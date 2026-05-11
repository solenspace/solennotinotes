import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/services/speech/stt_service.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Dictation affordance in the editor toolbar. Sibling to
/// [AudioCaptureButton]; shares the same long-press / slide-to-cancel /
/// tap-to-toggle accessibility model so users build a single muscle memory
/// for both voice modalities.
///
/// **Renders nothing** when the cold-start STT capability probe reported
/// the device cannot run STT fully offline — Spec 15 hides the feature on
/// incapable devices to preserve architecture invariant 1.
class DictationButton extends StatefulWidget {
  const DictationButton({super.key});

  @override
  State<DictationButton> createState() => _DictationButtonState();
}

class _DictationButtonState extends State<DictationButton> {
  static const double _cancelDistance = 80;

  bool _pressed = false;
  bool _cancelled = false;

  void _start() {
    HapticFeedback.mediumImpact();
    _cancelled = false;
    context.read<NoteEditorBloc>().add(const DictationStarted());
  }

  void _stop() {
    HapticFeedback.selectionClick();
    context.read<NoteEditorBloc>().add(const DictationStopped());
  }

  void _cancel() {
    HapticFeedback.lightImpact();
    context.read<NoteEditorBloc>().add(const DictationCancelled());
  }

  @override
  Widget build(BuildContext context) {
    if (!context.read<SttService>().isOfflineCapable) {
      return const SizedBox.shrink();
    }
    final accessible = MediaQuery.of(context).accessibleNavigation;
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) => a.isDictating != b.isDictating,
      builder: (context, state) {
        final dictating = state.isDictating;
        return _DictationGlyph(
          dictating: dictating,
          pressed: _pressed,
          tapToToggle: accessible,
          onTap: !accessible
              ? null
              : () {
                  if (dictating) {
                    _stop();
                  } else {
                    _start();
                  }
                },
          onLongPressStart: accessible
              ? null
              : (_) {
                  setState(() => _pressed = true);
                  _start();
                },
          onLongPressMoveUpdate: accessible
              ? null
              : (details) {
                  if (_cancelled) return;
                  if (details.offsetFromOrigin.distance > _cancelDistance) {
                    _cancelled = true;
                    _cancel();
                  }
                },
          onLongPressEnd: accessible
              ? null
              : (_) {
                  setState(() => _pressed = false);
                  if (_cancelled) {
                    _cancelled = false;
                    return;
                  }
                  _stop();
                },
          onLongPressCancel: accessible
              ? null
              : () {
                  if (!_pressed) return;
                  setState(() => _pressed = false);
                  if (_cancelled) {
                    _cancelled = false;
                    return;
                  }
                  _cancel();
                },
        );
      },
    );
  }
}

class _DictationGlyph extends StatelessWidget {
  const _DictationGlyph({
    required this.dictating,
    required this.pressed,
    required this.tapToToggle,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onLongPressCancel,
  });

  final bool dictating;
  final bool pressed;
  final bool tapToToggle;
  final GestureTapCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = dictating ? scheme.primary : scheme.onSurface.withValues(alpha: 0.85);
    final tooltip = tapToToggle
        ? (dictating ? context.l10n.dictation_stop : context.l10n.dictation_start)
        : (dictating ? context.l10n.dictation_release : context.l10n.dictation_hold);
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPressStart: onLongPressStart,
          onLongPressMoveUpdate: onLongPressMoveUpdate,
          onLongPressEnd: onLongPressEnd,
          onLongPressCancel: onLongPressCancel,
          child: AnimatedScale(
            scale: pressed ? 0.92 : 1.0,
            duration: DurationPrimitives.fast,
            curve: CurvePrimitives.calm,
            child: AnimatedContainer(
              duration: DurationPrimitives.fast,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: dictating ? scheme.primary.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                dictating ? Icons.stop_rounded : Icons.record_voice_over_rounded,
                size: 22,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
