import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/theme.dart';
import '../../jobs/sparring_jobs.dart';

/// A sparring round's background progress: the stage, a bar (determinate when
/// the stage can measure itself) and how long it has been running.
class SparringProgressLine extends StatefulWidget {
  const SparringProgressLine({required this.progress, super.key});

  final SparringJobProgress progress;

  @override
  State<SparringProgressLine> createState() => _SparringProgressLineState();
}

class _SparringProgressLineState extends State<SparringProgressLine> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final elapsed = DateTime.now().difference(p.startedAt);
    final f = p.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${p.status.label}'
          '${f != null ? ' · ${(f * 100).round()}%' : ''}'
          ' · ${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: f, minHeight: 4),
        ),
      ],
    );
  }
}
