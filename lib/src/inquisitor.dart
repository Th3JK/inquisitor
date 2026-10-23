import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'cache/cache.dart';
import 'cache/prefs_cache.dart';
import 'client.dart';
import 'config.dart';
import 'evaluator.dart';
import 'model/app_version.dart';
import 'model/inquisitor_platform.dart';
import 'model/payload.dart';
import 'model/state.dart';
import 'policies.dart';

/// Watches the state and version endpoints and reports what the running app
/// is allowed to do.
///
/// Create one instance for the lifetime of the app, [start] it during
/// bootstrap, and read the answer from [state] or [stream]:
///
/// ```dart
/// final inquisitor = Inquisitor(
///   config: InquisitorConfig(
///     stateUrl: Uri.parse('https://example.com/app_state.php'),
///     versionUrl: Uri.parse('https://example.com/app_version.php'),
///     flagListeners: {'Unlocked': (isOn) => premium.value = isOn},
///   ),
/// );
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await inquisitor.start();
///   runApp(MyApp());
/// }
/// ```
///
/// Nothing here throws. A failed fetch, an unparseable response, a broken
/// cache, a throwing flag listener — all of it is caught, reported through
/// `InquisitorConfig.onError`, and surfaced as [InquisitorState.error]. A kill
/// switch that crashes the app it is meant to protect would be worse than no
/// kill switch at all.
class Inquisitor {
  /// Creates an instance. Nothing happens until [start] is called.
  Inquisitor({required this.config})
    : _cache = config.cache ?? SharedPreferencesCache(),
      _client = InquisitorClient(
        stateUrl: config.stateUrl,
        versionUrl: config.versionUrl,
        headers: config.headers,
        timeout: config.timeout,
        client: config.httpClient,
      ) {
    for (final entry in config.flagListeners.entries) {
      _flagListeners.add(_FlagRegistration(entry.key, entry.value));
    }
  }

  /// The configuration this instance runs with.
  final InquisitorConfig config;

  final InquisitorCache _cache;
  final InquisitorClient _client;
  final StreamController<InquisitorState> _controller =
      StreamController<InquisitorState>.broadcast();
  final List<_FlagRegistration> _flagListeners = <_FlagRegistration>[];

  InquisitorState _current = InquisitorState.unknown();
  InquisitorPayload? _payload;
  AppVersion? _version;
  InquisitorPlatform _platform = InquisitorPlatform.unknown;

  Future<void>? _starting;
  Future<void>? _refreshing;
  DateTime? _lastRefreshAt;
  AppLifecycleListener? _lifecycleListener;
  bool _disposed = false;
  bool _ready = false;

  /// The verdict in effect right now.
  ///
  /// Safe to read before [start] completes: it reports
  /// [InquisitorVerdict.ok] until there is something better to say.
  InquisitorState get state => _current;

  /// The verdict over time.
  ///
  /// Every new listener immediately receives the current state, then each
  /// change after it. Identical consecutive states are not re-emitted.
  Stream<InquisitorState> get stream =>
      Stream<InquisitorState>.multi((StreamController<InquisitorState> emitter) {
        emitter.add(_current);
        final subscription = _controller.stream.listen(
          emitter.add,
          onError: emitter.addError,
          onDone: emitter.close,
        );
        emitter
          ..onPause = subscription.pause
          ..onResume = subscription.resume
          ..onCancel = subscription.cancel;
      });

  /// Whether [start] has been called.
  bool get isStarted => _starting != null;

  /// Whether the first evaluation has completed, so [state] reflects real data
  /// rather than the placeholder.
  bool get isReady => _ready;

  /// Whether the flag [name] is on right now. Names are compared without case.
  bool isFlagOn(String name) => _current.isFlagOn(name);

  /// Whether the flag [name] is on, over time.
  ///
  /// Replays the current value to every new listener, then emits only when it
  /// changes.
  Stream<bool> watchFlag(String name) =>
      stream.map((state) => state.isFlagOn(name)).distinct();

  /// Calls [listener] whenever the flag [name] changes, and returns a function
  /// that removes it again.
  ///
  /// With [fireImmediately] — the default — the listener also hears the
  /// current value: straight away once [isReady], otherwise as soon as the
  /// first value is known. Pass false to hear changes only.
  ///
  /// Listeners declared up front belong in `InquisitorConfig.flagListeners`.
  VoidCallback addFlagListener(
    String name,
    InquisitorFlagListener listener, {
    bool fireImmediately = true,
  }) {
    final registration = _FlagRegistration(name, listener);
    _flagListeners.add(registration);
    if (_ready) {
      final isOn = isFlagOn(name);
      if (fireImmediately) {
        _deliver(registration, isOn);
      } else {
        registration.delivered = isOn;
      }
    }
    return () => _flagListeners.remove(registration);
  }

  /// Resolves the app version and platform, applies any cached verdict, then
  /// refreshes from the server.
  ///
  /// Awaiting this before `runApp` guarantees the first frame already knows
  /// whether it may show the app. Calling it more than once is harmless — the
  /// original future is returned.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    _platform = (config.platformResolver ?? InquisitorPlatform.current)();
    _version = await _guard<AppVersion?>(_resolveVersion);
    // Filled in silently: learning our own version and platform tells a
    // listener nothing about what the app may do, and an ok -> ok emission is
    // just noise on the stream.
    _current = InquisitorState.unknown(
      currentVersion: _version,
      platform: _platform,
    );

    final cached = await _guard(_cache.read);
    final usable = cached != null && !_isBeyondMaxAge(cached);
    if (usable) {
      _applyCached(cached);
    }

    // A cache still inside its TTL is good enough for this launch; refreshing
    // is left to the resume hook or an explicit call.
    if (!usable || _isStale(cached)) {
      await refresh(force: true);
    }
    _ready = true;
    // The first verdict may equal the placeholder and never be published, so
    // make sure every flag listener has heard a value by now.
    _notifyFlags();
    _attachLifecycleListener();
  }

  /// Fetches both endpoints and republishes the verdict.
  ///
  /// Without [force], a refresh started within `InquisitorConfig.minRefreshInterval`
  /// of the last one is skipped. Concurrent calls share one request.
  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future<void>.value();
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;

    if (!force) {
      final last = _lastRefreshAt;
      if (last != null && _now().difference(last) < config.minRefreshInterval) {
        return Future<void>.value();
      }
    }

    final future = _refresh().whenComplete(() => _refreshing = null);
    return _refreshing = future;
  }

  Future<void> _refresh() async {
    _lastRefreshAt = _now();
    final cached = await _guard(_cache.read);

    try {
      final response = await _client.fetch();
      final fetchedAt = _now();
      // Parse before caching so a response this client cannot understand
      // never displaces a good cached one.
      final payload = InquisitorPayload.parse(
        state: response.state,
        version: response.version,
      );
      await _guard(
        () => _cache.write(
          state: response.state,
          version: response.version,
          fetchedAt: fetchedAt,
        ),
      );
      _applyPayload(payload, InquisitorSource.network, fetchedAt);
    } catch (error, stack) {
      _report(error, stack);
      _applyFailure(cached, error);
    }
  }

  /// Whether the optional-update prompt should be shown for [state].
  ///
  /// False unless the verdict is [InquisitorVerdict.updateAvailable] and the
  /// user has not dismissed this version — or has, but
  /// `InquisitorConfig.nagInterval` has since elapsed.
  Future<bool> shouldPromptUpdate([InquisitorState? state]) async {
    final subject = state ?? _current;
    if (subject.verdict != InquisitorVerdict.updateAvailable) return false;

    final version = subject.latestVersion?.toString();
    if (version == null) return false;

    final dismissedAt = await _guard(() => _cache.dismissedAt(version));
    if (dismissedAt == null) return true;

    final interval = config.nagInterval;
    if (interval == null) return false;
    return _now().difference(dismissedAt) >= interval;
  }

  /// Records that the user dismissed the optional-update prompt.
  Future<void> dismissUpdate([InquisitorState? state]) async {
    final version = (state ?? _current).latestVersion?.toString();
    if (version == null) return;
    await _guard(() => _cache.markDismissed(version, _now()));
  }

  /// Forgets the cached response and every dismissal, then refreshes.
  ///
  /// Intended for a debug menu; not something an app should do routinely.
  Future<void> reset() async {
    await _guard(_cache.clear);
    await _guard(_cache.clearDismissals);
    _payload = null;
    await refresh(force: true);
  }

  /// Releases the lifecycle listener, the HTTP client, the flag listeners and
  /// the stream.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _lifecycleListener?.dispose();
    _client.close();
    _flagListeners.clear();
    await _controller.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _applyCached(CachedPayload cached) {
    try {
      _applyPayload(
        InquisitorPayload.parse(state: cached.state, version: cached.version),
        InquisitorSource.cache,
        cached.fetchedAt,
      );
    } catch (error, stack) {
      _report(error, stack);
      // A cached body this build can no longer parse is worse than useless.
      unawaited(_guard(_cache.clear));
      _applyNoData(error);
    }
  }

  void _applyPayload(
    InquisitorPayload payload,
    InquisitorSource source,
    DateTime fetchedAt,
  ) {
    _payload = payload;
    _publish(_evaluate(payload, source, fetchedAt));
  }

  /// A refresh failed. Keep the last good verdict if there is one, annotated
  /// with the error; otherwise fall through to the policy.
  void _applyFailure(CachedPayload? cached, Object error) {
    final payload = _payload;
    if (payload != null && !(cached != null && _isBeyondMaxAge(cached))) {
      _publish(
        _evaluate(
          payload,
          InquisitorSource.cache,
          cached?.fetchedAt ?? _current.fetchedAt,
          error,
        ),
      );
      return;
    }
    _applyNoData(error);
  }

  void _applyNoData(Object? error) {
    _payload = null;
    _publish(
      InquisitorState(
        verdict: switch (config.noDataPolicy) {
          NoDataPolicy.allow => InquisitorVerdict.ok,
          NoDataPolicy.block => InquisitorVerdict.blocked,
        },
        currentVersion: _version,
        platform: _platform,
        source: InquisitorSource.fallback,
        error: error,
      ),
    );
  }

  InquisitorState _evaluate(
    InquisitorPayload payload,
    InquisitorSource source,
    DateTime? fetchedAt, [
    Object? error,
  ]) => InquisitorEvaluator.evaluate(
    payload: payload,
    currentVersion: _version,
    platform: _platform,
    source: source,
    storeUrls: config.storeUrls,
    minimumVersions: config.minimumVersions,
    fetchedAt: fetchedAt,
    error: error,
  );

  void _publish(InquisitorState next) {
    if (_disposed) return;
    if (next == _current) return;
    _current = next;
    if (!_controller.isClosed) _controller.add(next);
    _notifyFlags();
  }

  /// Tells each flag listener its flag's value, if it has not heard that value
  /// yet.
  void _notifyFlags() {
    // A copy, so a listener may remove itself — or add another — mid-loop.
    for (final registration in List.of(_flagListeners)) {
      if (_disposed) return;
      final isOn = _current.isFlagOn(registration.name);
      if (registration.delivered != isOn) _deliver(registration, isOn);
    }
  }

  void _deliver(_FlagRegistration registration, bool isOn) {
    registration.delivered = isOn;
    try {
      registration.listener(isOn);
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  bool _isStale(CachedPayload? cached) =>
      cached == null || cached.age(_now()) >= config.cacheTtl;

  bool _isBeyondMaxAge(CachedPayload cached) {
    final maxAge = config.cacheMaxAge;
    return maxAge != null && cached.age(_now()) >= maxAge;
  }

  void _attachLifecycleListener() {
    if (!config.refreshOnResume || _disposed || _lifecycleListener != null) {
      return;
    }
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(refresh()),
    );
  }

  Future<AppVersion?> _resolveVersion() async {
    final provider = config.versionProvider;
    if (provider != null) return provider();

    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.trim();
    return AppVersion.tryParse(
      build.isEmpty ? info.version : '${info.version}+$build',
    );
  }

  DateTime _now() => config.clock?.call() ?? DateTime.now();

  /// Runs [action], reporting and swallowing any failure.
  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stack) {
      _report(error, stack);
      return null;
    }
  }

  void _report(Object error, StackTrace stack) {
    final handler = config.onError;
    if (handler != null) {
      handler(error, stack);
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'inquisitor',
        silent: true,
      ),
    );
  }
}

/// One flag listener and the last value it was told.
class _FlagRegistration {
  _FlagRegistration(this.name, this.listener);

  final String name;
  final InquisitorFlagListener listener;

  /// The value last delivered, or `null` before the first delivery.
  bool? delivered;
}
