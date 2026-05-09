import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Docked toolbar above the keyboard. Each button is a [_ToolButton] with a
/// gentle press scale animation. The state of each affordance is owned by the
/// parent editor screen via callbacks.
class EditorToolbar extends StatelessWidget {
  final bool currentBlockIsChecklist;
  final VoidCallback onToggleChecklist;
  final VoidCallback onAddImage;
  final VoidCallback onOpenStyleSheet;

  /// Long-press on the brush icon resets the active note's overlay to the
  /// user's [NotiIdentity] default.
  final VoidCallback onResetOverlay;

  final VoidCallback onOpenReminderSheet;
  final VoidCallback onOpenTagSheet;
  final VoidCallback onDoneEditing;

  /// Optional audio capture affordance (e.g. `AudioCaptureButton`). The
  /// toolbar stays presentational; the button owns its own bloc wiring.
  final Widget? audioCaptureButton;

  /// Optional dictation affordance (e.g. `DictationButton`). Sibling to the
  /// audio capture slot; the button hides itself when STT is unavailable
  /// offline so an absent affordance is the steady state on incapable
  /// devices.
  final Widget? dictationButton;

  /// Optional read-aloud affordance (e.g. `ReadAloudButton`). Sibling to
  /// the dictation slot; tapping starts/stops whole-note text-to-speech.
  final Widget? readAloudButton;

  /// Optional AI assist affordance (e.g. `AiAssistButton`). Sits next
  /// to the brush per Spec 20 § "The ✦ Assist toolbar button"; the
  /// button hides itself when the device cannot run the on-device LLM
  /// or the model is not yet downloaded.
  final Widget? assistButton;

  /// Optional nearby-share affordance (e.g. `ShareButton`). Sits next
  /// to the assist button per Spec 24; opens the share sheet for the
  /// open note.
  final Widget? shareButton;

  const EditorToolbar({
    super.key,
    required this.currentBlockIsChecklist,
    required this.onToggleChecklist,
    required this.onAddImage,
    required this.onOpenStyleSheet,
    required this.onResetOverlay,
    required this.onOpenReminderSheet,
    required this.onOpenTagSheet,
    required this.onDoneEditing,
    this.audioCaptureButton,
    this.dictationButton,
    this.readAloudButton,
    this.assistButton,
    this.shareButton,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: scheme.outline,
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingPrimitives.sm,
        vertical: SpacingPrimitives.sm,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _ToolButton(
              icon: currentBlockIsChecklist
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              tooltip: 'Toggle checklist',
              selected: currentBlockIsChecklist,
              onTap: () {
                HapticFeedback.selectionClick();
                onToggleChecklist();
              },
            ),
            const Gap(SpacingPrimitives.xs),
            _ToolButton(
              icon: Icons.image_outlined,
              tooltip: 'Add image',
              onTap: onAddImage,
            ),
            if (audioCaptureButton != null) ...[
              const Gap(SpacingPrimitives.xs),
              audioCaptureButton!,
            ],
            if (dictationButton != null) ...[
              const Gap(SpacingPrimitives.xs),
              dictationButton!,
            ],
            if (readAloudButton != null) ...[
              const Gap(SpacingPrimitives.xs),
              readAloudButton!,
            ],
            if (assistButton != null) ...[
              const Gap(SpacingPrimitives.xs),
              assistButton!,
            ],
            if (shareButton != null) ...[
              const Gap(SpacingPrimitives.xs),
              shareButton!,
            ],
            const Gap(SpacingPrimitives.xs),
            _ToolButton(
              tooltip: 'Style — long-press to reset',
              onTap: onOpenStyleSheet,
              onLongPress: onResetOverlay,
              builder: (color) => SvgPicture.asset(
                'lib/assets/icons/brush.svg',
                width: 22,
                height: 22,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
            ),
            const Gap(SpacingPrimitives.xs),
            _ToolButton(
              icon: Icons.notifications_outlined,
              tooltip: 'Reminder',
              onTap: onOpenReminderSheet,
            ),
            const Gap(SpacingPrimitives.xs),
            _ToolButton(
              icon: Icons.tag_rounded,
              tooltip: 'Tags',
              onTap: onOpenTagSheet,
            ),
            const Spacer(),
            TextButton(
              onPressed: onDoneEditing,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatefulWidget {
  final IconData? icon;
  final Widget Function(Color color)? builder;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  const _ToolButton({
    this.icon,
    this.builder,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  }) : assert(icon != null || builder != null, 'icon or builder must be provided');

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = widget.selected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.85);
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: DurationPrimitives.fast,
          curve: CurvePrimitives.calm,
          child: AnimatedContainer(
            duration: DurationPrimitives.fast,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.selected ? scheme.primary.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
            ),
            alignment: Alignment.center,
            child: widget.builder != null
                ? widget.builder!(iconColor)
                : Icon(widget.icon, size: 22, color: iconColor),
          ),
        ),
      ),
    );
  }
}
