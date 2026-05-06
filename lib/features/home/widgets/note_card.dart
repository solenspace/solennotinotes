import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import 'package:noti_notes_app/features/note_editor/widgets/editor_block.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/theme/curated_palettes.dart';
import 'package:noti_notes_app/theme/tokens.dart';

import '../bloc/notes_list_bloc.dart';
import '../bloc/notes_list_event.dart';

/// Visual card for a note in the masonry grid. Designed to read well at small
/// sizes with auto-contrast text on per-note color backgrounds.
class NoteCard extends StatefulWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tokens = context.tokens;
    final note = widget.note;
    final swatch = NotesColorPalette.swatchFor(note.colorBackground);

    // Resolve background based on theme (light/dark)
    final activeBgColor = swatch?.background(brightness) ?? note.colorBackground;

    // Determine text color based on gradient or active background
    Color computeTextColor() {
      if (note.hasGradient && note.gradient != null) {
        final avgLuminance = note.gradient!.colors.first.computeLuminance();
        return avgLuminance > 0.5
            ? tokens.colors.inkOnLightSurface
            : tokens.colors.inkOnDarkSurface;
      }
      return swatch?.autoTextColor(brightness) ??
          (activeBgColor.computeLuminance() > 0.5
              ? tokens.colors.inkOnLightSurface
              : tokens.colors.inkOnDarkSurface);
    }

    final textColor = computeTextColor();

    final blocks =
        note.blocks.isNotEmpty ? note.blocks.map(EditorBlock.fromMap).toList() : <EditorBlock>[];

    final textBlocks = blocks.whereType<TextBlock>().toList();
    final checklistBlocks = blocks.whereType<ChecklistBlock>().toList();
    final imageBlocks = blocks.whereType<ImageBlock>().toList();
    final hasContent = textBlocks.any((b) => b.text.isNotEmpty) ||
        checklistBlocks.isNotEmpty ||
        imageBlocks.isNotEmpty ||
        note.title.isNotEmpty;

    final preview = textBlocks.map((b) => b.text).where((t) => t.isNotEmpty).join('\n');

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: () {
        HapticFeedback.selectionClick();
        widget.onLongPress();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: DurationPrimitives.fast,
        curve: CurvePrimitives.calm,
        child: Container(
          decoration: BoxDecoration(
            color: note.hasGradient ? null : activeBgColor,
            gradient: note.hasGradient ? note.gradient : null,
            borderRadius: BorderRadius.circular(RadiusPrimitives.sm), // Neo-brutalist tight radius
            image: note.patternImage != null
                ? DecorationImage(
                    image: AssetImage(note.patternImage!),
                    fit: BoxFit.cover,
                    opacity: 0.4,
                    colorFilter: ColorFilter.mode(
                      activeBgColor,
                      BlendMode.softLight,
                    ),
                  )
                : null,
            border: Border.all(
              color: brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.15),
              width: 1.0, // Thin, sharp border matching the component
            ),
          ),
          padding: const EdgeInsets.all(SpacingPrimitives.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (note.isPinned)
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    Icons.push_pin,
                    size: 14,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              if (imageBlocks.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
                  child: Image.file(
                    File(imageBlocks.first.path),
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 60,
                      color: textColor.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                const Gap(SpacingPrimitives.sm),
              ],
              if (note.title.isNotEmpty)
                Text(
                  note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: textColor,
                      ),
                ),
              if (preview.isNotEmpty) ...[
                if (note.title.isNotEmpty) const Gap(SpacingPrimitives.xs),
                Text(
                  preview,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: textColor.withValues(alpha: 0.85),
                      ),
                ),
              ],
              if (checklistBlocks.isNotEmpty) ...[
                const Gap(SpacingPrimitives.xs),
                ...checklistBlocks.take(4).map(
                      (b) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          // Locate this block in the original list and toggle it
                          final updatedBlocks = note.blocks.map((map) {
                            if (map['id'] == b.id) {
                              return {
                                ...map,
                                'checked': !b.checked,
                              };
                            }
                            return map;
                          }).toList();
                          context
                              .read<NotesListBloc>()
                              .add(NoteBlocksReplaced(note.id, updatedBlocks));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                b.checked ? Icons.check_box : Icons.check_box_outline_blank,
                                size: 18,
                                color: textColor.withValues(alpha: 0.85),
                              ),
                              const Gap(SpacingPrimitives.sm),
                              Expanded(
                                child: Text(
                                  b.text.isEmpty ? 'Untitled task' : b.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: textColor.withValues(
                                          alpha: b.checked ? 0.5 : 0.85,
                                        ),
                                        decoration: b.checked ? TextDecoration.lineThrough : null,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                if (checklistBlocks.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+${checklistBlocks.length - 4} more',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: textColor.withValues(alpha: 0.6),
                          ),
                    ),
                  ),
              ],
              if (note.tags.isNotEmpty) ...[
                const Gap(SpacingPrimitives.sm),
                Wrap(
                  spacing: SpacingPrimitives.xs,
                  runSpacing: SpacingPrimitives.xs,
                  children: note.tags.take(3).map((t) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
                        border: Border.all(color: textColor.withValues(alpha: 0.3), width: 1.0),
                      ),
                      child: Text(
                        '#$t',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: textColor,
                            ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (note.reminder != null) ...[
                const Gap(SpacingPrimitives.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      size: 12,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                    const Gap(SpacingPrimitives.xs),
                    Text(
                      DateFormat('MMM d · HH:mm').format(note.reminder!),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: textColor.withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ],
              if (!hasContent)
                Text(
                  'Empty note',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: textColor.withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                ),
              const Gap(SpacingPrimitives.sm),
              Text(
                DateFormat('MMM d').format(note.dateCreated),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: textColor.withValues(alpha: 0.55),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
