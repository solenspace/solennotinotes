import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/share/widgets/share_nearby_sheet.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Editor-toolbar entry that opens the nearby share sheet for the
/// currently-open note. Visual chrome mirrors `EditorToolbar._ToolButton`
/// (40×40 container, 22 px glyph, `RadiusPrimitives.sm`, AnimatedScale
/// press feedback) — the toolbar's button is private to its file, so the
/// chrome is reproduced here rather than exported.
class ShareButton extends StatefulWidget {
  const ShareButton({super.key});

  @override
  State<ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<ShareButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Share nearby',
      child: Semantics(
        label: 'Share nearby',
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: _onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1.0,
            duration: DurationPrimitives.fast,
            curve: CurvePrimitives.calm,
            child: AnimatedContainer(
              duration: DurationPrimitives.fast,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.ios_share_rounded,
                size: 22,
                color: scheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final note = context.read<NoteEditorBloc>().state.note;
    if (note == null) return;
    await ShareNearbySheet.show(context, notes: [note]);
  }
}
