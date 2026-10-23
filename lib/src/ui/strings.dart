import 'package:meta/meta.dart';

/// Every piece of copy the built-in screens can show.
///
/// Kept as a plain data class rather than a localisation delegate so the
/// package needs no `intl` dependency. Build one from your own translations and
/// hand it to `InquisitorGate.strings`:
///
/// ```dart
/// InquisitorGate(
///   inquisitor: inquisitor,
///   strings: InquisitorStrings(
///     updateRequiredTitle: context.l10n.updateRequiredTitle,
///     updateAction: context.l10n.updateNow,
///   ),
///   child: child,
/// );
/// ```
@immutable
class InquisitorStrings {
  /// Creates a string set, defaulting to the built-in English copy.
  const InquisitorStrings({
    this.blockedTitle = 'App unavailable',
    this.blockedMessage =
        'This version of the app can no longer be used. Please contact support '
        'if you think this is a mistake.',
    this.updateRequiredTitle = 'Update required',
    this.updateRequiredMessage =
        'This version is no longer supported. Update to carry on.',
    this.updateAvailableTitle = 'Update available',
    this.updateAvailableMessage = 'A new version of the app is ready.',
    this.updateAction = 'Update now',
    this.laterAction = 'Not now',
    this.retryAction = 'Try again',
    this.offlineTitle = 'No connection',
    this.offlineMessage =
        'The app could not reach the server. Check your connection and try '
        'again.',
    this.versionLabel = 'Version',
  });

  /// Heading when the kill switch is on.
  final String blockedTitle;

  /// Body copy when the kill switch is on.
  final String blockedMessage;

  /// Heading when the installed version is below the minimum.
  final String updateRequiredTitle;

  /// Body copy when the installed version is below the minimum.
  final String updateRequiredMessage;

  /// Heading of the optional-update prompt.
  final String updateAvailableTitle;

  /// Body copy of the optional-update prompt.
  final String updateAvailableMessage;

  /// Label of the button that opens the store.
  final String updateAction;

  /// Label of the button that dismisses the optional-update prompt.
  final String laterAction;

  /// Label of the button that retries a failed fetch.
  final String retryAction;

  /// Heading when there is no server answer and the policy blocks.
  final String offlineTitle;

  /// Body copy when there is no server answer and the policy blocks.
  final String offlineMessage;

  /// Label preceding the version numbers in the footer.
  final String versionLabel;
}
