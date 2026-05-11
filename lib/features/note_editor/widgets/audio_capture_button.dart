import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/features/note_editor/widgets/audio_amplitude_meter.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Mic affordance in the editor toolbar. Two interaction modes, picked at
/// build time by [MediaQueryData.accessibleNavigation]:
///
/// * **Hold-to-record** (default): long-press start fires
///   [AudioCaptureRequested]; release fires [AudioCaptureStopped]; sliding
///   the finger past [_cancelDistance] cancels the in-flight session.
/// * **Tap-to-toggle**: when assistive tech is active, a single tap
///   toggles between request and stop. Long-press has known issues with
///   VoiceOver / TalkBack passthrough; tap is the reliable fallback.
///
/// While `state.isCapturingAudio` is true the icon swaps to a stop glyph
/// and an [AudioAmplitudeMeter] renders inline.
class AudioCaptureButton extends StatefulWidget {
  const AudioCaptureButton({super.key});

  @override
  State<AudioCaptureButton> createState() => _AudioCaptureButtonState();
}

class _AudioCaptureButtonState extends State<AudioCaptureButton> {
  static const double _cancelDistance = 80;

  bool _pressed = false;
  bool _cancelled = false;

  void _start() {
    HapticFeedback.mediumImpact();
    _cancelled = false;
    context.read<NoteEditorBloc>().add(const AudioCaptureRequested());
  }

  void _stop() {
    HapticFeedback.selectionClick();
    context.read<NoteEditorBloc>().add(const AudioCaptureStopped());
  }

  void _cancel() {
    HapticFeedback.lightImpact();
    context.read<NoteEditorBloc>().add(const AudioCaptureCancelled());
  }

  @override
  Widget build(BuildContext context) {
    final accessible = MediaQuery.of(context).accessibleNavigation;
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) =>
          a.isCapturingAudio != b.isCapturingAudio || a.currentAmplitude != b.currentAmplitude,
      builder: (context, state) {
        final capturing = state.isCapturingAudio;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MicButton(
              capturing: capturing,
              pressed: _pressed,
              tapToToggle: accessible,
              onTap: !accessible
                  ? null
                  : () {
                      if (capturing) {
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
            ),
            if (capturing) ...[
              const Gap(SpacingPrimitives.sm),
              ExcludeSemantics(
                child: AudioAmplitudeMeter(amplitude: state.currentAmplitude ?? 0),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.capturing,
    required this.pressed,
    required this.tapToToggle,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onLongPressCancel,
  });

  final bool capturing;
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
    final iconColor = capturing ? scheme.error : scheme.onSurface.withValues(alpha: 0.85);
    final tooltip = tapToToggle
        ? (capturing ? context.l10n.audio_stop_recording : context.l10n.audio_record)
        : (capturing ? context.l10n.audio_recording_release : context.l10n.audio_hold_record);
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
                color: capturing ? scheme.error.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
              ),
              alignment: Alignment.center,
              child: capturing
                  ? Icon(Icons.stop_rounded, size: 22, color: iconColor)
                  : SvgPicture.asset(
                      'lib/assets/icons/mic.svg',
                      width: 22,
                      height: 22,
                      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
