import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'cache/cache.dart';
import 'model/app_version.dart';
import 'model/inquisitor_platform.dart';
import 'policies.dart';

/// Supplies the version of the running app.
///
/// Defaults to `package_info_plus`. Override it in tests, or when the version
/// lives somewhere else — a build-time constant, say.
typedef VersionProvider = Future<AppVersion?> Function();

/// Reports internal failures that Inquisitor swallowed.
typedef InquisitorErrorHandler = void Function(Object error, StackTrace stack);

/// Told whether a flag is on — once when its value is first known, then on
/// every change.
typedef InquisitorFlagListener = void Function(bool isOn);

/// Everything Inquisitor needs to run.
@immutable
class InquisitorConfig {
  /// Creates a configuration.
  const InquisitorConfig({
    required this.stateUrl,
    required this.versionUrl,
    this.httpClient,
    this.headers = const <String, String>{},
    this.timeout = const Duration(seconds: 10),
    this.storeUrls = const <InquisitorPlatform, String>{},
    this.minimumVersions = const <InquisitorPlatform, String>{},
    this.flagListeners = const <String, InquisitorFlagListener>{},
    this.cache,
    this.noDataPolicy = NoDataPolicy.allow,
    this.cacheTtl = const Duration(minutes: 15),
    this.cacheMaxAge,
    this.refreshOnResume = true,
    this.minRefreshInterval = const Duration(minutes: 5),
    this.nagInterval,
    this.versionProvider,
    this.platformResolver,
    this.clock,
    this.onError,
  });

  /// The state endpoint, serving
  /// `[{"flag": "Unlocked", "state": "1"}, {"flag": "KillSwitch", "state": "0"}]`.
  final Uri stateUrl;

  /// The version endpoint, serving
  /// `[{"device": "Android", "version": "1.0.0"}, {"device": "Apple", "version": "1.0.0"}]`.
  final Uri versionUrl;

  /// The HTTP client to fetch with. Pass one to reuse the app's connection
  /// pool; it is not closed on dispose.
  final http.Client? httpClient;

  /// Extra request headers sent to both endpoints, for example an API key.
  final Map<String, String> headers;

  /// How long to wait for each request before giving up.
  final Duration timeout;

  /// Store URLs per platform, since the server carries none.
  final Map<InquisitorPlatform, String> storeUrls;

  /// Minimum supported versions per platform, such as `'1.0.0'`. Anything
  /// below is blocked behind a forced update. The server only advertises the
  /// latest version, so this lives in the app.
  final Map<InquisitorPlatform, String> minimumVersions;

  /// Listeners per flag name, for example
  /// `{'Unlocked': (isOn) => premium.value = isOn}`.
  ///
  /// Each is called once the flag's value is first known — from cache or
  /// network — and again whenever it changes. Names are compared without case.
  /// Add more at runtime with `Inquisitor.addFlagListener`.
  final Map<String, InquisitorFlagListener> flagListeners;

  /// Where responses are persisted. Defaults to a `SharedPreferences`-backed
  /// cache namespaced under `inquisitor`.
  final InquisitorCache? cache;

  /// What to do when the server is unreachable and nothing is cached.
  final NoDataPolicy noDataPolicy;

  /// How long a cached response is considered fresh.
  ///
  /// Past this age the cached verdict is still applied immediately, but a
  /// refresh is started in the background.
  final Duration cacheTtl;

  /// How long a cached response stays usable at all.
  ///
  /// `null` — the default — means a cached response never hard-expires, so an
  /// app that has been offline for a month still gets its last known verdict.
  /// Set it to force [noDataPolicy] once the cache is this old.
  final Duration? cacheMaxAge;

  /// Whether to refresh when the app returns to the foreground.
  final bool refreshOnResume;

  /// The shortest gap between two automatic refreshes.
  ///
  /// Does not apply to `refresh(force: true)`.
  final Duration minRefreshInterval;

  /// How long a dismissed optional-update prompt stays dismissed.
  ///
  /// `null` — the default — means a given version is only ever prompted once;
  /// the prompt returns when the server advertises a newer one.
  final Duration? nagInterval;

  /// Supplies the running app's version.
  final VersionProvider? versionProvider;

  /// Supplies the platform to evaluate rules for. Defaults to the real one.
  final PlatformResolver? platformResolver;

  /// Supplies the current time. Override for deterministic tests.
  final DateTime Function()? clock;

  /// Called for every error Inquisitor absorbs — failed fetches, unreadable
  /// responses, cache problems, throwing flag listeners. Hook your logger up
  /// here; without it, failures are silent apart from `state.error`.
  final InquisitorErrorHandler? onError;
}
