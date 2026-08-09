import 'package:flutter/material.dart';

import '../../domain/session_phase.dart';
import '../theme.dart';

/// A proportional strip showing where a session's time goes.
///
/// Same colours as everywhere else, so the shape of a template is recognisable
/// before reading a word of it.
class PhaseBar extends StatelessWidget {
  const PhaseBar({
    required this.durations,
    this.height = 8,
    this.progress,
    super.key,
  });

  /// Phase → time, in arc order.
  final Map<SessionPhase, Duration> durations;

  final double height;

  /// 0..1 overall session progress. When set, the remaining part is dimmed.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final total = durations.values.fold<int>(
      0,
      (sum, duration) => sum + duration.inSeconds,
    );
    if (total == 0) return SizedBox(height: height);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final entry in durations.entries)
                if (entry.value.inSeconds > 0)
                  Expanded(
                    flex: entry.value.inSeconds,
                    child: Container(
                      height: height,
                      color: AppTheme.phaseColor(entry.key),
                    ),
                  ),
            ],
          ),
          if (progress != null)
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerRight,
                widthFactor: (1 - progress!).clamp(0.0, 1.0),
                child: Container(color: Colors.black.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ),
    );
  }
}
