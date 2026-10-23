import 'package:flutter/material.dart';

import '../model/state.dart';
import 'strings.dart';

/// The full-screen barrier shown for [InquisitorVerdict.blocked].
///
/// Shows kill-switch copy when the server switched the app off, and
/// "no connection" copy when there is no data and the no-data policy blocks.
class InquisitorBlockedScreen extends StatelessWidget {
  /// Creates the screen.
  const InquisitorBlockedScreen({
    required this.state,
    this.strings = const InquisitorStrings(),
    this.onRetry,
    super.key,
  });

  /// The state that caused the block.
  final InquisitorState state;

  /// Copy for the built-in labels.
  final InquisitorStrings strings;

  /// Called when the user asks to try again. The retry button is hidden when
  /// this is null.
  final VoidCallback? onRetry;

  /// True when the server did not block anything — the app is barred because
  /// it could not reach it and the no-data policy says to fail closed.
  bool get _isOffline => state.source == InquisitorSource.fallback;

  @override
  Widget build(BuildContext context) {
    return InquisitorMessageScaffold(
      icon: _isOffline ? Icons.wifi_off_outlined : Icons.block_outlined,
      title: _isOffline ? strings.offlineTitle : strings.blockedTitle,
      message: _isOffline ? strings.offlineMessage : strings.blockedMessage,
      state: state,
      strings: strings,
      actions: <Widget>[
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: Text(strings.retryAction)),
      ],
    );
  }
}

/// The full-screen barrier shown when the installed version is below the
/// minimum.
///
/// Unlike [InquisitorUpdateDialog] this cannot be dismissed — the whole point
/// of a forced update is that there is no way past it.
class InquisitorUpdateRequiredScreen extends StatelessWidget {
  /// Creates the screen.
  const InquisitorUpdateRequiredScreen({
    required this.state,
    this.strings = const InquisitorStrings(),
    this.onUpdate,
    super.key,
  });

  /// The state that demanded the update.
  final InquisitorState state;

  /// Copy for the built-in labels.
  final InquisitorStrings strings;

  /// Called when the user presses the update button. Hidden when null.
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    return InquisitorMessageScaffold(
      icon: Icons.system_update_outlined,
      title: strings.updateRequiredTitle,
      message: strings.updateRequiredMessage,
      state: state,
      strings: strings,
      actions: <Widget>[
        if (onUpdate != null)
          FilledButton(onPressed: onUpdate, child: Text(strings.updateAction)),
      ],
    );
  }
}

/// The shared chrome behind the blocking screens: centred icon, headline, body,
/// actions, and a version footer.
///
/// Exposed so a custom screen can reuse the layout without recreating it.
class InquisitorMessageScaffold extends StatelessWidget {
  /// Creates the layout.
  const InquisitorMessageScaffold({
    required this.icon,
    required this.title,
    required this.message,
    required this.state,
    this.strings = const InquisitorStrings(),
    this.actions = const <Widget>[],
    this.extra,
    super.key,
  });

  /// Glyph shown above the headline.
  final IconData icon;

  /// The headline.
  final String title;

  /// The body copy.
  final String message;

  /// The state being explained, used for the version footer.
  final InquisitorState state;

  /// Copy for the built-in labels.
  final InquisitorStrings strings;

  /// Buttons shown under the message.
  final List<Widget> actions;

  /// Optional widget inserted between the message and the actions.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(icon, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (extra != null) ...<Widget>[
                    const SizedBox(height: 24),
                    extra!,
                  ],
                  if (actions.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 32),
                    for (final action in actions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: action,
                      ),
                  ],
                  const SizedBox(height: 24),
                  InquisitorVersionFooter(state: state, strings: strings),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the installed version, and the newest one when the server advertises
/// something different.
///
/// Small, muted, and genuinely useful when a user is on the phone to support.
class InquisitorVersionFooter extends StatelessWidget {
  /// Creates the footer.
  const InquisitorVersionFooter({
    required this.state,
    this.strings = const InquisitorStrings(),
    super.key,
  });

  /// The state to describe.
  final InquisitorState state;

  /// Copy for the built-in labels.
  final InquisitorStrings strings;

  @override
  Widget build(BuildContext context) {
    final current = state.currentVersion;
    if (current == null) return const SizedBox.shrink();

    final latest = state.latestVersion;
    final showsLatest = latest != null && latest > current;

    return Text(
      showsLatest
          ? '${strings.versionLabel} $current → $latest'
          : '${strings.versionLabel} $current',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
