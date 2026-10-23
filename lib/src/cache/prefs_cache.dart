import 'package:shared_preferences/shared_preferences.dart';

import 'cache.dart';

/// The default [InquisitorCache], backed by `SharedPreferences`.
///
/// Every key is namespaced by [keyPrefix], so several Inquisitor instances
/// (staging and production, say) can share one preferences store without
/// colliding.
class SharedPreferencesCache extends InquisitorCache {
  /// Creates a cache.
  ///
  /// Pass [preferences] to reuse an instance the app already holds; otherwise
  /// one is obtained lazily on first use.
  SharedPreferencesCache({
    this.keyPrefix = 'inquisitor',
    SharedPreferences? preferences,
  })
  // A named parameter cannot be private, so an initializing formal is not an
  // option for this private field.
  // ignore: prefer_initializing_formals
  : _preferences = preferences;

  /// Prefix applied to every key this cache writes.
  final String keyPrefix;

  SharedPreferences? _preferences;
  Future<SharedPreferences>? _pending;

  String get _stateKey => '$keyPrefix.state';
  String get _versionKey => '$keyPrefix.version';
  String get _fetchedAtKey => '$keyPrefix.fetched_at';
  String _dismissedKey(String version) => '$keyPrefix.dismissed.$version';

  Future<SharedPreferences> get _prefs async {
    final cached = _preferences;
    if (cached != null) return cached;
    // Guard against a stampede of concurrent first calls.
    return _preferences = await (_pending ??= SharedPreferences.getInstance());
  }

  @override
  Future<CachedPayload?> read() async {
    final prefs = await _prefs;
    final state = prefs.getString(_stateKey);
    final version = prefs.getString(_versionKey);
    final fetchedAtMillis = prefs.getInt(_fetchedAtKey);
    if (state == null || version == null || fetchedAtMillis == null) {
      return null;
    }
    return CachedPayload(
      state: state,
      version: version,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis, isUtc: true),
    );
  }

  @override
  Future<void> write({
    required String state,
    required String version,
    required DateTime fetchedAt,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_stateKey, state);
    await prefs.setString(_versionKey, version);
    await prefs.setInt(_fetchedAtKey, fetchedAt.toUtc().millisecondsSinceEpoch);
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_stateKey);
    await prefs.remove(_versionKey);
    await prefs.remove(_fetchedAtKey);
  }

  @override
  Future<DateTime?> dismissedAt(String version) async {
    final prefs = await _prefs;
    final millis = prefs.getInt(_dismissedKey(version));
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  @override
  Future<void> markDismissed(String version, DateTime at) async {
    final prefs = await _prefs;
    await prefs.setInt(
      _dismissedKey(version),
      at.toUtc().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> clearDismissals() async {
    final prefs = await _prefs;
    final prefix = '$keyPrefix.dismissed.';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      await prefs.remove(key);
    }
  }
}

/// An [InquisitorCache] that keeps everything in memory.
///
/// Useful in tests and for apps that deliberately want no persistence — note
/// that without persistence, every cold start with no network falls through to
/// the no-data policy.
class InMemoryCache extends InquisitorCache {
  /// Creates an empty cache.
  InMemoryCache();

  CachedPayload? _entry;
  final Map<String, DateTime> _dismissals = <String, DateTime>{};

  @override
  Future<CachedPayload?> read() async => _entry;

  @override
  Future<void> write({
    required String state,
    required String version,
    required DateTime fetchedAt,
  }) async {
    _entry = CachedPayload(state: state, version: version, fetchedAt: fetchedAt);
  }

  @override
  Future<void> clear() async => _entry = null;

  @override
  Future<DateTime?> dismissedAt(String version) async => _dismissals[version];

  @override
  Future<void> markDismissed(String version, DateTime at) async =>
      _dismissals[version] = at;

  @override
  Future<void> clearDismissals() async => _dismissals.clear();
}
