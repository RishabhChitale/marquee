import 'package:flutter/material.dart';

/// Asks for a text value. Returns the trimmed text, or null if cancelled/empty.
Future<String?> promptName(BuildContext context,
    {required String title, String initial = '', String action = 'Save'}) async {
  final t = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title, initial, action));
  final s = t?.trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// In-app confirmation. True only if the user pressed [action].
Future<bool> confirmDialog(BuildContext context,
    {required String title,
    required String message,
    String action = 'Remove'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog(this.title, this.initial, this.action);
  final String title, initial, action;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _c = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 360,
          child: TextField(
              controller: _c,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(context, v)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _c.text),
              child: Text(widget.action)),
        ],
      );
}
