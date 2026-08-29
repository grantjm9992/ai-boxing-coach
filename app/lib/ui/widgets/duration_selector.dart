import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

/// A round-length picker: a slider from 1:00 to 3:00 in 30-second steps, with
/// the selected length shown. Shared by shadow boxing and combination drills.
class DurationSelector extends StatelessWidget {
  const DurationSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Duration value;
  final ValueChanged<Duration> onChanged;

  static const Duration min = Duration(seconds: 60);
  static const Duration max = Duration(seconds: 180);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const Text(
              'Round length',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            Text(
              TimeFormat.clock(value),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        Slider(
          value: value.inSeconds.toDouble(),
          min: min.inSeconds.toDouble(),
          max: max.inSeconds.toDouble(),
          divisions: 4, // 60, 90, 120, 150, 180
          label: TimeFormat.clock(value),
          onChanged: (seconds) =>
              onChanged(Duration(seconds: seconds.round())),
        ),
      ],
    );
  }
}
