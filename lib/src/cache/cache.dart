import 'package:meta/meta.dart';

/// A server response held on disk, with the metadata needed to decide whether
/// it is still good enough to use.
@immutable
class CachedPayload {
  /// Creates a cache entry.
  const CachedPayload({
    required this.state,
    required this.version,
    required this.fetchedAt,
  });

  /// The state endpoint's body, exactly as fetched.
  final String state;

  /// The version endpoint's body, exactly as fetched.
  final String version;

  /// When it was fetched.
  final DateTime fetchedAt;

  /// How old this entry is at [now].
  Duration age(DateTime now) => now.difference(fetchedAt);
}

/// Persists the last server response and the user's update-prompt dismissals.
///
/// Swap in your own implementation to store this somewhere other than
/// `SharedPreferences` — secure storage, for instance, if the payload is
/// sensitive.
abstract class InquisitorCache {
  /// Allows subclasses to have const constructors.
  const InquisitorCache();

  /// Reads the cached response, or `null` when nothing is stored.
  Future<CachedPayload?> read();

  /// Stores the [state] and [version] bodies as the current response.
  Future<void> write({
    required String state,
    required String version,
    required DateTime fetchedAt,
  });

  /// Drops the stored response. Dismissal records are left alone.
  Future<void> clear();

  /// When the update prompt for [version] was last dismissed, or `null` if it
  /// never was.
  Future<DateTime?> dismissedAt(String version);

  /// Records that the update prompt for [version] was dismissed at [at].
  Future<void> markDismissed(String version, DateTime at);

  /// Forgets every dismissal, so prompts show again.
  Future<void> clearDismissals();
}
