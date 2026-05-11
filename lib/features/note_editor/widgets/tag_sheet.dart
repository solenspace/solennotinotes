import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:material_tag_editor/tag_editor.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';
import 'package:noti_notes_app/widgets/sheets/sheet_scaffold.dart';

/// Tag editor in a bottom sheet. Suggested tags are surfaced from the most-
/// used set across all notes; tapping one adds it instantly. Free input uses
/// comma as the delimiter.
class TagSheet extends StatefulWidget {
  final String noteId;
  const TagSheet({super.key, required this.noteId});

  @override
  State<TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<TagSheet> {
  /// Loaded asynchronously from `NotesRepository.getAll()` because the
  /// editor BLoC scopes to a single note. Empty until the load completes.
  List<String> _suggestedTags = const [];

  @override
  void initState() {
    super.initState();
    _loadSuggestedTags();
  }

  Future<void> _loadSuggestedTags() async {
    final repo = context.read<NotesRepository>();
    final all = await repo.getAll();
    if (!mounted) return;
    final counts = <String, int>{};
    for (final n in all) {
      for (final tag in n.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    setState(() {
      _suggestedTags = sorted.take(5).map((e) => e.key).toList(growable: false);
    });
  }

  void _addTag(String tag) {
    final cleaned = tag.trim();
    if (cleaned.isEmpty) return;
    final current = context.read<NoteEditorBloc>().state.note?.tags ?? const <String>{};
    if (current.contains(cleaned)) return;
    context.read<NoteEditorBloc>().add(TagAdded(cleaned));
  }

  void _removeTag(int index) {
    context.read<NoteEditorBloc>().add(TagRemovedAtIndex(index));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      builder: (context, state) {
        final tags = state.note?.tags.toList(growable: false) ?? const <String>[];
        final suggested = _suggestedTags.where((t) => !tags.contains(t)).toList();
        final scheme = Theme.of(context).colorScheme;

        return SheetScaffold(
          title: context.l10n.tag_sheet_title,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (suggested.isNotEmpty) ...[
                  Text(
                    context.l10n.tag_section_suggested,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const Gap(SpacingPrimitives.sm),
                  Wrap(
                    spacing: SpacingPrimitives.sm,
                    runSpacing: SpacingPrimitives.sm,
                    children: suggested
                        .map(
                          (tag) => ActionChip(
                            label: Text(context.l10n.tag_chip_label(tag)),
                            onPressed: () => _addTag(tag),
                          ),
                        )
                        .toList(),
                  ),
                  const Gap(SpacingPrimitives.lg),
                ],
                Text(
                  context.l10n.tag_section_your_tags,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const Gap(SpacingPrimitives.sm),
                Container(
                  padding: const EdgeInsets.all(SpacingPrimitives.md),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
                  ),
                  child: TagEditor(
                    length: tags.length,
                    delimiters: const [','],
                    hasAddButton: false,
                    resetTextOnSubmitted: true,
                    inputDecoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: context.l10n.tag_input_hint,
                    ),
                    textStyle: Theme.of(context).textTheme.bodyLarge,
                    onSubmitted: _addTag,
                    onTagChanged: _addTag,
                    tagBuilder: (context, index) => Container(
                      margin: const EdgeInsets.only(right: 6, bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
                        border: Border.all(color: scheme.outline, width: 1.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.tag_chip_label(tags[index]),
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                ),
                          ),
                          const Gap(4),
                          GestureDetector(
                            onTap: () => _removeTag(index),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Gap(SpacingPrimitives.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.common_done),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
