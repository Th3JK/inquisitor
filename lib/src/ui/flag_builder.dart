import 'dart:async';

import 'package:flutter/widgets.dart';

import '../inquisitor.dart';
import 'inquisitor_scope.dart';

/// Builds a widget from whether a flag is on.
typedef InquisitorFlagWidgetBuilder =
    Widget Function(BuildContext context, bool isOn);

/// Rebuilds whenever the flag [flag] turns on or off.
///
/// The usual job is locked content:
///
/// ```dart
/// InquisitorFlagBuilder(
///   flag: 'Unlocked',
///   builder: (context, isOn) => isOn ? const PremiumPanel() : const LockedTeaser(),
/// );
/// ```
///
/// A flag the server has not sent — or no data at all — reads as off.
class InquisitorFlagBuilder extends StatefulWidget {
  /// Creates a flag builder.
  ///
  /// Without an [inquisitor], the one from the nearest [InquisitorScope] is
  /// used — [InquisitorGate] installs one for the whole app.
  const InquisitorFlagBuilder({
    required this.flag,
    required this.builder,
    this.inquisitor,
    super.key,
  });

  /// The flag to follow. Compared without case.
  final String flag;

  /// Builds the subtree for the flag's current value.
  final InquisitorFlagWidgetBuilder builder;

  /// The controller to follow, or `null` for the enclosing scope's.
  final Inquisitor? inquisitor;

  @override
  State<InquisitorFlagBuilder> createState() => _InquisitorFlagBuilderState();
}

class _InquisitorFlagBuilderState extends State<InquisitorFlagBuilder> {
  Inquisitor? _controller;
  StreamSubscription<bool>? _subscription;
  bool _isOn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(InquisitorFlagBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flag != widget.flag) _controller = null;
    _follow();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  /// Subscribes to the flag, unless already following it on this controller.
  void _follow() {
    final controller = widget.inquisitor ?? InquisitorScope.of(context);
    if (identical(controller, _controller)) return;
    _controller = controller;
    unawaited(_subscription?.cancel());
    _isOn = controller.isFlagOn(widget.flag);
    _subscription = controller.watchFlag(widget.flag).listen((isOn) {
      if (mounted && isOn != _isOn) setState(() => _isOn = isOn);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _isOn);
}
