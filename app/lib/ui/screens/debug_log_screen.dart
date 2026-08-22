import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/debug_log.dart';
import '../theme.dart';

/// The on-device diagnostic log. Newest lines at the top, with copy / share /
/// clear — the window into what a release build is actually doing.
class DebugLogScreen extends StatelessWidget {
  const DebugLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = DebugLog.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug log'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_all),
            onPressed: () => _copy(context, log),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _share(log),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmClear(context, log),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: log,
        builder: (context, _) {
          final lines = log.lines;
          if (lines.isEmpty) {
            return const Center(
              child: Text(
                'Nothing logged yet.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: lines.length,
            itemBuilder: (context, i) {
              // Newest first.
              final line = lines[lines.length - 1 - i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SelectableText(
                  line,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppTheme.textSecondary,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _copy(BuildContext context, DebugLog log) async {
    await Clipboard.setData(ClipboardData(text: log.text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Log copied')));
  }

  Future<void> _share(DebugLog log) async {
    final file = log.file;
    if (file != null && await file.exists()) {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          subject: 'AI Boxing Coach debug log',
        ),
      );
    } else {
      await SharePlus.instance.share(ShareParams(text: log.text));
    }
  }

  Future<void> _confirmClear(BuildContext context, DebugLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the log?'),
        content: const Text('Removes everything logged so far, on disk too.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await log.clear();
  }
}
