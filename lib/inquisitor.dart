/// Remote app control for Flutter — kill switch, content flags and update
/// gating, driven by two endpoints your server owns:
///
/// ```
/// app_state.php   -> [{"flag": "Unlocked", "state": "1"}, {"flag": "KillSwitch", "state": "0"}]
/// app_version.php -> [{"device": "Android", "version": "1.0.0"}, {"device": "Apple", "version": "1.0.0"}]
/// ```
///
/// This library is the headless core: no widgets, no `url_launcher`. Import
/// `package:inquisitor/inquisitor_ui.dart` as well if you want the ready-made
/// blocking screens, update prompt and flag builder.
///
/// ```dart
/// final inquisitor = Inquisitor(
///   config: InquisitorConfig(
///     stateUrl: Uri.parse('https://example.com/app_state.php'),
///     versionUrl: Uri.parse('https://example.com/app_version.php'),
///     flagListeners: {'Unlocked': (isOn) => print('Unlocked: $isOn')},
///   ),
/// );
/// await inquisitor.start();
/// inquisitor.stream.listen((state) => print(state.verdict));
/// ```
library;

export 'src/cache/cache.dart';
export 'src/cache/prefs_cache.dart';
export 'src/config.dart';
export 'src/inquisitor.dart';
export 'src/model/app_version.dart';
export 'src/model/flags.dart';
export 'src/model/inquisitor_platform.dart';
export 'src/model/state.dart';
export 'src/policies.dart';
