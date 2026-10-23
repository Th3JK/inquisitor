import 'package:url_launcher/url_launcher.dart';

/// Opens an external URL — the store listing, a status page, a support form.
///
/// Override it on [InquisitorGate] to route through your own analytics, an
/// in-app browser, or a stub in tests.
typedef UrlOpener = Future<void> Function(String url);

/// The default [UrlOpener], handing the URL to the platform via
/// `url_launcher`.
///
/// Silently does nothing for a URL that cannot be parsed or launched — a dead
/// store link should not throw out of a button press on a blocking screen.
Future<void> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
