import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/models/note_overlay.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// AppBar chip rendered when a note's overlay carries a sender identity
/// id (i.e. the note arrived via share). Renders [SizedBox.shrink] for
/// every locally-authored note today; the share-receive flow in spec 24
/// populates the field that lights this up.
///
/// The popup menu offers two actions:
///   * "Keep their style" — no-op, dismisses the menu.
///   * "Convert to mine"  — dispatches [OverlayConvertToMine].
class FromSenderChip extends StatelessWidget {
  const FromSenderChip({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) =>
          a.note?.toOverlay().fromIdentityId != b.note?.toOverlay().fromIdentityId ||
          a.accentOverride != b.accentOverride,
      builder: (ctx, state) {
        final overlay = state.note?.toOverlay();
        final fromId = overlay?.fromIdentityId;
        if (fromId == null) return const SizedBox.shrink();
        return _ChipPopup(
          fromId: fromId,
          accentGlyph: state.accentOverride ?? overlay?.signatureAccent,
          accentColor: overlay?.accent,
        );
      },
    );
  }
}

class _ChipPopup extends StatelessWidget {
  const _ChipPopup({
    required this.fromId,
    required this.accentGlyph,
    required this.accentColor,
  });

  final String fromId;
  final String? accentGlyph;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Display the first six characters of the id until the share-receive
    // spec lands a real display-name lookup.
    final shortId = fromId.length >= 6 ? fromId.substring(0, 6) : fromId;
    return PopupMenuButton<String>(
      tooltip: 'Sender options',
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'keep', child: Text('Keep their style')),
        PopupMenuItem(value: 'mine', child: Text('Convert to mine')),
      ],
      onSelected: (value) {
        if (value == 'mine') {
          context.read<NoteEditorBloc>().add(const OverlayConvertToMine());
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (accentGlyph != null) ...[
              Text(
                accentGlyph!,
                style: tokens.text.labelLg.copyWith(
                  color: accentColor ?? tokens.colors.accent,
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
            ],
            Text(
              'from $shortId',
              style: tokens.text.labelMd.copyWith(color: tokens.colors.onSurface),
            ),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }
}
