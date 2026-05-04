# 06 — bloc-migration-editor

## Goal

Migrate `lib/features/note_editor/screen.dart` (and the supporting widgets under `lib/features/note_editor/widgets/`) from the legacy `Notes` ChangeNotifier to a **per-route `NoteEditorBloc`**. Every per-note mutation handled by `Notes` today (22 actions: title, blocks, tags, images, colors, pattern, gradient, font color, display mode, reminder, todos, pin, delete) becomes one of the BLoC's events. Save semantics match today: **per-action persistence** — every event handler ends with `repository.save(...)`. After this spec, the editor screen does not import `package:provider`, and the legacy provider's per-note mutation methods are marked deprecated for removal in Spec 08.

## Dependencies

- [05-bloc-introduction-home](05-bloc-introduction-home.md) — establishes `flutter_bloc`, `RepositoryProvider`, `bloc_test`, `FakeNotesRepository`, and the file/event/state conventions this spec follows. **Read Spec 05 first**; this spec uses the same template.
- [04-repository-layer](04-repository-layer.md) — `NotesRepository.save`, `delete`, `getAll` are the BLoC's only data-access primitives.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — per-route `BlocProvider` patterns, side-effect signaling without `BuildContext`.
- `dart-flutter-patterns` — sealed events, immutable state.
- `dart-add-unit-test` — `bloc_test` per event.

**After-coding agents:**
- `flutter-expert` — audit the 22 handlers for missed `state.note == null` guards, missing `await repository.save`, accidental field swaps; verify the `popRequested` one-shot flag pattern works.
- `test-automator` — coverage review; ensure each of 22 events plus the EditorOpened(null/missing) paths is tested.
- `code-reviewer` — behavioral parity with the legacy `Notes` provider's per-note mutation methods.

## Design Decisions

- **Per-route BLoC scope.** `BlocProvider.create` mounts `NoteEditorBloc` when the editor route is pushed and disposes when it pops. The BLoC's lifetime equals the editor's lifetime; no global state, no `setActiveNote(id)` switching.
- **Per-action persistence preserved.** Every event handler calls `repository.save(updatedNote)` (or `repository.delete(id)`) before emitting state. No debouncing, no draft-and-save-on-exit. Same I/O profile as the legacy provider.
- **One event per user action — 22 events.** Maximum debuggability with `LoggingBlocObserver`; uniform with `NotesListBloc`. Small repetition cost; large clarity win in tests.
- **Editor opens in two modes via a single event.** `EditorOpened(noteId)` with `noteId == null` means "start a new note" — the BLoC creates a fresh `Note` in memory, emits `ready` with the blank note, and saves on the first content-bearing event. `EditorOpened(noteId: 'xyz')` means "load and edit existing" — reads from `repository.getAll()`, finds by id, emits `ready` or `notFound`.
- **State holds the working note plus a status enum.** `NoteEditorStatus.{loading, ready, notFound, saving, error}`. Mutations transition through `saving` only when the implementer wants visual feedback; for instant edits like title typing, the bloc emits the new state directly without a `saving` flicker.
- **`PinToggled` exists on both `NotesListBloc` (Spec 05) and `NoteEditorBloc` (this spec).** Both call `repository.save(note.copyWith(isPinned: !isPinned))`; consistency is guaranteed because the repository stream re-emits to both. No coordination logic needed.
- **`NoteDeleted` cancels notifications inside the editor BLoC** (parity with the home BLoC's bulk-delete handler) and pops the route via a one-shot side-effect emission. Pattern: emit a `NoteEditorState` with a non-equatable `popRequested` flag, the screen listens with `BlocListener`, navigates back, and the next state clears the flag. This avoids coupling the BLoC to `BuildContext`.
- **Image add/remove cleans up files via the repository.** `repository.save` does not delete the previous image automatically (it's a save, not a delta); the BLoC handles the old-file cleanup in `_onImageRemoved` and `_onImageSelected` (when overwriting) by calling the `ImagePickerService` directly. Future spec can move this into `NotesRepository.replaceImage(...)` if it becomes a recurring pattern.
- **Block-based editor logic is preserved.** `BlocksReplaced(List<Map<String, dynamic>>)` mirrors the legacy `replaceBlocks`. The block format (text/checklist/image map shape) is not refactored in this spec; that lives in a later editor-content spec.
- **Tag list is treated as ordered.** Legacy `removeTagsFromNote(index, id)` removed by index; we keep that contract. The new `TagRemovedAtIndex(index)` event preserves index semantics so existing UI (which renders tags as a list) keeps working.
- **No new packages.** Everything lands on top of Spec 05's `flutter_bloc` + `equatable` + `bloc_test` + `mocktail`.

## Implementation

### A. Files to create

```
lib/features/note_editor/bloc/
├── note_editor_bloc.dart
├── note_editor_event.dart
└── note_editor_state.dart

test/features/note_editor/bloc/
└── note_editor_bloc_test.dart
```

### B. `note_editor_state.dart`

```dart
import 'package:equatable/equatable.dart';
import 'package:noti_notes_app/models/note.dart';

enum NoteEditorStatus { initial, loading, ready, notFound, saving, error }

class NoteEditorState extends Equatable {
  const NoteEditorState({
    this.status = NoteEditorStatus.initial,
    this.note,
    this.popRequested = false,
    this.errorMessage,
  });

  final NoteEditorStatus status;
  final Note? note;

  /// One-shot signal: when true, the screen should pop the route. The next
  /// state emission will reset this to false.
  final bool popRequested;

  final String? errorMessage;

  NoteEditorState copyWith({
    NoteEditorStatus? status,
    Note? note,
    bool? popRequested,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NoteEditorState(
      status: status ?? this.status,
      note: note ?? this.note,
      popRequested: popRequested ?? false,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, note, popRequested, errorMessage];
}
```

> Note: `popRequested` resets to `false` on every `copyWith`; this gives the side-effect a single emission. The screen's `BlocListener` reacts to `state.popRequested == true`, calls `Navigator.pop(context)`, and the next state will already have `popRequested: false`.

### C. `note_editor_event.dart`

```dart
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:noti_notes_app/models/note.dart';

sealed class NoteEditorEvent extends Equatable {
  const NoteEditorEvent();

  @override
  List<Object?> get props => const [];
}

/// Mounted by the screen's BlocProvider.create. `noteId == null` means
/// "create a new note"; non-null means "load and edit existing".
final class EditorOpened extends NoteEditorEvent {
  const EditorOpened({this.noteId});
  final String? noteId;
  @override
  List<Object?> get props => [noteId];
}

// — Title and content —
final class TitleChanged extends NoteEditorEvent {
  const TitleChanged(this.title);
  final String title;
  @override
  List<Object?> get props => [title];
}

final class BlocksReplaced extends NoteEditorEvent {
  const BlocksReplaced(this.blocks);
  final List<Map<String, dynamic>> blocks;
  @override
  List<Object?> get props => [blocks];
}

// — Tags —
final class TagAdded extends NoteEditorEvent {
  const TagAdded(this.tag);
  final String tag;
  @override
  List<Object?> get props => [tag];
}

final class TagRemovedAtIndex extends NoteEditorEvent {
  const TagRemovedAtIndex(this.index);
  final int index;
  @override
  List<Object?> get props => [index];
}

// — Image —
final class ImageSelected extends NoteEditorEvent {
  const ImageSelected(this.file);
  final File file;
  @override
  List<Object?> get props => [file.path];
}

final class ImageRemoved extends NoteEditorEvent {
  const ImageRemoved();
}

// — Theme / appearance —
final class BackgroundColorChanged extends NoteEditorEvent {
  const BackgroundColorChanged(this.color);
  final Color color;
  @override
  List<Object?> get props => [color];
}

final class PatternImageSet extends NoteEditorEvent {
  const PatternImageSet(this.patternKey);
  final String patternKey;
  @override
  List<Object?> get props => [patternKey];
}

final class PatternImageRemoved extends NoteEditorEvent {
  const PatternImageRemoved();
}

final class FontColorChanged extends NoteEditorEvent {
  const FontColorChanged(this.color);
  final Color color;
  @override
  List<Object?> get props => [color];
}

final class DisplayModeChanged extends NoteEditorEvent {
  const DisplayModeChanged(this.mode);
  final DisplayMode mode;
  @override
  List<Object?> get props => [mode];
}

final class GradientChanged extends NoteEditorEvent {
  const GradientChanged(this.gradient);
  final LinearGradient gradient;
  @override
  List<Object?> get props => [gradient];
}

final class GradientToggled extends NoteEditorEvent {
  const GradientToggled();
}

// — Reminder —
final class ReminderSet extends NoteEditorEvent {
  const ReminderSet(this.dateTime);
  final DateTime dateTime;
  @override
  List<Object?> get props => [dateTime];
}

final class ReminderRemoved extends NoteEditorEvent {
  const ReminderRemoved();
}

// — Todos —
final class TaskAdded extends NoteEditorEvent {
  const TaskAdded();
}

final class TaskToggledAtIndex extends NoteEditorEvent {
  const TaskToggledAtIndex(this.index);
  final int index;
  @override
  List<Object?> get props => [index];
}

final class TaskRemovedAtIndex extends NoteEditorEvent {
  const TaskRemovedAtIndex(this.index);
  final int index;
  @override
  List<Object?> get props => [index];
}

final class TaskContentUpdatedAtIndex extends NoteEditorEvent {
  const TaskContentUpdatedAtIndex({required this.index, required this.content});
  final int index;
  final String content;
  @override
  List<Object?> get props => [index, content];
}

// — Pin / delete —
final class PinToggled extends NoteEditorEvent {
  const PinToggled();
}

final class NoteDeleted extends NoteEditorEvent {
  const NoteDeleted();
}
```

### D. `note_editor_bloc.dart`

The BLoC has 22 handlers; each follows the same shape. The full file is mechanical translation of the legacy provider's methods. Below is the skeleton + three representative handlers; the rest follow identically.

```dart
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';
import 'package:uuid/uuid.dart';

import 'note_editor_event.dart';
import 'note_editor_state.dart';

class NoteEditorBloc extends Bloc<NoteEditorEvent, NoteEditorState> {
  NoteEditorBloc({
    required NotesRepository repository,
    ImagePickerService? imageService,
  })  : _repository = repository,
        _imageService = imageService ?? const ImagePickerService(),
        super(const NoteEditorState()) {
    on<EditorOpened>(_onEditorOpened);
    on<TitleChanged>(_onTitleChanged);
    on<BlocksReplaced>(_onBlocksReplaced);
    on<TagAdded>(_onTagAdded);
    on<TagRemovedAtIndex>(_onTagRemovedAtIndex);
    on<ImageSelected>(_onImageSelected);
    on<ImageRemoved>(_onImageRemoved);
    on<BackgroundColorChanged>(_onBackgroundColorChanged);
    on<PatternImageSet>(_onPatternImageSet);
    on<PatternImageRemoved>(_onPatternImageRemoved);
    on<FontColorChanged>(_onFontColorChanged);
    on<DisplayModeChanged>(_onDisplayModeChanged);
    on<GradientChanged>(_onGradientChanged);
    on<GradientToggled>(_onGradientToggled);
    on<ReminderSet>(_onReminderSet);
    on<ReminderRemoved>(_onReminderRemoved);
    on<TaskAdded>(_onTaskAdded);
    on<TaskToggledAtIndex>(_onTaskToggledAtIndex);
    on<TaskRemovedAtIndex>(_onTaskRemovedAtIndex);
    on<TaskContentUpdatedAtIndex>(_onTaskContentUpdatedAtIndex);
    on<PinToggled>(_onPinToggled);
    on<NoteDeleted>(_onNoteDeleted);
  }

  final NotesRepository _repository;
  final ImagePickerService _imageService;

  Future<void> _onEditorOpened(
    EditorOpened event,
    Emitter<NoteEditorState> emit,
  ) async {
    emit(state.copyWith(status: NoteEditorStatus.loading));
    if (event.noteId == null) {
      emit(state.copyWith(status: NoteEditorStatus.ready, note: _blankNote()));
      return;
    }
    final all = await _repository.getAll();
    final found = all.where((n) => n.id == event.noteId).firstOrNull;
    if (found == null) {
      emit(state.copyWith(status: NoteEditorStatus.notFound));
      return;
    }
    emit(state.copyWith(status: NoteEditorStatus.ready, note: found));
  }

  Future<void> _onTitleChanged(
    TitleChanged event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    note.title = event.title;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  // ...repeat the same shape for the other 20 handlers; each:
  // 1. read state.note (early return if null)
  // 2. mutate the field per the legacy method
  // 3. await _repository.save(note) — except for NoteDeleted
  // 4. emit(state.copyWith(note: note))
  //
  // Two non-trivial handlers below.

  Future<void> _onImageSelected(
    ImageSelected event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    final old = note.imageFile;
    if (old != null && old.path != event.file.path) {
      await _imageService.removeImage(old);
    }
    note.imageFile = event.file;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onImageRemoved(
    ImageRemoved event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    final old = note.imageFile;
    if (old != null) {
      await _imageService.removeImage(old);
    }
    note.imageFile = null;
    await _repository.save(note);
    emit(state.copyWith(note: note));
  }

  Future<void> _onNoteDeleted(
    NoteDeleted event,
    Emitter<NoteEditorState> emit,
  ) async {
    final note = state.note;
    if (note == null) return;
    // Notification cancellation is index-based in the legacy API; for the
    // editor we use the note's hashCode-as-id heuristic the legacy provider
    // also relied on (findIndex). Future notifications spec refactors to id.
    await LocalNotificationService.cancelNotification(note.id.hashCode & 0x7fffffff);
    await _repository.delete(note.id);
    emit(state.copyWith(popRequested: true));
  }

  Note _blankNote() {
    return Note(
      const {},
      null,
      null,
      <Map<String, dynamic>>[],
      null,
      null,
      id: const Uuid().v4(),
      title: '',
      content: '',
      dateCreated: DateTime.now(),
      colorBackground: const Color(0xFF2D2D2D),
      fontColor: const Color(0xFFF2EFEA),
      hasGradient: false,
    );
  }
}
```

> The two slim handlers (`_onTitleChanged`, `_onImageSelected`, `_onImageRemoved`, `_onNoteDeleted`) are shown explicitly because they have non-trivial side effects. The remaining 18 handlers mutate one field each then save — write them by mechanical translation of the corresponding legacy method body in `lib/features/home/legacy/notes_provider.dart`. Use `flutter-expert` (subagent) to review the full file before commit.

### E. Update `lib/features/note_editor/screen.dart`

Replace `Provider.of<Notes>(context)` and `context.read<Notes>()` with `BlocProvider` mount + `BlocBuilder` consumption + `BlocListener` for the pop side-effect.

Mount pattern (in the route push site, e.g. from `home/screen.dart`):

```dart
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => BlocProvider(
    create: (ctx) => NoteEditorBloc(
      repository: ctx.read<NotesRepository>(),
    )..add(EditorOpened(noteId: openingId)),  // null for new notes
    child: const NoteEditorScreen(),
  ),
));
```

Inside `NoteEditorScreen`:

```dart
BlocConsumer<NoteEditorBloc, NoteEditorState>(
  listenWhen: (prev, next) => next.popRequested && !prev.popRequested,
  listener: (ctx, state) => Navigator.of(ctx).pop(),
  buildWhen: (prev, next) => prev.note != next.note || prev.status != next.status,
  builder: (ctx, state) {
    return switch (state.status) {
      NoteEditorStatus.loading => const _Loading(),
      NoteEditorStatus.notFound => const _NotFound(),
      NoteEditorStatus.error => _Error(message: state.errorMessage),
      _ => _EditorBody(note: state.note!),
    };
  },
);
```

The widgets under `lib/features/note_editor/widgets/` (`checklist_block.dart`, `editor_block.dart`, `editor_toolbar.dart`, `image_block.dart`, `note_app_bar.dart`, `text_block.dart`, `note_style_sheet.dart`, `reminder_sheet.dart`, `tag_sheet.dart`) are updated to dispatch BLoC events via `context.read<NoteEditorBloc>().add(...)` instead of calling `notes.tooling*(...)`. **No visual change.**

Mapping (exhaustive — implementer uses this as a swap table):

| Legacy call | New event |
|-------------|-----------|
| `notes.updateTitle(id, t)` | `add(TitleChanged(t))` |
| `notes.replaceBlocks(id, b)` | `add(BlocksReplaced(b))` |
| `notes.addTagToNote(tag, id)` | `add(TagAdded(tag))` |
| `notes.removeTagsFromNote(i, id)` | `add(TagRemovedAtIndex(i))` |
| `notes.addImageToNote(id, f)` | `add(ImageSelected(f))` (skip when `f==null`) |
| `notes.removeImageFromNote(id)` | `add(const ImageRemoved())` |
| `notes.changeCurrentColor(id, c)` | `add(BackgroundColorChanged(c))` |
| `notes.changeCurrentPattern(id, p)` | `add(PatternImageSet(p))` (or `PatternImageRemoved` if null) |
| `notes.removeCurrentPattern(id)` | `add(const PatternImageRemoved())` |
| `notes.changeCurrentFontColor(id, c)` | `add(FontColorChanged(c))` |
| `notes.changeCurrentDisplay(id, m)` | `add(DisplayModeChanged(m))` |
| `notes.changeCurrentGradient(id, g)` | `add(GradientChanged(g))` |
| `notes.switchGradient(id)` | `add(const GradientToggled())` |
| `notes.addReminder(id, dt)` | `add(ReminderSet(dt))` |
| `notes.removeReminder(id)` | `add(const ReminderRemoved())` |
| `notes.addTask(id)` | `add(const TaskAdded())` |
| `notes.toggleTask(id, i)` | `add(TaskToggledAtIndex(i))` |
| `notes.removeTask(id, i)` | `add(TaskRemovedAtIndex(i))` |
| `notes.updateTask(id, i, t)` | `add(TaskContentUpdatedAtIndex(index: i, content: t))` |
| `notes.togglePin(id)` | `add(const PinToggled())` |
| `notes.deleteNote(id)` | `add(const NoteDeleted())` |

### F. Add `@Deprecated` annotations on the migrated legacy methods

In `lib/features/home/legacy/notes_provider.dart`, annotate each of the 22 migrated methods with:

```dart
@Deprecated('migrated to NoteEditorBloc; remove in Spec 08')
```

Keep the bodies. Search and settings still call into some of these (e.g. `findById`, the find-by-color helpers); leave those alone — Spec 07 retires them.

### G. Tests

`test/features/note_editor/bloc/note_editor_bloc_test.dart` — at minimum one `blocTest` per event, using `FakeNotesRepository` from Spec 05. Pattern (one example):

```dart
blocTest<NoteEditorBloc, NoteEditorState>(
  'TitleChanged updates note and saves',
  build: () => NoteEditorBloc(repository: fake),
  seed: () => NoteEditorState(
    status: NoteEditorStatus.ready,
    note: _buildNote(id: 'a', title: 'before'),
  ),
  act: (b) => b.add(const TitleChanged('after')),
  expect: () => [
    isA<NoteEditorState>().having((s) => s.note?.title, 'title', 'after'),
  ],
  verify: (_) {
    expect(fake.savedNotes.last.title, 'after');
  },
);
```

Repeat for the other 21 events. Add coverage for:
- `EditorOpened(noteId: null)` — emits `ready` with a non-null `note`, no save.
- `EditorOpened(noteId: 'missing')` — emits `notFound`.
- `NoteDeleted` — calls `repository.delete(id)`, sets `popRequested: true`, then resets to `false` on the next emission.
- `ImageSelected` overwriting an existing image — fake `ImagePickerService` records the old file deletion.

### H. Update [`context/code-standards.md`](../context/code-standards.md)

Append to the `flutter_bloc usage` section:

```markdown
- Per-route BLoCs are mounted via `BlocProvider.create` inside `MaterialPageRoute.builder`. The BLoC's lifetime equals the route's. Initial-load events fire from the cascade in `create:` (`..add(InitEvent())`).
- Side-effect signals (route pop, snackbars, navigation) ride on a one-shot boolean field in state; `BlocListener` reacts and the next state resets the flag. BLoCs do not import `BuildContext`.
```

### I. Update [`context/progress-tracker.md`](../context/progress-tracker.md)

- Mark Spec 06 complete in **Completed**.
- Add to **Architecture decisions**:
  ```markdown
  14. **Per-route `NoteEditorBloc`** with 22 events, per-action persistence via `repository.save`, side-effect signals via `popRequested` boolean. Same template as `NotesListBloc`; legacy provider's per-note mutations marked deprecated for Spec 08.
  ```

## Success Criteria

- [ ] `lib/features/note_editor/bloc/{note_editor_bloc.dart, note_editor_event.dart, note_editor_state.dart}` exist with all 22 events handled.
- [ ] `lib/features/note_editor/screen.dart` and every widget under `lib/features/note_editor/widgets/` consume the BLoC; **no `package:provider` imports** under `lib/features/note_editor/` (verify with `grep -RnE "package:provider" lib/features/note_editor`).
- [ ] The 22 migrated methods on the legacy `Notes` provider are annotated `@Deprecated('migrated to NoteEditorBloc; remove in Spec 08')`. Method bodies are unchanged.
- [ ] `flutter analyze` exits 0.
- [ ] `bash scripts/check-offline.sh` exits 0.
- [ ] `dart format --set-exit-if-changed -l 100 lib/ test/` exits 0.
- [ ] `flutter test` exits 0; `note_editor_bloc_test.dart` covers all 22 events plus the EditorOpened(null) / EditorOpened(missing) paths.
- [ ] **Manual smoke**: open existing note → edit title → close editor → home shows new title. Add a tag → close → reopen → tag persists. Change color → close → list shows new card color. Delete note from editor → editor pops → home no longer shows the note. Create new note from FAB → type → close → appears in list. Pin from editor → home shows pin badge.
- [ ] No imports of Hive, image_picker, flutter_local_notifications, flutter_bloc are added under `lib/features/note_editor/widgets/` (widgets stay pure UI; BLoC is the only orchestrator).
- [ ] [`context/code-standards.md`](../context/code-standards.md), [`context/progress-tracker.md`](../context/progress-tracker.md) updated per Sections H and I.
- [ ] No invariant in [`context/architecture.md`](../context/architecture.md) is changed.
- [ ] No new packages in `pubspec.yaml`.

## References

- [`context/architecture.md`](../context/architecture.md) — invariants 5, 6, 8
- [`context/code-standards.md`](../context/code-standards.md) — flutter_bloc usage (extended by this spec)
- [05-bloc-introduction-home](05-bloc-introduction-home.md) — template; same conventions
- [04-repository-layer](04-repository-layer.md) — `NotesRepository` interface
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Skill: [`dart-add-unit-test`](../.agents/skills/dart-add-unit-test/SKILL.md)
- Agent: `flutter-expert` — invoke after writing the 22 handlers to audit for missed `state.note == null` guards, missing `await repository.save`, or accidental field swaps
- Agent: `code-reviewer` — invoke pre-commit; visual + behavioral parity is the bar
- Follow-ups: [07-bloc-migration-search-and-settings](07-bloc-migration-search-and-settings.md), [08-provider-removal](08-provider-removal.md)
