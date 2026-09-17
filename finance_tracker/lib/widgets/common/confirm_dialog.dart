import 'package:flutter/material.dart';

/// A reusable confirmation dialog for destructive or irreversible actions.
///
/// Usage:
/// ```dart
/// final confirmed = await ConfirmDialog.show(
///   context,
///   title: 'Delete transaction?',
///   message: 'This action cannot be undone.',
/// );
/// if (confirmed) { ... }
/// ```
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Delete',
    this.isDestructive = true,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool isDestructive;

  /// Shows the dialog and returns `true` if the user confirmed, `false`
  /// otherwise (dismissed or cancelled).
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Delete',
    bool isDestructive = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        isDestructive: isDestructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: isDestructive
              ? FilledButton.styleFrom(backgroundColor: Colors.red[700])
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
