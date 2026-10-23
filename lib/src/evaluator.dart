import 'model/app_version.dart';
import 'model/inquisitor_platform.dart';
import 'model/payload.dart';
import 'model/state.dart';

/// Turns the server data into a verdict for one install.
///
/// Deliberately pure and synchronous — no I/O, no clock — so every rule
/// combination can be unit tested without a binding or a server.
abstract final class InquisitorEvaluator {
  /// Evaluates [payload] for [currentVersion] on [platform].
  ///
  /// Rules are checked in descending severity and the first match wins:
  ///
  /// 1. the kill switch,
  /// 2. an installed version below the app-side minimum,
  /// 3. an installed version below the server's latest,
  /// 4. otherwise [InquisitorVerdict.ok].
  ///
  /// The flags travel with every verdict, blocked or not.
  static InquisitorState evaluate({
    required InquisitorPayload payload,
    required AppVersion? currentVersion,
    required InquisitorPlatform platform,
    required InquisitorSource source,
    Map<InquisitorPlatform, String> storeUrls =
        const <InquisitorPlatform, String>{},
    Map<InquisitorPlatform, String> minimumVersions =
        const <InquisitorPlatform, String>{},
    DateTime? fetchedAt,
    Object? error,
  }) {
    final latest = payload.latestVersions[platform];
    final minimum = AppVersion.tryParse(minimumVersions[platform]);

    // A version tier that is missing — or that could not be parsed — stays
    // unenforced rather than locking users out of a working app.
    final InquisitorVerdict verdict;
    if (payload.killSwitch) {
      verdict = InquisitorVerdict.blocked;
    } else if (currentVersion == null) {
      verdict = InquisitorVerdict.ok;
    } else if (minimum != null && currentVersion < minimum) {
      verdict = InquisitorVerdict.updateRequired;
    } else if (latest != null && currentVersion < latest) {
      verdict = InquisitorVerdict.updateAvailable;
    } else {
      verdict = InquisitorVerdict.ok;
    }

    return InquisitorState(
      verdict: verdict,
      currentVersion: currentVersion,
      platform: platform,
      source: source,
      latestVersion: latest,
      minimumVersion: minimum,
      storeUrl: storeUrls[platform],
      flags: payload.flags,
      fetchedAt: fetchedAt,
      error: error,
    );
  }
}
