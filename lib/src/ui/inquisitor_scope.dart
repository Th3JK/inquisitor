import 'package:flutter/widgets.dart';

import '../inquisitor.dart';

/// Makes an [Inquisitor] available to the widgets below it.
///
/// [InquisitorGate] installs one automatically, so anything inside the gate can
/// reach the controller without threading it through constructors:
///
/// ```dart
/// final inquisitor = InquisitorScope.of(context);
/// await inquisitor.refresh(force: true);
/// ```
class InquisitorScope extends InheritedWidget {
  /// Creates a scope.
  const InquisitorScope({
    required this.inquisitor,
    required super.child,
    super.key,
  });

  /// The controller shared with the subtree.
  final Inquisitor inquisitor;

  /// The nearest enclosing controller.
  ///
  /// Throws when there is none — use [maybeOf] where the gate is optional.
  static Inquisitor of(BuildContext context) {
    final inquisitor = maybeOf(context);
    assert(inquisitor != null, 'No InquisitorScope found in the widget tree.');
    return inquisitor!;
  }

  /// The nearest enclosing controller, or `null` when there is none.
  static Inquisitor? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<InquisitorScope>()
      ?.inquisitor;

  @override
  bool updateShouldNotify(InquisitorScope oldWidget) =>
      oldWidget.inquisitor != inquisitor;
}
