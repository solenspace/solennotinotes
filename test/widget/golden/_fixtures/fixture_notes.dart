import 'package:flutter/material.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/theme/contrast.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

/// Deterministic notes for golden tests: fixed UUIDs, fixed timestamps, no
/// images or audio (golden tests do not exercise the filesystem). Mirrors
/// the `_buildNote` pattern from `test/features/home/bloc/notes_list_bloc_test.dart`.
Note fixtureNoteA() => Note(
      {'home', 'design'},
      null,
      null,
      const <Map<String, dynamic>>[],
      null,
      null,
      id: 'g-note-a',
      title: 'Designs to review',
      content: '',
      dateCreated: DateTime.utc(2026, 1, 1, 9),
      colorBackground: const Color(0xFFEDE6D6),
      fontColor: const Color(0xFF1C1B1A),
      hasGradient: false,
      isPinned: true,
      blocks: const <Map<String, dynamic>>[
        {'type': 'text', 'id': 'a-text-1', 'text': 'Audit token system before Phase 7 polish.'},
        {'type': 'checklist', 'id': 'a-chk-1', 'text': 'Lock palette tokens', 'checked': true},
        {'type': 'checklist', 'id': 'a-chk-2', 'text': 'Lock pattern alphas', 'checked': false},
      ],
    );

Note fixtureNoteB() => Note(
      {'errands'},
      null,
      null,
      const <Map<String, dynamic>>[],
      null,
      null,
      id: 'g-note-b',
      title: 'Groceries',
      content: '',
      dateCreated: DateTime.utc(2026, 1, 2, 11),
      colorBackground: const Color(0xFFE8D8BD),
      fontColor: const Color(0xFF1C1B1A),
      hasGradient: false,
      blocks: const <Map<String, dynamic>>[
        {'type': 'checklist', 'id': 'b-chk-1', 'text': 'Olive oil', 'checked': false},
        {'type': 'checklist', 'id': 'b-chk-2', 'text': 'Tomatoes', 'checked': true},
        {'type': 'checklist', 'id': 'b-chk-3', 'text': 'Bread', 'checked': false},
      ],
    );

Note fixtureNoteC() => Note(
      const <String>{},
      null,
      null,
      const <Map<String, dynamic>>[],
      null,
      null,
      id: 'g-note-c',
      title: '',
      content: '',
      dateCreated: DateTime.utc(2026, 1, 3, 14),
      colorBackground: const Color(0xFF2D2D2D),
      fontColor: const Color(0xFFEDEDED),
      hasGradient: false,
      blocks: const <Map<String, dynamic>>[
        {
          'type': 'text',
          'id': 'c-text-1',
          'text': 'Thinking in tokens, not values. Each palette is a contract.',
        },
      ],
    );

List<Note> fixtureNotes() => [fixtureNoteA(), fixtureNoteB(), fixtureNoteC()];

/// Re-skins every fixture note with [overlay] — `colorBackground`,
/// `fontColor`, and `patternImage` are rewritten exactly the way
/// `NoteEditorBloc._writeOverlay` does in production. Used by goldens to
/// make palette / pattern variants visibly distinct without inventing new
/// fixture data per variant.
List<Note> fixtureNotesWithOverlay(NotiThemeOverlay overlay) {
  return fixtureNotes()
      .map(
        (n) => n
          ..colorBackground = overlay.surface
          ..fontColor = overlay.onSurface ?? clampForReadability(overlay.surface)
          ..gradient = null
          ..hasGradient = false
          ..patternImage = overlay.patternKey?.name,
      )
      .toList();
}

/// Convenience: re-skins fixtures with the given palette plus an optional
/// [pattern] override.
List<Note> fixtureNotesFor({
  required NotiThemeOverlay palette,
  NotiPatternKey? pattern,
}) {
  final overlay = palette.copyWith(patternKey: pattern, clearPattern: pattern == null);
  return fixtureNotesWithOverlay(overlay);
}
