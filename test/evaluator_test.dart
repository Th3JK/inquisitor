import 'package:flutter_test/flutter_test.dart';
import 'package:inquisitor/inquisitor.dart';
import 'package:inquisitor/src/evaluator.dart';
import 'package:inquisitor/src/model/payload.dart';

import 'support/fake_backend.dart';

void main() {
  InquisitorState evaluate({
    String? state,
    String? version,
    required String? current,
    InquisitorPlatform platform = InquisitorPlatform.ios,
    Map<InquisitorPlatform, String> minimumVersions =
        const <InquisitorPlatform, String>{InquisitorPlatform.ios: '2.0.0'},
  }) => InquisitorEvaluator.evaluate(
    payload: InquisitorPayload.parse(
      state: state ?? stateBody(),
      version: version ?? versionBody(),
    ),
    currentVersion: AppVersion.tryParse(current),
    platform: platform,
    source: InquisitorSource.network,
    storeUrls: const <InquisitorPlatform, String>{
      InquisitorPlatform.ios: 'https://apps.apple.com/app/id1',
    },
    minimumVersions: minimumVersions,
  );

  group('version tiers', () {
    final version = versionBody(ios: '2.4.0');

    test('current version is ok', () {
      final state = evaluate(version: version, current: '2.4.0');
      expect(state.verdict, InquisitorVerdict.ok);
      expect(state.isBlocking, isFalse);
    });

    test('a newer build than the server knows about is still ok', () {
      final state = evaluate(version: version, current: '2.5.0');
      expect(state.verdict, InquisitorVerdict.ok);
    });

    test('below latest but above minimum is an optional update', () {
      final state = evaluate(version: version, current: '2.3.0');
      expect(state.verdict, InquisitorVerdict.updateAvailable);
      expect(state.latestVersion.toString(), '2.4.0');
      expect(state.storeUrl, 'https://apps.apple.com/app/id1');
      expect(state.isBlocking, isFalse);
    });

    test('below the app-side minimum is a forced update', () {
      final state = evaluate(version: version, current: '1.9.0');
      expect(state.verdict, InquisitorVerdict.updateRequired);
      expect(state.minimumVersion.toString(), '2.0.0');
      expect(state.isBlocking, isTrue);
    });

    test('no minimum configured means no forced update', () {
      final state = evaluate(
        version: version,
        current: '1.0.0',
        minimumVersions: const <InquisitorPlatform, String>{},
      );
      expect(state.verdict, InquisitorVerdict.updateAvailable);
    });

    test('an unreadable local version enforces nothing', () {
      final state = evaluate(version: version, current: null);
      expect(state.verdict, InquisitorVerdict.ok);
    });
  });

  group('per-platform staggering', () {
    final version = versionBody(ios: '2.4.0', android: '2.3.0');

    test('prompts on iOS but not on Android', () {
      expect(
        evaluate(version: version, current: '2.3.0').verdict,
        InquisitorVerdict.updateAvailable,
      );
      expect(
        evaluate(
          version: version,
          current: '2.3.0',
          platform: InquisitorPlatform.android,
        ).verdict,
        InquisitorVerdict.ok,
      );
    });

    test('a platform the server does not list is ok', () {
      final state = evaluate(
        version: version,
        current: '1.0.0',
        platform: InquisitorPlatform.web,
      );
      expect(state.verdict, InquisitorVerdict.ok);
      expect(state.latestVersion, isNull);
    });
  });

  group('kill switch', () {
    test('outranks a forced update', () {
      final state = evaluate(
        state: stateBody(killSwitch: true),
        current: '1.0.0',
      );
      expect(state.verdict, InquisitorVerdict.blocked);
      expect(state.isBlocking, isTrue);
    });

    test('applies to every platform', () {
      for (final platform in InquisitorPlatform.values) {
        final state = evaluate(
          state: stateBody(killSwitch: true),
          current: '9.9.9',
          platform: platform,
        );
        expect(state.verdict, InquisitorVerdict.blocked, reason: '$platform');
      }
    });
  });

  group('flags', () {
    test('travel with an ok verdict', () {
      final state = evaluate(state: stateBody(unlocked: true), current: '2.3.0');
      expect(state.isFlagOn('Unlocked'), isTrue);
    });

    test('travel with a blocked verdict', () {
      final state = evaluate(
        state: stateBody(unlocked: true, killSwitch: true),
        current: '2.3.0',
      );
      expect(state.verdict, InquisitorVerdict.blocked);
      expect(state.isFlagOn('Unlocked'), isTrue);
    });

    test('a locked flag does not block', () {
      final state = evaluate(state: stateBody(), current: '2.3.0');
      expect(state.isFlagOn('Unlocked'), isFalse);
      expect(state.isBlocking, isFalse);
    });
  });

  test('carries source, timestamp and error through', () {
    final fetchedAt = DateTime.utc(2026, 8, 11);
    final error = StateError('stale');
    final state = InquisitorEvaluator.evaluate(
      payload: InquisitorPayload.parse(
        state: stateBody(),
        version: versionBody(),
      ),
      currentVersion: AppVersion.tryParse('2.3.0'),
      platform: InquisitorPlatform.ios,
      source: InquisitorSource.cache,
      fetchedAt: fetchedAt,
      error: error,
    );
    expect(state.source, InquisitorSource.cache);
    expect(state.fetchedAt, fetchedAt);
    expect(state.error, same(error));
  });
}
