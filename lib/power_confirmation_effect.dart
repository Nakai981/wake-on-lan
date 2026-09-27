import 'package:flutter/material.dart';

/// Brief, non-blocking feedback for a user-confirmed PC state.
class PowerConfirmationEffect extends StatelessWidget {
  final VoidCallback? onEnd;
  const PowerConfirmationEffect({super.key, this.onEnd});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            onEnd: onEnd,
            builder: (context, progress, _) {
              final opacity = progress < .65
                  ? 1.0
                  : ((1 - progress) / .35).clamp(0.0, 1.0);
              return Opacity(
                opacity: opacity,
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: .35 + progress * 1.1,
                        child: Container(
                          width: 210,
                          height: 210,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.primary.withValues(
                                alpha: (1 - progress) * .65,
                              ),
                              width: 2,
                            ),
                            gradient: RadialGradient(
                              colors: [
                                colors.primary.withValues(alpha: .18),
                                colors.primary.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
