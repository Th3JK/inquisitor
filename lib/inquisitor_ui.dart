/// The opt-in user interface for Inquisitor.
///
/// Wrap the app in an [InquisitorGate] and it will cover the UI when the kill
/// switch is on or an update is mandatory, and raise a dismissible prompt when
/// an update is merely available:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => InquisitorGate(
///     inquisitor: inquisitor,
///     child: child!,
///   ),
///   home: const HomePage(),
/// );
/// ```
///
/// Gate content on a flag with [InquisitorFlagBuilder]:
///
/// ```dart
/// InquisitorFlagBuilder(
///   flag: 'Unlocked',
///   builder: (context, isOn) => isOn ? const PremiumPanel() : const LockedTeaser(),
/// );
/// ```
///
/// Every screen, every string and the store-opening behaviour can be replaced;
/// see [InquisitorGate] and [InquisitorStrings].
library;

export 'inquisitor.dart';
export 'src/ui/blocked_screen.dart';
export 'src/ui/flag_builder.dart';
export 'src/ui/inquisitor_gate.dart';
export 'src/ui/inquisitor_scope.dart';
export 'src/ui/strings.dart';
export 'src/ui/update_dialog.dart';
