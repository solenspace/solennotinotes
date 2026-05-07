import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/cubit/ai_assist_cubit.dart';
import 'package:noti_notes_app/features/note_editor/cubit/ai_assist_state.dart';
import 'package:noti_notes_app/features/note_editor/widgets/ai_streaming_pane.dart';
import 'package:noti_notes_app/models/editor_block.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/services/ai/ai_action.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Three-mode bottom sheet for AI assist (Spec 20):
///
///   1. **Picker** — three action tiles (Summarize / Rewrite / Suggest
///      title). Tapping one starts generation.
///   2. **Streaming** — [AiStreamingPane] renders tokens as they
///      arrive; the Stop button (always visible) cancels generation
///      within one token.
///   3. **Result** — the finished draft is selectable text. Accept
///      buttons (Replace / Append / Discard for summarize+rewrite,
///      "Use this title" + radio list for suggest-title) dispatch the
///      right event on `NoteEditorBloc` and dismiss the sheet.
///
/// The sheet does not own any bloc lifetime — it threads the editor's
/// existing [NoteEditorBloc] and the route's [AiAssistCubit] through
/// `BlocProvider.value` so the cubit's state persists across rapid
/// open / close cycles, and accept paths route through the same
/// editor bloc that owns the note.
class AiAssistSheet extends StatelessWidget {
  const AiAssistSheet({super.key});

  static Future<void> show(BuildContext context) {
    final aiCubit = context.read<AiAssistCubit>();
    final editorBloc = context.read<NoteEditorBloc>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.tokens.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.tokens.shape.lg),
        ),
      ),
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider<AiAssistCubit>.value(value: aiCubit),
          BlocProvider<NoteEditorBloc>.value(value: editorBloc),
        ],
        child: const AiAssistSheet(),
      ),
    ).whenComplete(aiCubit.reset);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          const _DragHandle(),
          const _PrivacyBanner(),
          Expanded(
            child: BlocBuilder<AiAssistCubit, AiAssistState>(
              builder: (context, state) {
                if (state.activeAction == null) {
                  return _PickerBody(scrollController: scroll);
                }
                if (state.finished || state.errorMessage != null) {
                  return _ResultBody(state: state);
                }
                return const _StreamingBody();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: tokens.colors.divider,
        borderRadius: tokens.shape.pillRadius,
      ),
    );
  }
}

/// "Running on this device — nothing leaves it." — Spec 20 § "Privacy
/// reinforcement". The sheet's anchor microcopy. Lives at the top of
/// every mode so the reassurance is the first thing the user sees.
class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: scheme.onSurfaceVariant),
          Gap(tokens.spacing.xs),
          Expanded(
            child: Text(
              'Running on this device — nothing leaves it.',
              style: tokens.text.labelSm.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody({required this.scrollController});
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.md,
      ),
      children: [
        for (final action in AiAction.values) ...[
          _ActionTile(action: action),
          Gap(tokens.spacing.sm),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});
  final AiAction action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        onTap: () => _start(context),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.label, style: Theme.of(context).textTheme.titleMedium),
                    Gap(tokens.spacing.xs),
                    Text(
                      action.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final cubit = context.read<AiAssistCubit>();
    final editorState = context.read<NoteEditorBloc>().state;
    final note = editorState.note;
    final noteText = note == null ? '' : _extractNoteText(note);
    if (noteText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some text to the note first.')),
      );
      return;
    }
    await cubit.start(action: action, noteText: noteText);
  }
}

class _StreamingBody extends StatelessWidget {
  const _StreamingBody();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        const Expanded(child: AiStreamingPane()),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.lg,
            vertical: tokens.spacing.md,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('Stop'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.onSurface,
                ),
                onPressed: () => context.read<AiAssistCubit>().stop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultBody extends StatefulWidget {
  const _ResultBody({required this.state});
  final AiAssistState state;

  @override
  State<_ResultBody> createState() => _ResultBodyState();
}

class _ResultBodyState extends State<_ResultBody> {
  int _selectedTitleIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final isTitleAction = widget.state.activeAction == AiAction.suggestTitle;
    final titles = widget.state.titleSuggestions;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.lg,
              vertical: tokens.spacing.md,
            ),
            child: SingleChildScrollView(
              child: isTitleAction && titles.isNotEmpty
                  ? _TitleOptions(
                      titles: titles,
                      selectedIndex: _selectedTitleIndex,
                      onSelect: (i) => setState(() => _selectedTitleIndex = i),
                    )
                  : SelectableText(
                      widget.state.draftOutput.isEmpty
                          ? '(Empty result.)'
                          : widget.state.draftOutput,
                      style: tokens.text.bodyLg.copyWith(color: scheme.onSurface),
                    ),
            ),
          ),
        ),
        if (widget.state.errorMessage != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
            child: Text(
              widget.state.errorMessage!,
              style: tokens.text.bodySm.copyWith(color: scheme.error),
            ),
          ),
        Padding(
          padding: EdgeInsets.all(tokens.spacing.md),
          child: _AcceptButtons(
            state: widget.state,
            selectedTitleIndex: _selectedTitleIndex,
          ),
        ),
      ],
    );
  }
}

class _TitleOptions extends StatelessWidget {
  const _TitleOptions({
    required this.titles,
    required this.selectedIndex,
    required this.onSelect,
  });
  final List<String> titles;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return RadioGroup<int>(
      groupValue: selectedIndex,
      onChanged: (v) {
        if (v != null) onSelect(v);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < titles.length; i++)
            RadioListTile<int>(
              value: i,
              contentPadding: EdgeInsets.zero,
              title: Text(titles[i], style: tokens.text.bodyLg),
              dense: true,
            ),
        ],
      ),
    );
  }
}

class _AcceptButtons extends StatelessWidget {
  const _AcceptButtons({required this.state, required this.selectedTitleIndex});
  final AiAssistState state;
  final int selectedTitleIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isTitle = state.activeAction == AiAction.suggestTitle;
    final draftEmpty = state.draftOutput.trim().isEmpty;

    if (isTitle) {
      final titles = state.titleSuggestions;
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Discard'),
            ),
          ),
          Gap(tokens.spacing.sm),
          Expanded(
            child: FilledButton(
              onPressed:
                  titles.isEmpty ? null : () => _useTitle(context, titles[selectedTitleIndex]),
              child: const Text('Use this title'),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Discard'),
          ),
        ),
        Gap(tokens.spacing.sm),
        Expanded(
          child: OutlinedButton(
            onPressed: draftEmpty ? null : () => _append(context, state.draftOutput),
            child: const Text('Append'),
          ),
        ),
        Gap(tokens.spacing.sm),
        Expanded(
          child: FilledButton(
            onPressed: draftEmpty ? null : () => _replace(context, state.draftOutput),
            child: const Text('Replace'),
          ),
        ),
      ],
    );
  }

  void _replace(BuildContext context, String output) {
    final note = context.read<NoteEditorBloc>().state.note;
    if (note == null) {
      Navigator.of(context).pop();
      return;
    }
    final newBlocks = _replaceTextBlocks(note.blocks, output.trim());
    context.read<NoteEditorBloc>().add(BlocksReplaced(newBlocks));
    Navigator.of(context).pop();
  }

  void _append(BuildContext context, String output) {
    final note = context.read<NoteEditorBloc>().state.note;
    if (note == null) {
      Navigator.of(context).pop();
      return;
    }
    final newBlocks = [
      ...note.blocks.map(_cloneBlock),
      newTextBlock(output.trim()).toMap(),
    ];
    context.read<NoteEditorBloc>().add(BlocksReplaced(newBlocks));
    Navigator.of(context).pop();
  }

  void _useTitle(BuildContext context, String title) {
    context.read<NoteEditorBloc>().add(TitleChanged(title));
    Navigator.of(context).pop();
  }
}

/// Concatenate every text-bearing block (text + checklist) into a single
/// string, separated by blank lines. Image / audio blocks are skipped —
/// their content is not text the model can reason about. Whitespace-only
/// strings are filtered so the prompt does not get padded with empty
/// lines.
String _extractNoteText(Note note) {
  final buffer = StringBuffer();
  if (note.title.trim().isNotEmpty) {
    buffer.writeln(note.title.trim());
    buffer.writeln();
  }
  for (final raw in note.blocks) {
    final type = raw['type'] as String?;
    if (type != 'text' && type != 'checklist') continue;
    final text = (raw['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) continue;
    if (type == 'checklist') {
      final checked = raw['checked'] as bool? ?? false;
      buffer.writeln('${checked ? '- [x]' : '- [ ]'} $text');
    } else {
      buffer.writeln(text);
    }
    buffer.writeln();
  }
  return buffer.toString().trimRight();
}

/// Build a fresh `BlocksReplaced` payload that swaps every text-bearing
/// block in the source list with a single new `text` block carrying
/// [output]. Image / audio blocks survive in their original positions
/// — Spec 20 § "Result handling" calls out this preservation.
List<Map<String, dynamic>> _replaceTextBlocks(
  List<Map<String, dynamic>> source,
  String output,
) {
  final out = <Map<String, dynamic>>[];
  var inserted = false;
  for (final block in source) {
    final type = block['type'] as String?;
    final isText = type == 'text' || type == 'checklist';
    if (isText) {
      if (!inserted) {
        out.add(newTextBlock(output).toMap());
        inserted = true;
      }
      // Drop the source text block — it has been folded into the new one.
      continue;
    }
    out.add(_cloneBlock(block));
  }
  if (!inserted) out.add(newTextBlock(output).toMap());
  return out;
}

Map<String, dynamic> _cloneBlock(Map<String, dynamic> b) => Map<String, dynamic>.from(b);
