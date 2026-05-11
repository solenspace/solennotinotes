import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';
import 'package:noti_notes_app/widgets/sheets/sheet_scaffold.dart';

import '../bloc/notes_list_bloc.dart';
import '../bloc/notes_list_event.dart';
import '../bloc/notes_list_state.dart';

/// Bottom sheet shown on long-press of a note card. Replaces the old
/// screen-wide edit mode with a per-card menu (Pin / Duplicate / Delete).
class LongPressMenuSheet extends StatelessWidget {
  final String noteId;
  const LongPressMenuSheet({super.key, required this.noteId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesListBloc, NotesListState>(
      builder: (context, state) {
        final note = state.notes.firstWhereOrNull((n) => n.id == noteId);
        if (note == null) {
          return SheetScaffold(
            title: context.l10n.menu_untitled_note,
            maxHeightFactor: 0.5,
            child: const SizedBox.shrink(),
          );
        }
        return SheetScaffold(
          title: note.title.isEmpty ? context.l10n.menu_untitled_note : note.title,
          maxHeightFactor: 0.5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuTile(
                icon: note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: note.isPinned ? context.l10n.menu_unpin : context.l10n.menu_pin,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.read<NotesListBloc>().add(PinToggled(noteId));
                  Navigator.of(context).pop();
                },
              ),
              const Gap(SpacingPrimitives.xs),
              _MenuTile(
                icon: Icons.delete_outline,
                label: context.l10n.menu_delete,
                destructive: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.read<NotesListBloc>().add(NoteDeleted(noteId));
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? Colors.redAccent : scheme.onSurface;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingPrimitives.lg,
            vertical: SpacingPrimitives.md,
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const Gap(SpacingPrimitives.md),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
