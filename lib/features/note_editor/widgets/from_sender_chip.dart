import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/models/note_overlay.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// AppBar chip rendered when a note's overlay carries a sender identity
/// id (i.e. the note arrived via share). Spec 25 populates the underlying
/// `Note.fromIdentityId` + `fromDisplayName` + `fromAccentGlyph` columns
/// on Accept; before that, every locally-authored note renders as
/// [SizedBox.shrink].
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
          a.note?.fromIdentityId != b.note?.fromIdentityId ||
          a.note?.fromDisplayName != b.note?.fromDisplayName ||
          a.note?.fromAccentGlyph != b.note?.fromAccentGlyph ||
          a.accentOverride != b.accentOverride,
      builder: (ctx, state) {
        final note = state.note;
        final fromId = note?.fromIdentityId;
        if (note == null || fromId == null) return const SizedBox.shrink();
        final overlay = note.toOverlay();
        return _ChipPopup(
          fromId: fromId,
          displayName: note.fromDisplayName,
          accentGlyph: state.accentOverride ?? note.fromAccentGlyph,
          accentColor: overlay.accent,
        );
      },
    );
  }
}

class _ChipPopup extends StatelessWidget {
  const _ChipPopup({
    required this.fromId,
    required this.displayName,
    required this.accentGlyph,
    required this.accentColor,
  });

  final String fromId;
  final String? displayName;
  final String? accentGlyph;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : (fromId.length >= 6 ? fromId.substring(0, 6) : fromId);
    return Semantics(
      label: context.l10n.from_sender_semantic_label(label),
      button: true,
      child: PopupMenuButton<String>(
        tooltip: context.l10n.from_sender_tooltip,
        itemBuilder: (_) => [
          PopupMenuItem(value: 'keep', child: Text(context.l10n.from_sender_keep_style)),
          PopupMenuItem(value: 'mine', child: Text(context.l10n.from_sender_convert_mine)),
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
                  style: tokens.text.labelLg.copyWith(color: accentColor),
                ),
                SizedBox(width: tokens.spacing.xs),
              ],
              Text(
                context.l10n.from_sender_chip_label(label),
                style: tokens.text.labelMd.copyWith(color: tokens.colors.onSurface),
              ),
              const Icon(Icons.arrow_drop_down, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
