import 'package:flutter/material.dart';

/// Slim 3-step progress header: Scan → Face → Card.
class VerifyStepsHeader extends StatelessWidget {
  const VerifyStepsHeader({super.key, required this.current});

  /// 1-based index of the current step.
  final int current;

  static const _labels = ['Scan', 'Face', 'Card'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: (i + 1) <= current
                    ? scheme.primary
                    : scheme.outlineVariant,
              ),
            ),
          _StepDot(
            index: i + 1,
            label: _labels[i],
            state: i + 1 < current
                ? _StepState.done
                : (i + 1 == current ? _StepState.now : _StepState.todo),
          ),
        ],
      ],
    );
  }
}

enum _StepState { done, now, todo }

class _StepDot extends StatelessWidget {
  const _StepDot(
      {required this.index, required this.label, required this.state});

  final int index;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = switch (state) {
      _StepState.done => scheme.primary,
      _StepState.now => scheme.primaryContainer,
      _StepState.todo => scheme.surfaceContainerHighest,
    };
    final fg = switch (state) {
      _StepState.done => scheme.onPrimary,
      _StepState.now => scheme.onPrimaryContainer,
      _StepState.todo => scheme.onSurfaceVariant,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: bg,
          child: state == _StepState.done
              ? Icon(Icons.check, size: 15, color: fg)
              : Text('$index',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: fg)),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: state == _StepState.now
                    ? FontWeight.w800
                    : FontWeight.w400,
                color: fg)),
      ],
    );
  }
}
