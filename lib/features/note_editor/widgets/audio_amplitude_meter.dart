import 'package:flutter/material.dart';

import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Live mic-level indicator displayed during recording. The visible bar
/// width tracks [amplitude] in [0, 1]; a quick AnimatedContainer smooths
/// the per-sample jumps emitted at ~60ms by the recorder.
class AudioAmplitudeMeter extends StatelessWidget {
  const AudioAmplitudeMeter({
    super.key,
    required this.amplitude,
    this.color,
    this.width = 64,
    this.height = 4,
  });

  final double amplitude;
  final Color? color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final barColor = color ?? Theme.of(context).colorScheme.primary;
    final clamped = amplitude.clamp(0.0, 1.0);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
      ),
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: DurationPrimitives.fast,
        curve: CurvePrimitives.calm,
        width: width * clamped,
        height: height,
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        ),
      ),
    );
  }
}
