import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_tokens.dart';

typedef ExpandableFabCallback = void Function();

enum SwipeDirection { left, right }

class ExpandableFab extends StatefulWidget {
  final ExpandableFabCallback onContent;
  final ExpandableFabCallback onTodo;

  const ExpandableFab({
    super.key,
    required this.onContent,
    required this.onTodo,
  });

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with TickerProviderStateMixin {
  static const double _swipeThreshold = 50.0;
  static const double _buttonSpacing = 80.0;

  double _dragX = 0;
  SwipeDirection? _selectedDirection;
  bool _hasReachedThreshold = false;

  late AnimationController _expandController;
  late AnimationController _scaleController;
  late Animation<double> _expandAnimation;
  late Animation<double> _leftScaleAnimation;
  late Animation<double> _rightScaleAnimation;

  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 600), // Slower for elastic bounce
      reverseDuration: AppDurations.md,
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: AppDurations.sm,
      vsync: this,
    );

    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.elasticOut, // Morph pop-out bounce
      reverseCurve: Curves.easeInCubic,
    );

    _leftScaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(_scaleController);
    _rightScaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(_scaleController);
  }

  @override
  void dispose() {
    _expandController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _onTap() async {
    HapticFeedback.lightImpact();
    setState(() => _showHint = true);
    
    // Quick pop-out animation to show options exist
    // animateTo duration isn't a direct parameter. Need to use duration explicitly if needed.
    _expandController.duration = const Duration(milliseconds: 150);
    await _expandController.animateTo(0.4, curve: Curves.easeOut);
    
    _expandController.duration = const Duration(milliseconds: 200);
    await _expandController.reverse();
    
    // Restore base duration
    _expandController.duration = const Duration(milliseconds: 600);

    // Hide hint after delay
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _showHint = false);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    HapticFeedback.lightImpact();
    setState(() {
      _dragX = 0;
      _selectedDirection = null;
      _hasReachedThreshold = false;
    });
    _expandController.forward();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    setState(() {
      _dragX = details.localOffsetFromOrigin.dx;
      
      final absDragX = _dragX.abs();
      
      if (absDragX > _swipeThreshold && !_hasReachedThreshold) {
        _hasReachedThreshold = true;
        HapticFeedback.lightImpact();
      }
      
      if (absDragX > _swipeThreshold) {
        if (_dragX < 0) {
          _selectedDirection = SwipeDirection.left;
        } else {
          _selectedDirection = SwipeDirection.right;
        }
      } else {
        _selectedDirection = null;
      }
    });
    
    _updateScaleAnimations();
  }

  void _updateScaleAnimations() {
    final absDragX = _dragX.abs();
    final progress = (absDragX / _swipeThreshold).clamp(0.0, 1.0);
    
    if (_selectedDirection == SwipeDirection.left) {
      _leftScaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
      );
      _rightScaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
        CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
      );
      _scaleController.value = progress;
    } else if (_selectedDirection == SwipeDirection.right) {
      _rightScaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
      );
      _leftScaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
        CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
      );
      _scaleController.value = progress;
    } else {
      _scaleController.value = 0;
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_selectedDirection != null) {
      HapticFeedback.selectionClick();
      if (_selectedDirection == SwipeDirection.left) {
        widget.onContent();
      } else {
        widget.onTodo();
      }
    }
    
    _collapse();
  }

  void _collapse() {
    _expandController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _dragX = 0;
          _selectedDirection = null;
          _hasReachedThreshold = false;
        });
        _scaleController.value = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return SizedBox(
      width: 240,
      height: 140, // Increased height to accommodate hints above buttons
      child: GestureDetector(
        onTap: _onTap,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: _onLongPressEnd,
        child: AnimatedBuilder(
          animation: Listenable.merge([_expandController, _scaleController]),
          builder: (context, child) {
            return Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: 4,
                  // Originates exactly from center (120 - 22 = 98) and translates outwards
                  left: 98.0 - (_expandAnimation.value * _buttonSpacing),
                  child: Transform.scale(
                    scale: _expandAnimation.value * _leftScaleAnimation.value,
                    child: _ButtonCircle(
                      icon: Icons.edit_note,
                      color: scheme.primary,
                      iconColor: scheme.onPrimary,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 98.0 - (_expandAnimation.value * _buttonSpacing),
                  child: Transform.scale(
                    scale: _expandAnimation.value * _rightScaleAnimation.value,
                    child: _ButtonCircle(
                      icon: Icons.checklist,
                      color: scheme.primary,
                      iconColor: scheme.onPrimary,
                    ),
                  ),
                ),
                CenterButton(
                  expandProgress: _expandAnimation.value,
                  color: scheme.primary,
                  onPrimaryColor: scheme.onPrimary,
                ),
                // "Hold and swipe" tooltip
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  bottom: _showHint ? 70 : 40,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _showHint ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.onSurface,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.onSurface.withValues(alpha: 0.15),
                            offset: const Offset(3, 3),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Text(
                        'Hold and swipe',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.surface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                // Left button hint (Content) - directly above button
                Positioned(
                  bottom: 60,
                  left: 98.0 - (_expandAnimation.value * _buttonSpacing),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 100),
                    opacity: _selectedDirection == SwipeDirection.left && _hasReachedThreshold ? 1.0 : 0.0,
                    child: Transform.scale(
                      scale: _expandAnimation.value * _leftScaleAnimation.value,
                      child: _HintLabel(text: 'Content'),
                    ),
                  ),
                ),
                // Right button hint (Todo) - directly above button
                Positioned(
                  bottom: 60,
                  right: 98.0 - (_expandAnimation.value * _buttonSpacing),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 100),
                    opacity: _selectedDirection == SwipeDirection.right && _hasReachedThreshold ? 1.0 : 0.0,
                    child: Transform.scale(
                      scale: _expandAnimation.value * _rightScaleAnimation.value,
                      child: _HintLabel(text: 'Todo'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ButtonCircle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;

  const _ButtonCircle({
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, color: iconColor, size: 22),
    );
  }
}

class CenterButton extends StatelessWidget {
  final double expandProgress;
  final Color color;
  final Color onPrimaryColor;

  const CenterButton({
    super.key,
    required this.expandProgress,
    required this.color,
    required this.onPrimaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final rotation = expandProgress * 0.125 * 3.14159;
    final scale = 1.0 - (expandProgress * 0.15);
    
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface,
            width: 1.0,
          ),
        ),
        child: Transform.rotate(
          angle: rotation,
          child: Icon(
            Icons.add,
            size: 28,
            color: onPrimaryColor,
          ),
        ),
      ),
    );
  }
}

class _HintLabel extends StatelessWidget {
  final String text;
  const _HintLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.onSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: [
          BoxShadow(
            color: scheme.onSurface.withValues(alpha: 0.15),
            offset: const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.surface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
