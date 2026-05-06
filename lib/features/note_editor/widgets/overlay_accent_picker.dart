import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/theme/tokens.dart';

const List<String> _suggestedAccents = [
  '☼',
  '✦',
  '⌘',
  '△',
  '❍',
  '✕',
  '☾',
  '◆',
  '✿',
  '★',
  '❀',
  '◯',
];

/// Single-grapheme accent input + suggestion row. The TextField is clamped
/// to one user-perceived character (via the `characters` package) on
/// every change. Any suggestion tap dispatches [OverlayAccentChanged].
class OverlayAccentPicker extends StatefulWidget {
  const OverlayAccentPicker({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  State<OverlayAccentPicker> createState() => _OverlayAccentPickerState();
}

class _OverlayAccentPickerState extends State<OverlayAccentPicker> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initial = context.read<NoteEditorBloc>().state.accentOverride ?? '';
    _controller = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyTyped(String raw) {
    final trimmed = raw.characters.isEmpty ? '' : raw.characters.first;
    if (trimmed != raw) {
      _controller.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
    }
    context.read<NoteEditorBloc>().add(OverlayAccentChanged(trimmed));
  }

  void _pickSuggestion(String glyph) {
    _controller.value = TextEditingValue(
      text: glyph,
      selection: TextSelection.collapsed(offset: glyph.length),
    );
    context.read<NoteEditorBloc>().add(OverlayAccentChanged(glyph));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) => a.accentOverride != b.accentOverride,
      builder: (ctx, state) {
        // Keep the controller in sync with state when something else
        // (Reset / ConvertToMine) changes the accent under us.
        final external = state.accentOverride ?? '';
        if (external != _controller.text) {
          _controller.value = TextEditingValue(
            text: external,
            selection: TextSelection.collapsed(offset: external.length),
          );
        }

        return ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.all(tokens.spacing.lg),
          children: [
            Text(
              'Note signature',
              style: tokens.text.titleSm.copyWith(color: tokens.colors.onSurface),
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              'A single character or emoji that travels with this note.',
              style: tokens.text.bodySm.copyWith(color: tokens.colors.onSurfaceMuted),
            ),
            SizedBox(height: tokens.spacing.md),
            TextField(
              controller: _controller,
              onChanged: _applyTyped,
              autocorrect: false,
              enableSuggestions: false,
              textAlign: TextAlign.center,
              style: tokens.text.displaySm.copyWith(color: tokens.colors.onSurface),
              inputFormatters: [
                LengthLimitingTextInputFormatter(8),
                _SingleGraphemeFormatter(),
              ],
              decoration: InputDecoration(
                hintText: '☼',
                hintStyle: tokens.text.displaySm.copyWith(color: tokens.colors.onSurfaceMuted),
                filled: true,
                fillColor: tokens.colors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: tokens.shape.mdRadius,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.md),
            Text(
              'Suggestions',
              style: tokens.text.labelLg.copyWith(color: tokens.colors.onSurfaceMuted),
            ),
            SizedBox(height: tokens.spacing.sm),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _suggestedAccents.length,
                separatorBuilder: (_, __) => SizedBox(width: tokens.spacing.sm),
                itemBuilder: (_, i) {
                  final glyph = _suggestedAccents[i];
                  final isSelected = state.accentOverride == glyph;
                  return _SuggestionChip(
                    glyph: glyph,
                    selected: isSelected,
                    onTap: () => _pickSuggestion(glyph),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  final String glyph;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: 'Use $glyph as the note signature',
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: tokens.shape.mdRadius,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.colors.surfaceVariant,
            borderRadius: tokens.shape.mdRadius,
            border: Border.all(
              color: selected ? tokens.colors.accent : tokens.colors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(glyph, style: tokens.text.titleLg),
        ),
      ),
    );
  }
}

/// Truncates input to the first user-perceived character on every change.
/// Pasting "☼☾★" keeps "☼"; pasting "👨‍👩‍👧" keeps the full emoji ZWJ
/// sequence as one grapheme.
class _SingleGraphemeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final firstGrapheme = newValue.text.characters.first;
    if (firstGrapheme == newValue.text) return newValue;
    return TextEditingValue(
      text: firstGrapheme,
      selection: TextSelection.collapsed(offset: firstGrapheme.length),
    );
  }
}
