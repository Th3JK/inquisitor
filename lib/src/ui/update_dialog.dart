import 'package:flutter/material.dart';

import '../model/state.dart';
import 'strings.dart';

/// The dismissible prompt shown when a newer version exists but the installed
/// one is still allowed to run.
///
/// [InquisitorGate] shows this at most once per advertised version — see
/// `InquisitorConfig.nagInterval` to relax or tighten that.
class InquisitorUpdateDialog extends StatelessWidget {
  /// Creates the dialog.
  const InquisitorUpdateDialog({
    required this.state,
    this.strings = const InquisitorStrings(),
    this.onUpdate,
    this.onDismiss,
    super.key,
  });

  /// The state that triggered the prompt.
  final InquisitorState state;

  /// Copy for the built-in labels.
  final InquisitorStrings strings;

  /// Called when the user chooses to update.
  final VoidCallback? onUpdate;

  /// Called when the user defers.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final latest = state.latestVersion;

    return AlertDialog(
      icon: const Icon(Icons.system_update_outlined),
      title: Text(strings.updateAvailableTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(strings.updateAvailableMessage),
          if (latest != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '${strings.versionLabel} ${state.currentVersion} → $latest',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: onDismiss, child: Text(strings.laterAction)),
        FilledButton(onPressed: onUpdate, child: Text(strings.updateAction)),
      ],
    );
  }
}
