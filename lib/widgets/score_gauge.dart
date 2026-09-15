import 'package:flutter/material.dart';

/// Animated score-vs-threshold bar: gold fill, threshold tick, big score
/// readout. Replaces raw `Score 0.742 vs threshold 0.40` text.
class ScoreGauge extends StatelessWidget {
  const ScoreGauge({
    super.key,
    required this.score,
    required this.threshold,
    this.scoreLabel = 'Score',
    this.thresholdLabel = 'Threshold',
  });

  final double score;
  final double threshold;
  final String scoreLabel;
  final String thresholdLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = score.clamp(0.0, 1.0);
    final pass = score >= threshold;
    final barColor = pass ? scheme.primary : scheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              score.toStringAsFixed(3),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: barColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                scoreLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '$thresholdLabel ${threshold.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: clamped),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, value, _) => LayoutBuilder(
            builder: (_, constraints) {
              final w = constraints.maxWidth;
              return SizedBox(
                height: 14,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                    // Threshold tick.
                    Positioned(
                      left: (threshold.clamp(0.0, 1.0) * w) - 1.5,
                      top: -2,
                      bottom: -2,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: scheme.onSurface,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
