import 'dart:async';

import 'package:flutter/material.dart';

import '../inquisitor.dart';
import '../model/state.dart';
import 'blocked_screen.dart';
import 'inquisitor_scope.dart';
import 'strings.dart';
import 'update_dialog.dart';
import 'url_opener.dart';

/// Builds a replacement for one of the built-in screens.
typedef InquisitorScreenBuilder =
    Widget Function(BuildContext context, InquisitorState state);

/// Builds a replacement for the optional-update prompt.
///
/// Call [onUpdate] to send the user to the store and [onDismiss] to defer;
/// the gate records the dismissal either way.
typedef InquisitorPromptBuilder =
    Widget Function(
      BuildContext context,
      InquisitorState state,
      VoidCallback onUpdate,
      VoidCallback onDismiss,
    );

/// Puts Inquisitor's verdict on screen.
///
/// Wrap the app once, ideally through `MaterialApp.builder` so the barrier sits
/// above the `Navigator` and covers every route:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) =>
///       InquisitorGate(inquisitor: inquisitor, child: child!),
///   home: const HomePage(),
/// );
/// ```
///
/// While a barrier is up the app below stays mounted but is hidden, inert and
/// hidden from assistive tech — so when the server lifts the kill switch, the
/// user lands back exactly where they were instead of on a rebuilt app.
///
/// Everything is replaceable: pass [blockedBuilder], [updateRequiredBuilder] or
/// [updatePromptBuilder] for your own screens, [strings] for your own copy, and
/// [onOpenUrl] to control how links are opened.
class InquisitorGate extends StatefulWidget {
  /// Creates a gate.
  const InquisitorGate({
    required this.inquisitor,
    required this.child,
    this.strings = const InquisitorStrings(),
    this.blockedBuilder,
    this.updateRequiredBuilder,
    this.updatePromptBuilder,
    this.loadingBuilder,
    this.onOpenUrl,
    this.promptForUpdates = true,
    super.key,
  });

  /// The controller to follow. The gate calls `start()` on it if the app has
  /// not already done so.
  final Inquisitor inquisitor;

  /// The app.
  final Widget child;

  /// Copy for the built-in screens.
  final InquisitorStrings strings;

  /// Replaces the kill-switch and no-connection screen.
  final InquisitorScreenBuilder? blockedBuilder;

  /// Replaces the forced-update screen.
  final InquisitorScreenBuilder? updateRequiredBuilder;

  /// Replaces the optional-update prompt.
  final InquisitorPromptBuilder? updatePromptBuilder;

  /// Shown until the first verdict is in.
  ///
  /// Leave it null to show the app immediately — the right choice unless the
  /// app is unsafe to show before the server has spoken.
  final WidgetBuilder? loadingBuilder;

  /// Opens store links. Defaults to `url_launcher`.
  final UrlOpener? onOpenUrl;

  /// Whether to raise the optional-update prompt at all.
  ///
  /// Set false to keep the forced tiers but surface soft updates your own way,
  /// for example as a banner driven by `inquisitor.stream`.
  final bool promptForUpdates;

  @override
  State<InquisitorGate> createState() => _InquisitorGateState();
}

class _InquisitorGateState extends State<InquisitorGate> {
  /// Versions already handled in this session.
  ///
  /// Tapping "update now" suppresses the prompt for the rest of the session but
  /// is deliberately *not* persisted: someone who taps through to the store and
  /// never installs should be asked again next launch.
  final Set<String> _handledThisSession = <String>{};

  StreamSubscription<InquisitorState>? _subscription;
  late InquisitorState _state;
  String? _promptedVersion;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(InquisitorGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inquisitor != widget.inquisitor) {
      _promptedVersion = null;
      _handledThisSession.clear();
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _listen() {
    _state = widget.inquisitor.state;
    _subscription = widget.inquisitor.stream.listen(_onState);
    // The first verdict may be identical to the placeholder one, which the
    // controller does not re-emit — so rebuild off the future too, otherwise a
    // loadingBuilder could hang on an unchanged state.
    unawaited(
      widget.inquisitor.start().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  void _onState(InquisitorState state) {
    if (!mounted) return;
    setState(() => _state = state);
    unawaited(_evaluatePrompt(state));
  }

  Future<void> _openUrl(String url) async {
    final opener = widget.onOpenUrl ?? openExternalUrl;
    await opener(url);
  }

  void _openStore(InquisitorState state) {
    final url = state.storeUrl;
    if (url != null) unawaited(_openUrl(url));
  }

  /// Decides whether the soft-update prompt is due, off the build path.
  Future<void> _evaluatePrompt(InquisitorState state) async {
    if (!widget.promptForUpdates) return;

    final version = state.latestVersion?.toString();
    if (state.verdict != InquisitorVerdict.updateAvailable || version == null) {
      if (_promptedVersion != null && mounted) {
        setState(() => _promptedVersion = null);
      }
      return;
    }

    if (_handledThisSession.contains(version) || _promptedVersion == version) {
      return;
    }

    final shouldPrompt = await widget.inquisitor.shouldPromptUpdate(state);
    if (!mounted || !shouldPrompt) return;
    setState(() => _promptedVersion = version);
  }

  void _dismissPrompt(InquisitorState state, {required bool persist}) {
    final version = state.latestVersion?.toString();
    if (version != null) _handledThisSession.add(version);
    if (persist) unawaited(widget.inquisitor.dismissUpdate(state));
    setState(() => _promptedVersion = null);
  }

  Widget _buildBarrier(BuildContext context, InquisitorState state) =>
      switch (state.verdict) {
        InquisitorVerdict.updateRequired =>
          widget.updateRequiredBuilder?.call(context, state) ??
              InquisitorUpdateRequiredScreen(
                state: state,
                strings: widget.strings,
                onUpdate: state.storeUrl == null
                    ? null
                    : () => _openStore(state),
              ),
        _ =>
          widget.blockedBuilder?.call(context, state) ??
              InquisitorBlockedScreen(
                state: state,
                strings: widget.strings,
                onRetry: _canRetry(state)
                    ? () => unawaited(widget.inquisitor.refresh(force: true))
                    : null,
              ),
      };

  /// Retrying makes sense when there was no data, not for a kill switch.
  static bool _canRetry(InquisitorState state) =>
      state.source == InquisitorSource.fallback;

  @override
  Widget build(BuildContext context) {
    final state = _state;

    final loadingBuilder = widget.loadingBuilder;
    final Widget content;
    if (loadingBuilder != null && !widget.inquisitor.isReady) {
      content = loadingBuilder(context);
    } else {
      final isBlocking = state.isBlocking;
      final prompt = _promptedVersion == null || isBlocking
          ? null
          : _buildPrompt(context, state);

      content = Stack(
        children: <Widget>[
          ExcludeFocus(
            excluding: isBlocking,
            child: ExcludeSemantics(
              excluding: isBlocking,
              child: TickerMode(
                enabled: !isBlocking,
                child: Offstage(offstage: isBlocking, child: widget.child),
              ),
            ),
          ),
          if (isBlocking) Positioned.fill(child: _buildBarrier(context, state)),
          if (prompt != null) ...<Widget>[
            const Positioned.fill(
              child: ModalBarrier(dismissible: false, color: Colors.black54),
            ),
            Positioned.fill(child: prompt),
          ],
        ],
      );
    }

    return InquisitorScope(inquisitor: widget.inquisitor, child: content);
  }

  Widget _buildPrompt(BuildContext context, InquisitorState state) {
    void onUpdate() {
      _dismissPrompt(state, persist: false);
      _openStore(state);
    }

    void onDismiss() => _dismissPrompt(state, persist: true);

    final builder = widget.updatePromptBuilder;
    if (builder != null) return builder(context, state, onUpdate, onDismiss);

    return InquisitorUpdateDialog(
      state: state,
      strings: widget.strings,
      onUpdate: state.storeUrl == null ? null : onUpdate,
      onDismiss: onDismiss,
    );
  }
}
