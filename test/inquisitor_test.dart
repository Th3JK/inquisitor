import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inquisitor/inquisitor.dart';

import 'support/fake_backend.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 12);

  Inquisitor build({
    required FakeBackend backend,
    InquisitorCache? cache,
    NoDataPolicy policy = NoDataPolicy.allow,
    String? version = '2.3.0',
    Map<InquisitorPlatform, String> minimumVersions =
        const <InquisitorPlatform, String>{},
    Map<String, InquisitorFlagListener> flagListeners =
        const <String, InquisitorFlagListener>{},
    Duration cacheTtl = Duration.zero,
    Duration? cacheMaxAge,
    Duration minRefreshInterval = const Duration(minutes: 5),
    Duration? nagInterval,
    DateTime Function()? clock,
    InquisitorErrorHandler? onError,
  }) => Inquisitor(
    config: InquisitorConfig(
      stateUrl: stateUrl,
      versionUrl: versionUrl,
      httpClient: backend.client,
      minimumVersions: minimumVersions,
      flagListeners: flagListeners,
      cache: cache ?? InMemoryCache(),
      noDataPolicy: policy,
      cacheTtl: cacheTtl,
      cacheMaxAge: cacheMaxAge,
      minRefreshInterval: minRefreshInterval,
      nagInterval: nagInterval,
      refreshOnResume: false,
      versionProvider: () async => AppVersion.tryParse(version),
      platformResolver: () => InquisitorPlatform.ios,
      clock: clock ?? () => now,
      onError: onError ?? (_, _) {},
    ),
  );

  group('start', () {
    test('publishes the network verdict', () async {
      final inquisitor = build(
        backend: FakeBackend(version: versionBody(ios: '2.4.0')),
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      expect(inquisitor.state.verdict, InquisitorVerdict.updateAvailable);
      expect(inquisitor.state.source, InquisitorSource.network);
      expect(inquisitor.isReady, isTrue);
    });

    test('is idempotent', () async {
      final backend = FakeBackend();
      final inquisitor = build(backend: backend);
      addTearDown(inquisitor.dispose);

      await Future.wait(<Future<void>>[
        inquisitor.start(),
        inquisitor.start(),
        inquisitor.start(),
      ]);

      expect(backend.calls, 1);
    });

    test('applies the cached verdict before the network answers', () async {
      final cache = InMemoryCache();
      await cache.write(
        state: stateBody(killSwitch: true),
        version: versionBody(),
        fetchedAt: now.subtract(const Duration(hours: 1)),
      );

      final backend = FakeBackend(version: versionBody(ios: '2.4.0'))
        ..gate = Completer<void>();
      final inquisitor = build(backend: backend, cache: cache);
      addTearDown(inquisitor.dispose);

      final verdicts = <InquisitorVerdict>[];
      final subscription = inquisitor.stream.listen(
        (state) => verdicts.add(state.verdict),
      );
      addTearDown(subscription.cancel);

      final started = inquisitor.start();
      await pumpEventQueue();

      // The cached kill switch is already in effect while the request is
      // still in flight.
      expect(inquisitor.state.verdict, InquisitorVerdict.blocked);
      expect(inquisitor.state.source, InquisitorSource.cache);

      backend.gate!.complete();
      await started;
      await pumpEventQueue();

      expect(inquisitor.state.verdict, InquisitorVerdict.updateAvailable);
      expect(verdicts, <InquisitorVerdict>[
        InquisitorVerdict.ok,
        InquisitorVerdict.blocked,
        InquisitorVerdict.updateAvailable,
      ]);
    });

    test('skips the network while the cache is inside its TTL', () async {
      final cache = InMemoryCache();
      await cache.write(
        state: stateBody(),
        version: versionBody(ios: '2.4.0'),
        fetchedAt: now,
      );

      final backend = FakeBackend();
      final inquisitor = build(
        backend: backend,
        cache: cache,
        cacheTtl: const Duration(minutes: 15),
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      expect(backend.calls, 0);
      expect(inquisitor.state.verdict, InquisitorVerdict.updateAvailable);
      expect(inquisitor.state.source, InquisitorSource.cache);
    });

    test('discards a cache past cacheMaxAge', () async {
      final cache = InMemoryCache();
      await cache.write(
        state: stateBody(killSwitch: true),
        version: versionBody(),
        fetchedAt: now.subtract(const Duration(days: 30)),
      );

      final inquisitor = build(
        backend: FakeBackend(error: StateError('offline')),
        cache: cache,
        cacheMaxAge: const Duration(days: 7),
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      // The stale kill switch is gone rather than applied forever.
      expect(inquisitor.state.verdict, InquisitorVerdict.ok);
      expect(inquisitor.state.source, InquisitorSource.fallback);
    });
  });

  group('failures', () {
    test('never throws out of start', () async {
      final inquisitor = build(backend: FakeBackend(error: StateError('boom')));
      addTearDown(inquisitor.dispose);

      await expectLater(inquisitor.start(), completes);
      expect(inquisitor.state.error, isStateError);
    });

    test('treats a non-2xx response as a failure', () async {
      final backend = FakeBackend()..statusCode = 500;
      final inquisitor = build(backend: backend);
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      expect(inquisitor.state.source, InquisitorSource.fallback);
      expect(inquisitor.state.error, isNotNull);
    });

    test('keeps serving the cached verdict when a refresh fails', () async {
      final cache = InMemoryCache();
      await cache.write(
        state: stateBody(killSwitch: true),
        version: versionBody(),
        fetchedAt: now.subtract(const Duration(hours: 1)),
      );

      final inquisitor = build(
        backend: FakeBackend(error: StateError('offline')),
        cache: cache,
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      expect(inquisitor.state.verdict, InquisitorVerdict.blocked);
      expect(inquisitor.state.source, InquisitorSource.cache);
      expect(inquisitor.state.error, isStateError);
    });

    test('an unreadable response does not displace a good cache', () async {
      final cache = InMemoryCache();
      await cache.write(
        state: stateBody(killSwitch: true),
        version: versionBody(),
        fetchedAt: now.subtract(const Duration(hours: 1)),
      );

      final inquisitor = build(
        backend: FakeBackend(state: '<html>Bad gateway</html>'),
        cache: cache,
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      expect(inquisitor.state.verdict, InquisitorVerdict.blocked);
      expect(inquisitor.state.error, isFormatException);
      expect(
        (await cache.read())!.state,
        stateBody(killSwitch: true),
      );
    });

    test('drops a cached body this build can no longer parse', () async {
      final cache = InMemoryCache();
      await cache.write(
        state: 'this was valid once',
        version: 'this was valid once',
        fetchedAt: now.subtract(const Duration(hours: 1)),
      );

      final inquisitor = build(
        backend: FakeBackend(error: StateError('offline')),
        cache: cache,
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      expect(inquisitor.state.source, InquisitorSource.fallback);
      expect(await cache.read(), isNull);
    });
  });

  group('no-data policy', () {
    Future<InquisitorState> stateUnder(NoDataPolicy policy) async {
      final inquisitor = build(
        backend: FakeBackend(error: StateError('offline')),
        policy: policy,
      );
      addTearDown(inquisitor.dispose);
      await inquisitor.start();
      return inquisitor.state;
    }

    test('allow lets the user in, with every flag off', () async {
      final state = await stateUnder(NoDataPolicy.allow);
      expect(state.verdict, InquisitorVerdict.ok);
      expect(state.isBlocking, isFalse);
      expect(state.isFlagOn('Unlocked'), isFalse);
      expect(state.error, isStateError);
    });

    test('block keeps the user out', () async {
      final state = await stateUnder(NoDataPolicy.block);
      expect(state.verdict, InquisitorVerdict.blocked);
      expect(state.source, InquisitorSource.fallback);
      expect(state.isBlocking, isTrue);
    });
  });

  group('refresh', () {
    test('throttles automatic refreshes but not forced ones', () async {
      final backend = FakeBackend();
      final inquisitor = build(
        backend: backend,
        minRefreshInterval: const Duration(minutes: 5),
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();
      expect(backend.calls, 1);

      await inquisitor.refresh();
      expect(backend.calls, 1, reason: 'inside the throttle window');

      await inquisitor.refresh(force: true);
      expect(backend.calls, 2);
    });

    test('shares one request between concurrent callers', () async {
      final backend = FakeBackend()..gate = Completer<void>();
      final inquisitor = build(backend: backend);
      addTearDown(inquisitor.dispose);

      final started = inquisitor.start();
      await pumpEventQueue();
      final second = inquisitor.refresh(force: true);

      backend.gate!.complete();
      await Future.wait(<Future<void>>[started, second]);

      expect(backend.calls, 1);
    });

    test('caches both response bodies', () async {
      final cache = InMemoryCache();
      final inquisitor = build(
        backend: FakeBackend(
          state: stateBody(unlocked: true),
          version: versionBody(ios: '2.4.0'),
        ),
        cache: cache,
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      final cached = await cache.read();
      expect(cached!.state, stateBody(unlocked: true));
      expect(cached.version, versionBody(ios: '2.4.0'));
    });
  });

  group('stream', () {
    test('replays the current state to every new listener', () async {
      final inquisitor = build(
        backend: FakeBackend(version: versionBody(ios: '2.4.0')),
      );
      addTearDown(inquisitor.dispose);
      await inquisitor.start();

      await expectLater(
        inquisitor.stream.first,
        completion(
          isA<InquisitorState>().having(
            (state) => state.verdict,
            'verdict',
            InquisitorVerdict.updateAvailable,
          ),
        ),
      );
    });

    test('does not re-emit an unchanged state', () async {
      final backend = FakeBackend(version: versionBody(ios: '2.4.0'));
      final inquisitor = build(backend: backend);
      addTearDown(inquisitor.dispose);

      final states = <InquisitorState>[];
      final subscription = inquisitor.stream.listen(states.add);
      addTearDown(subscription.cancel);

      await inquisitor.start();
      await inquisitor.refresh(force: true);
      await inquisitor.refresh(force: true);
      await pumpEventQueue();

      expect(backend.calls, 3);
      expect(states.length, 2, reason: 'placeholder, then the verdict');
    });

    test('re-emits when only a flag changes', () async {
      final backend = FakeBackend();
      final inquisitor = build(backend: backend);
      addTearDown(inquisitor.dispose);
      await inquisitor.start();

      final next = inquisitor.stream.skip(1).first;
      backend.state = stateBody(unlocked: true);
      await inquisitor.refresh(force: true);

      expect((await next).isFlagOn('Unlocked'), isTrue);
    });
  });

  group('flag listeners', () {
    test('a configured listener hears the first value and each change', () async {
      final heard = <bool>[];
      final backend = FakeBackend(state: stateBody(unlocked: true));
      final inquisitor = build(
        backend: backend,
        flagListeners: <String, InquisitorFlagListener>{'Unlocked': heard.add},
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();
      expect(heard, <bool>[true]);

      backend.state = stateBody();
      await inquisitor.refresh(force: true);
      expect(heard, <bool>[true, false]);

      // An unchanged flag says nothing, even when other data changes.
      backend.version = versionBody(ios: '2.4.0');
      await inquisitor.refresh(force: true);
      expect(heard, <bool>[true, false]);
    });

    test('hears the cached value before the network answers', () async {
      final cache = InMemoryCache();
      await cache.write(
        state: stateBody(unlocked: true),
        version: versionBody(),
        fetchedAt: now.subtract(const Duration(hours: 1)),
      );
      final heard = <bool>[];
      final backend = FakeBackend(state: stateBody(unlocked: true))
        ..gate = Completer<void>();
      final inquisitor = build(
        backend: backend,
        cache: cache,
        flagListeners: <String, InquisitorFlagListener>{'Unlocked': heard.add},
      );
      addTearDown(inquisitor.dispose);

      final started = inquisitor.start();
      await pumpEventQueue();
      expect(heard, <bool>[true]);

      backend.gate!.complete();
      await started;
      expect(heard, <bool>[true], reason: 'the network agreed with the cache');
    });

    test('hears "off" when there is no data at all', () async {
      final heard = <bool>[];
      final inquisitor = build(
        backend: FakeBackend(error: StateError('offline')),
        flagListeners: <String, InquisitorFlagListener>{'Unlocked': heard.add},
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      expect(heard, <bool>[false]);
    });

    test('names are compared without case', () async {
      final heard = <bool>[];
      final inquisitor = build(
        backend: FakeBackend(state: stateBody(unlocked: true)),
        flagListeners: <String, InquisitorFlagListener>{'unlocked': heard.add},
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      expect(heard, <bool>[true]);
    });

    test('addFlagListener fires at once and its remover stops it', () async {
      final backend = FakeBackend(state: stateBody(unlocked: true));
      final inquisitor = build(backend: backend);
      addTearDown(inquisitor.dispose);
      await inquisitor.start();

      final heard = <bool>[];
      final remove = inquisitor.addFlagListener('Unlocked', heard.add);
      expect(heard, <bool>[true]);

      backend.state = stateBody();
      await inquisitor.refresh(force: true);
      expect(heard, <bool>[true, false]);

      remove();
      backend.state = stateBody(unlocked: true);
      await inquisitor.refresh(force: true);
      expect(heard, <bool>[true, false]);
    });

    test('fireImmediately: false hears changes only', () async {
      final backend = FakeBackend(state: stateBody(unlocked: true));
      final inquisitor = build(backend: backend);
      addTearDown(inquisitor.dispose);
      await inquisitor.start();

      final heard = <bool>[];
      inquisitor.addFlagListener(
        'Unlocked',
        heard.add,
        fireImmediately: false,
      );
      expect(heard, isEmpty);

      backend.state = stateBody();
      await inquisitor.refresh(force: true);
      expect(heard, <bool>[false]);
    });

    test('added before start, it hears the first value', () async {
      final inquisitor = build(
        backend: FakeBackend(state: stateBody(unlocked: true)),
      );
      addTearDown(inquisitor.dispose);

      final heard = <bool>[];
      inquisitor.addFlagListener('Unlocked', heard.add);
      expect(heard, isEmpty);

      await inquisitor.start();
      expect(heard, <bool>[true]);
    });

    test('a throwing listener is reported and does not stop the others', () async {
      final errors = <Object>[];
      final heard = <bool>[];
      final inquisitor = build(
        backend: FakeBackend(state: stateBody(unlocked: true)),
        onError: (error, _) => errors.add(error),
        flagListeners: <String, InquisitorFlagListener>{
          'Unlocked': (_) => throw StateError('listener broke'),
          'KillSwitch': heard.add,
        },
      );
      addTearDown(inquisitor.dispose);

      await inquisitor.start();

      expect(errors, <Matcher>[isStateError]);
      expect(heard, <bool>[false]);
      expect(inquisitor.isFlagOn('Unlocked'), isTrue);
    });

    test('watchFlag emits distinct values', () async {
      final backend = FakeBackend();
      final inquisitor = build(backend: backend);
      addTearDown(inquisitor.dispose);
      await inquisitor.start();

      final values = <bool>[];
      final subscription = inquisitor.watchFlag('Unlocked').listen(values.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      backend.state = stateBody(unlocked: true);
      await inquisitor.refresh(force: true);
      backend.version = versionBody(ios: '2.4.0');
      await inquisitor.refresh(force: true);
      await pumpEventQueue();

      expect(values, <bool>[false, true]);
    });
  });

  group('update prompts', () {
    test('prompts once per advertised version by default', () async {
      final inquisitor = build(
        backend: FakeBackend(version: versionBody(ios: '2.4.0')),
      );
      addTearDown(inquisitor.dispose);
      await inquisitor.start();

      expect(await inquisitor.shouldPromptUpdate(), isTrue);
      await inquisitor.dismissUpdate();
      expect(await inquisitor.shouldPromptUpdate(), isFalse);
    });

    test('prompts again once nagInterval has elapsed', () async {
      var clock = now;
      final inquisitor = build(
        backend: FakeBackend(version: versionBody(ios: '2.4.0')),
        nagInterval: const Duration(days: 3),
        clock: () => clock,
      );
      addTearDown(inquisitor.dispose);
      await inquisitor.start();

      await inquisitor.dismissUpdate();
      expect(await inquisitor.shouldPromptUpdate(), isFalse);

      clock = now.add(const Duration(days: 4));
      expect(await inquisitor.shouldPromptUpdate(), isTrue);
    });

    test('a newer version reopens the prompt', () async {
      final backend = FakeBackend(version: versionBody(ios: '2.4.0'));
      final inquisitor = build(backend: backend);
      addTearDown(inquisitor.dispose);

      await inquisitor.start();
      await inquisitor.dismissUpdate();
      expect(await inquisitor.shouldPromptUpdate(), isFalse);

      backend.version = versionBody(ios: '2.5.0');
      await inquisitor.refresh(force: true);

      expect(await inquisitor.shouldPromptUpdate(), isTrue);
    });

    test('never prompts when the update is forced', () async {
      final inquisitor = build(
        backend: FakeBackend(version: versionBody(ios: '9.0.0')),
        minimumVersions: const <InquisitorPlatform, String>{
          InquisitorPlatform.ios: '9.0.0',
        },
      );
      addTearDown(inquisitor.dispose);
      await inquisitor.start();

      expect(inquisitor.state.verdict, InquisitorVerdict.updateRequired);
      expect(await inquisitor.shouldPromptUpdate(), isFalse);
    });
  });

  test('reset clears the cache, the dismissals and refetches', () async {
    final backend = FakeBackend(version: versionBody(ios: '2.4.0'));
    final inquisitor = build(backend: backend);
    addTearDown(inquisitor.dispose);

    await inquisitor.start();
    await inquisitor.dismissUpdate();
    expect(await inquisitor.shouldPromptUpdate(), isFalse);

    await inquisitor.reset();

    expect(backend.calls, 2);
    expect(await inquisitor.shouldPromptUpdate(), isTrue);
  });

  test('dispose stops fetching and silences flag listeners', () async {
    final heard = <bool>[];
    final backend = FakeBackend();
    final inquisitor = build(
      backend: backend,
      flagListeners: <String, InquisitorFlagListener>{'Unlocked': heard.add},
    );

    await inquisitor.start();
    await inquisitor.dispose();

    backend.state = stateBody(unlocked: true);
    await inquisitor.refresh(force: true);

    expect(backend.calls, 1);
    expect(heard, <bool>[false]);
  });
}
