import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

typedef ExpandableFabCallback = void Function();

enum SwipeDirection { left, right, up }

class ExpandableFab extends StatefulWidget {
  final ExpandableFabCallback onContent;
  final ExpandableFabCallback onTodo;
  final ExpandableFabCallback onAudio;

  const ExpandableFab({
    super.key,
    required this.onContent,
    required this.onTodo,
    required this.onAudio,
  });

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab> with TickerProviderStateMixin {
  static const double _swipeThreshold = 50.0;
  static const double _sideButtonSpacing = 80.0;
  static const double _upButtonSpacing = 70.0;

  Offset _drag = Offset.zero;
  SwipeDirection? _selectedDirection;
  bool _hasReachedThreshold = false;

  late AnimationController _expandController;
  late AnimationController _scaleController;
  late Animation<double> _expandAnimation;
  late Animation<double> _leftScaleAnimation;
  late Animation<double> _rightScaleAnimation;
  late Animation<double> _upScaleAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 600),
      reverseDuration: DurationPrimitives.standard,
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: DurationPrimitives.standard,
      vsync: this,
    );

    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInCubic,
    );

    _leftScaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(_scaleController);
    _rightScaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(_scaleController);
    _upScaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(_scaleController);
  }

  @override
  void dispose() {
    _expandController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    HapticFeedback.lightImpact();
    setState(() {
      _drag = Offset.zero;
      _selectedDirection = null;
      _hasReachedThreshold = false;
    });
    _expandController.forward();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    setState(() {
      _drag = details.localOffsetFromOrigin;

      final dx = _drag.dx;
      final dy = _drag.dy;
      final absDx = dx.abs();
      final absDy = dy.abs();
      final reaches = (absDx > _swipeThreshold || absDy > _swipeThreshold);

      if (reaches && !_hasReachedThreshold) {
        _hasReachedThreshold = true;
        HapticFeedback.lightImpact();
      }

      if (!reaches) {
        _selectedDirection = null;
      } else if (absDy > absDx && dy < 0) {
        _selectedDirection = SwipeDirection.up;
      } else if (dx < 0) {
        _selectedDirection = SwipeDirection.left;
      } else {
        _selectedDirection = SwipeDirection.right;
      }
    });

    _updateScaleAnimations();
  }

  void _updateScaleAnimations() {
    final reference = _selectedDirection == SwipeDirection.up ? _drag.dy.abs() : _drag.dx.abs();
    final progress = (reference / _swipeThreshold).clamp(0.0, 1.0);

    _leftScaleAnimation = Tween<double>(
      begin: 1.0,
      end: _selectedDirection == SwipeDirection.left ? 1.1 : 0.9,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
    _rightScaleAnimation = Tween<double>(
      begin: 1.0,
      end: _selectedDirection == SwipeDirection.right ? 1.1 : 0.9,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
    _upScaleAnimation = Tween<double>(
      begin: 1.0,
      end: _selectedDirection == SwipeDirection.up ? 1.1 : 0.9,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));

    _scaleController.value = _selectedDirection == null ? 0 : progress;
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_selectedDirection != null) {
      HapticFeedback.selectionClick();
      switch (_selectedDirection!) {
        case SwipeDirection.left:
          widget.onContent();
        case SwipeDirection.right:
          widget.onTodo();
        case SwipeDirection.up:
          widget.onAudio();
      }
    }

    _collapse();
  }

  void _collapse() {
    _expandController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _drag = Offset.zero;
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
      height: 200,
      child: Semantics(
        button: true,
        label: context.l10n.fab_semantic_label,
        customSemanticsActions: {
          CustomSemanticsAction(label: context.l10n.fab_hint_content): widget.onContent,
          CustomSemanticsAction(label: context.l10n.fab_hint_todo): widget.onTodo,
          CustomSemanticsAction(label: context.l10n.fab_hint_audio): widget.onAudio,
        },
        child: GestureDetector(
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
                    left: 98.0 - (_expandAnimation.value * _sideButtonSpacing),
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
                    right: 98.0 - (_expandAnimation.value * _sideButtonSpacing),
                    child: Transform.scale(
                      scale: _expandAnimation.value * _rightScaleAnimation.value,
                      child: _ButtonCircle(
                        icon: Icons.checklist,
                        color: scheme.primary,
                        iconColor: scheme.onPrimary,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 4 + (_expandAnimation.value * _upButtonSpacing),
                    child: Transform.scale(
                      scale: _expandAnimation.value * _upScaleAnimation.value,
                      child: _ButtonCircle(
                        icon: Icons.mic_rounded,
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
                  Positioned(
                    bottom: 60,
                    left: 98.0 - (_expandAnimation.value * _sideButtonSpacing),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 100),
                      opacity: _selectedDirection == SwipeDirection.left && _hasReachedThreshold
                          ? 1.0
                          : 0.0,
                      child: Transform.scale(
                        scale: _expandAnimation.value * _leftScaleAnimation.value,
                        child: _HintLabel(text: context.l10n.fab_hint_content),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 60,
                    right: 98.0 - (_expandAnimation.value * _sideButtonSpacing),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 100),
                      opacity: _selectedDirection == SwipeDirection.right && _hasReachedThreshold
                          ? 1.0
                          : 0.0,
                      child: Transform.scale(
                        scale: _expandAnimation.value * _rightScaleAnimation.value,
                        child: _HintLabel(text: context.l10n.fab_hint_todo),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 60 + (_expandAnimation.value * _upButtonSpacing),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 100),
                      opacity: _selectedDirection == SwipeDirection.up && _hasReachedThreshold
                          ? 1.0
                          : 0.0,
                      child: Transform.scale(
                        scale: _expandAnimation.value * _upScaleAnimation.value,
                        child: _HintLabel(text: context.l10n.fab_hint_audio),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
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
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
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
          borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
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
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
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
