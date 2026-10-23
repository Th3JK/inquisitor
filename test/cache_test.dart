import 'package:flutter_test/flutter_test.dart';
import 'package:inquisitor/inquisitor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 8, 11, 12);

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('SharedPreferencesCache', () {
    test('round-trips a response', () async {
      final cache = SharedPreferencesCache();

      expect(await cache.read(), isNull);
      await cache.write(state: '[1]', version: '[2]', fetchedAt: now);

      final entry = await cache.read();
      expect(entry!.state, '[1]');
      expect(entry.version, '[2]');
      expect(entry.fetchedAt, now);
    });

    test('reads nothing unless both bodies are stored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'inquisitor.state': '[]',
        'inquisitor.fetched_at': now.millisecondsSinceEpoch,
      });
      expect(await SharedPreferencesCache().read(), isNull);
    });

    test('clear removes the response but keeps dismissals', () async {
      final cache = SharedPreferencesCache();
      await cache.write(state: '[]', version: '[]', fetchedAt: now);
      await cache.markDismissed('2.4.0', now);

      await cache.clear();

      expect(await cache.read(), isNull);
      expect(await cache.dismissedAt('2.4.0'), now);
    });

    test('records and clears dismissals per version', () async {
      final cache = SharedPreferencesCache();

      expect(await cache.dismissedAt('2.4.0'), isNull);
      await cache.markDismissed('2.4.0', now);
      expect(await cache.dismissedAt('2.4.0'), now);
      expect(await cache.dismissedAt('2.5.0'), isNull);

      await cache.clearDismissals();
      expect(await cache.dismissedAt('2.4.0'), isNull);
    });

    test('keeps instances with different prefixes apart', () async {
      final production = SharedPreferencesCache();
      final staging = SharedPreferencesCache(keyPrefix: 'inquisitor_staging');

      await production.write(state: '["prod"]', version: '[]', fetchedAt: now);
      await staging.write(state: '["staging"]', version: '[]', fetchedAt: now);

      expect((await production.read())!.state, '["prod"]');
      expect((await staging.read())!.state, '["staging"]');
    });

    test('leaves unrelated preference keys alone', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'user_theme': 'dark',
      });
      final cache = SharedPreferencesCache();
      await cache.write(state: '[]', version: '[]', fetchedAt: now);
      await cache.clear();
      await cache.clearDismissals();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_theme'), 'dark');
    });
  });

  group('age', () {
    test('measures against the supplied clock', () {
      final entry = CachedPayload(
        state: '[]',
        version: '[]',
        fetchedAt: now.subtract(const Duration(hours: 3)),
      );
      expect(entry.age(now), const Duration(hours: 3));
    });
  });

  group('InMemoryCache', () {
    test('behaves like the persistent one', () async {
      final cache = InMemoryCache();

      expect(await cache.read(), isNull);
      await cache.write(state: '[1]', version: '[2]', fetchedAt: now);
      expect((await cache.read())!.state, '[1]');
      expect((await cache.read())!.version, '[2]');

      await cache.markDismissed('2.4.0', now);
      expect(await cache.dismissedAt('2.4.0'), now);

      await cache.clear();
      expect(await cache.read(), isNull);
      expect(await cache.dismissedAt('2.4.0'), now);
    });
  });
}
