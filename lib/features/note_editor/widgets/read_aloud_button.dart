import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Read-aloud affordance in the editor toolbar. Tap toggles whole-note
/// read on/off; the icon swaps to a stop glyph while a session is active.
/// Per-block read is offered separately by the focused-block read button
/// inside [TextBlockWidget] / [ChecklistBlockWidget].
///
/// Unlike [DictationButton] / [AudioCaptureButton], read-aloud has no
/// hold-to-record gesture and no permission gate — synthesis is a pure
/// playback affordance with no microphone use.
class ReadAloudButton extends StatelessWidget {
  const ReadAloudButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) => a.isReadingAloud != b.isReadingAloud,
      builder: (context, state) {
        final reading = state.isReadingAloud;
        return _ReadAloudGlyph(
          reading: reading,
          onTap: () {
            HapticFeedback.selectionClick();
            final bloc = context.read<NoteEditorBloc>();
            if (reading) {
              bloc.add(const ReadAloudStopped());
            } else {
              bloc.add(const ReadAloudRequested());
            }
          },
        );
      },
    );
  }
}

class _ReadAloudGlyph extends StatefulWidget {
  const _ReadAloudGlyph({required this.reading, required this.onTap});

  final bool reading;
  final VoidCallback onTap;

  @override
  State<_ReadAloudGlyph> createState() => _ReadAloudGlyphState();
}

class _ReadAloudGlyphState extends State<_ReadAloudGlyph> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = widget.reading ? scheme.primary : scheme.onSurface.withValues(alpha: 0.85);
    final tooltip = widget.reading ? context.l10n.read_aloud_stop : context.l10n.read_aloud_start;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1.0,
            duration: DurationPrimitives.fast,
            curve: CurvePrimitives.calm,
            child: AnimatedContainer(
              duration: DurationPrimitives.fast,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.reading ? scheme.primary.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.reading ? Icons.stop_rounded : Icons.volume_up_rounded,
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
