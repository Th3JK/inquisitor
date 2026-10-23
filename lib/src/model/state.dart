import 'package:meta/meta.dart';

import 'app_version.dart';
import 'flags.dart';
import 'inquisitor_platform.dart';

/// What Inquisitor concluded about the running app, in ascending severity.
enum InquisitorVerdict {
  /// Nothing to do; the app is current and permitted.
  ok,

  /// A newer version exists. The user may be nudged but can keep working.
  updateAvailable,

  /// The installed version is below the minimum. The app must not be used
  /// until the user updates.
  updateRequired,

  /// Access is denied — the kill switch is on, or there is no data and the
  /// no-data policy blocks.
  blocked,
}

/// Where the state currently in effect came from.
enum InquisitorSource {
  /// A fresh server response.
  network,

  /// A previously cached server response.
  cache,

  /// No usable data; the configured no-data policy decided this state.
  fallback,
}

/// The result of evaluating the server data against this install.
///
/// Delivered synchronously via `Inquisitor.state` and reactively via
/// `Inquisitor.stream`.
@immutable
class InquisitorState {
  /// Creates a state snapshot.
  const InquisitorState({
    required this.verdict,
    required this.platform,
    required this.source,
    this.currentVersion,
    this.latestVersion,
    this.minimumVersion,
    this.storeUrl,
    this.flags = InquisitorFlags.empty,
    this.fetchedAt,
    this.error,
  });

  /// The state before the first evaluation completes.
  ///
  /// Reported as [InquisitorVerdict.ok] so a host app that renders before
  /// `start()` finishes is never blocked by the absence of an answer.
  factory InquisitorState.unknown({
    AppVersion? currentVersion,
    InquisitorPlatform? platform,
  }) => InquisitorState(
    verdict: InquisitorVerdict.ok,
    currentVersion: currentVersion,
    platform: platform ?? InquisitorPlatform.unknown,
    source: InquisitorSource.fallback,
  );

  /// The verdict in effect.
  final InquisitorVerdict verdict;

  /// The version this app is running, or `null` when it could not be
  /// determined.
  ///
  /// When it is `null` the version tiers are not enforced — Inquisitor never
  /// forces an update on an install whose version it cannot read.
  final AppVersion? currentVersion;

  /// The platform the state was resolved for.
  final InquisitorPlatform platform;

  /// Where this state came from.
  final InquisitorSource source;

  /// The newest version the server advertises for this platform.
  final AppVersion? latestVersion;

  /// The oldest version the app allows itself to run, from
  /// `InquisitorConfig.minimumVersions`.
  final AppVersion? minimumVersion;

  /// Where the update button should send the user, from
  /// `InquisitorConfig.storeUrls`.
  final String? storeUrl;

  /// The flags served by the state endpoint.
  ///
  /// Empty when there is no data at all, so every flag reads as off.
  final InquisitorFlags flags;

  /// When the underlying data was fetched from the server.
  final DateTime? fetchedAt;

  /// The most recent fetch failure, if the last refresh did not succeed.
  ///
  /// Present even on a successful verdict — a state served from cache after a
  /// failed refresh carries the error so the app can surface or log it.
  final Object? error;

  /// Whether the app must not be used in this state.
  ///
  /// True for [InquisitorVerdict.updateRequired] and above.
  bool get isBlocking => verdict.index >= InquisitorVerdict.updateRequired.index;

  /// Whether the flag [name] is on. See [InquisitorFlags.isOn].
  bool isFlagOn(String name) => flags.isOn(name);

  /// Returns a copy with the given fields replaced.
  InquisitorState copyWith({
    InquisitorVerdict? verdict,
    AppVersion? currentVersion,
    InquisitorPlatform? platform,
    InquisitorSource? source,
    AppVersion? latestVersion,
    AppVersion? minimumVersion,
    String? storeUrl,
    InquisitorFlags? flags,
    DateTime? fetchedAt,
    Object? error,
  }) => InquisitorState(
    verdict: verdict ?? this.verdict,
    currentVersion: currentVersion ?? this.currentVersion,
    platform: platform ?? this.platform,
    source: source ?? this.source,
    latestVersion: latestVersion ?? this.latestVersion,
    minimumVersion: minimumVersion ?? this.minimumVersion,
    storeUrl: storeUrl ?? this.storeUrl,
    flags: flags ?? this.flags,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    error: error ?? this.error,
  );

  @override
  bool operator ==(Object other) =>
      other is InquisitorState &&
      other.verdict == verdict &&
      other.currentVersion == currentVersion &&
      other.platform == platform &&
      other.source == source &&
      other.latestVersion == latestVersion &&
      other.minimumVersion == minimumVersion &&
      other.storeUrl == storeUrl &&
      other.flags == flags &&
      other.fetchedAt == fetchedAt &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    verdict,
    currentVersion,
    platform,
    source,
    latestVersion,
    minimumVersion,
    storeUrl,
    flags,
    fetchedAt,
    error,
  );

  @override
  String toString() =>
      'InquisitorState(${verdict.name}, ${platform.name}, current: $currentVersion, '
      'latest: $latestVersion, source: ${source.name}'
      '${flags.isEmpty ? '' : ', flags: $flags'}'
      '${error != null ? ', error: $error' : ''})';
}
