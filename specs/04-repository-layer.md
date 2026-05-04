# 04 — repository-layer

## Goal

Extract every Hive call and on-disk image cleanup out of [`lib/features/home/legacy/notes_provider.dart`](../lib/features/home/legacy/notes_provider.dart) (the post-Spec-03 home of `Notes` ChangeNotifier) into a new **abstract `NotesRepository` interface** with a single concrete `HiveNotesRepository` implementation under `lib/repositories/notes/`. The legacy provider keeps its public surface and `ChangeNotifier` semantics — only its data access stops talking to Hive directly. After this spec, every Hive `box.put` / `box.delete` / `box.values` access for notes lives in the repository, and `flutter analyze` would flag any new screen that reaches into Hive directly (architecture invariant 5).

The repository preserves the existing **JSON-string-in-Hive** storage format. Migration to typed Hive CE adapters is deferred to **Spec 04b**.

## Dependencies

- [01-lint-and-format-hardening](01-lint-and-format-hardening.md) — `flutter analyze` is the gate.
- [02-offline-invariant-ci-gate](02-offline-invariant-ci-gate.md) — repository code passes the forbidden-imports grep + `custom_lint`.
- [03-project-structure-migration](03-project-structure-migration.md) — collocated layout established; provider lives at `lib/features/home/legacy/`.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — repository-pattern guidance (abstract + concrete, separation from BLoC).
- `dart-flutter-patterns` — abstract-class + DI conventions; immutable models with `copyWith`.

**After-coding agents:**
- `flutter-expert` — audit the legacy provider refactor: signatures preserved, no Hive imports leaked into screens, stream subscription closes cleanly.
- `code-reviewer` — verify behavior parity: same `notifyListeners()` cadence, same return types, same error semantics.

## Design Decisions

- **Abstract interface + concrete implementation.** `NotesRepository` (abstract) declares the contract; `HiveNotesRepository` implements it. The abstraction is light (one impl today) but unblocks `bloc_test`-style mocking in Spec 05 without a refactor. We do **not** introduce `mocktail` or `mockito` in this spec; tests for the repo are real-Hive integration tests using `Hive.openBox` against a temp dir.
- **Repository lives at `lib/repositories/notes/`, not under `lib/features/home/`.** `Note` is shared across home, note_editor, search, and (future) share/inbox features. Cross-cutting domain resources go in the parallel `repositories/` root; only feature-internal data goes under `features/<feature>/repository/`. This is a **clarification of [`context/architecture.md`](../context/architecture.md)** (Section F below adds the rule).
- **Future + Stream API per the user's choice.** One-shot operations return `Future<T>`; collection observation returns `Stream<List<T>>` driven by `Hive.box.watch()`. Re-emit the full list on every change; per-key delta is a future optimization.
- **Notification side effects stay in the legacy provider.** `LocalNotificationService.cancelNotification(...)` calls in `removeSelectedNotes` and `deleteNote` are not moved. They migrate to a `NotesNotificationCoordinator` (or directly into the BLoC) when Spec 05 retires the provider.
- **Image-file deletion lives in the repository.** Deleting a note also removes its on-disk image; that's purely a data-layer concern and belongs with Hive cleanup. The repo takes a `PhotoPicker` (renamed `ImagePickerService` in Spec 03) as a constructor dependency; tests pass a fake.
- **No new runtime packages.** `package:provider` is already in `pubspec.yaml` and continues to inject the repo into the widget tree. `flutter_bloc` is **not** added in this spec — that's Spec 05.
- **`Note.fromJson` factory added to the model.** The decode logic in `Notes._loadNotesFromDataBase` (lines 68–115 of the original `notes.dart`) is lifted verbatim into a `factory Note.fromJson(Map<String, dynamic> json)` on the model. This is logic *relocation*, not logic change — same fields, same casts, same null handling. The model otherwise stays mutable; immutability comes with the Hive-adapter spec.
- **Box-name constants move to the repository.** `DbHelper.notesBoxName` (`'notes_v2'`) becomes a private constant inside `HiveNotesRepository`. `DbHelper` itself stays in `lib/helpers/database_helper.dart` for now (other consumers — settings, user — still use it); it's emptied of note-specific knowledge.
- **Existing public Provider API of `Notes` is preserved bit-for-bit.** Screens that consume `context.read<Notes>()` keep working. Method signatures, return types, and `notifyListeners()` calls stay identical. The only change is that mutation methods now end with `await _repository.save(...)` instead of `await DbHelper.insertUpdateData(...)`.

## Implementation

### A. Add `NotesRepository` (abstract)

Path: `lib/repositories/notes/notes_repository.dart`

```dart
import 'package:noti_notes_app/models/note.dart';

/// Contract for note persistence. Concrete implementations may target
/// Hive (current), in-memory (tests), or a future on-device store.
abstract class NotesRepository {
  /// Initialize backing storage. Must be called before any other method.
  /// Idempotent — multiple calls are safe.
  Future<void> init();

  /// Returns all notes currently persisted, decoded into domain models.
  Future<List<Note>> getAll();

  /// Returns a stream that emits the full list whenever it changes.
  /// First emission is the current snapshot. Subsequent emissions fire on
  /// every put/delete/clear via Hive's `box.watch()`.
  /// Caller is responsible for cancelling the subscription.
  Stream<List<Note>> watchAll();

  /// Persists a note. Overwrites if an entry with the same id exists.
  Future<void> save(Note note);

  /// Persists multiple notes in sequence. No transactional guarantees.
  Future<void> saveAll(Iterable<Note> notes);

  /// Deletes a note by id and any on-disk image associated with it.
  /// Notification cancellation is the caller's responsibility.
  Future<void> delete(String id);

  /// Deletes multiple notes (and their images) by id.
  Future<void> deleteAll(Iterable<String> ids);

  /// Wipes every persisted note and every on-disk image in one shot.
  /// Used by settings → "clear all data".
  Future<void> clear();
}
```

### B. Add `HiveNotesRepository` (concrete)

Path: `lib/repositories/notes/hive_notes_repository.dart`

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';

/// Hive-backed implementation of [NotesRepository]. Continues to store each
/// note as a JSON-encoded string keyed by note id (legacy v2 format).
/// Migration to typed Hive CE adapters lands in Spec 04b.
class HiveNotesRepository implements NotesRepository {
  HiveNotesRepository({ImagePickerService? imageService})
      : _imageService = imageService ?? const ImagePickerService();

  static const String _boxName = 'notes_v2';

  final ImagePickerService _imageService;
  Box<dynamic>? _box;

  @override
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Box<dynamic> get _openBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('HiveNotesRepository.init() was not called.');
    }
    return box;
  }

  @override
  Future<List<Note>> getAll() async {
    return _openBox.values
        .cast<String>()
        .map((s) => Note.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Stream<List<Note>> watchAll() async* {
    yield await getAll();
    await for (final _ in _openBox.watch()) {
      yield await getAll();
    }
  }

  @override
  Future<void> save(Note note) async {
    if (note.id.isEmpty) return;
    await _openBox.put(note.id, jsonEncode(note.toJson()));
  }

  @override
  Future<void> saveAll(Iterable<Note> notes) async {
    for (final n in notes) {
      await save(n);
    }
  }

  @override
  Future<void> delete(String id) async {
    final raw = _openBox.get(id);
    if (raw is String) {
      final note = Note.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final image = note.imageFile;
      if (image != null) {
        await _imageService.removeImage(image);
      }
    }
    await _openBox.delete(id);
  }

  @override
  Future<void> deleteAll(Iterable<String> ids) async {
    for (final id in ids) {
      await delete(id);
    }
  }

  @override
  Future<void> clear() async {
    final notes = await getAll();
    for (final n in notes) {
      final image = n.imageFile;
      if (image != null) {
        await _imageService.removeImage(image);
      }
    }
    await _openBox.clear();
  }
}
```

### C. Add `Note.fromJson(...)` factory

Path: `lib/models/note.dart` (add factory; do not change existing fields or `toJson`)

```dart
// Add inside the Note class, alongside the existing constructor + toJson.

factory Note.fromJson(Map<String, dynamic> json) {
  return Note(
    (json['tags'] as List).cast<String>().toSet(),
    json['imageFile'] != null ? File(json['imageFile'] as String) : null,
    json['patternImage'] as String?,
    (json['todoList'] as List).cast<Map<String, dynamic>>(),
    (json['reminder'] as String).isNotEmpty
        ? DateTime.parse(json['reminder'] as String)
        : null,
    json['gradient'] != null && json['gradient'] != ''
        ? LinearGradient(
            colors: [
              Color((json['gradient']['colors'] as List)[0] as int),
              Color((json['gradient']['colors'] as List)[1] as int),
            ],
            begin: toAlignment((json['gradient']['alignment'] as List)[0] as String),
            end: toAlignment((json['gradient']['alignment'] as List)[1] as String),
          )
        : null,
    id: json['id'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    dateCreated: DateTime.parse(json['dateCreated'] as String),
    colorBackground: Color(json['colorBackground'] as int),
    fontColor: Color(json['fontColor'] as int),
    displayMode: DisplayMode.values[json['displayMode'] as int],
    hasGradient: json['hasGradient'] as bool,
    isPinned: (json['isPinned'] as bool?) ?? false,
    sortIndex: json['sortIndex'] as int?,
    blocks: json['blocks'] != null
        ? (json['blocks'] as List)
            .cast<Map<dynamic, dynamic>>()
            .map((m) => m.cast<String, dynamic>())
            .toList()
        : null,
  );
}
```

> The decoding logic is **identical** to the inline block currently in `Notes._loadNotesFromDataBase`. Only the location moves. `import 'package:noti_notes_app/helpers/alignment.dart'` is added to `note.dart` for `toAlignment(...)`.

### D. Refactor `lib/features/home/legacy/notes_provider.dart`

The provider's public API is preserved exactly — same method names, same return types, same `notifyListeners()` calls. Internally:

- Constructor takes a `required NotesRepository repository` parameter.
- Remove every `import` of `database_helper.dart`, `dart:convert`, `dart:io`, and `photo_picker.dart` (now flowing through the repo).
- `loadNotesFromDataBase()` becomes:
  ```dart
  Future<void> loadNotesFromDataBase() async {
    _notes
      ..clear()
      ..addAll(await _repository.getAll());
    notifyListeners();
  }
  ```
- Every call to `DbHelper.insertUpdateData(...)` becomes `_repository.save(note)`.
- Every call to `DbHelper.deleteData(notesBoxName, id)` becomes `_repository.delete(id)`.
- `clearBox()` becomes `_repository.clear()`.
- `removeSelectedNotes(Set<String> ids)` and `deleteNote(String id)`:
  - Remove `PhotoPicker.removeImage(...)` calls (now done inside `_repository.delete(...)`).
  - **Keep** `LocalNotificationService.cancelNotification(...)` calls (deferred).
  - Replace data calls with repo calls.

The `Notes` provider remains a `ChangeNotifier`; it's still injected via `package:provider`. The class name and the file location do not change.

### E. Update `lib/main.dart`

The provider tree gains the repository before the notes provider so the Notes ChangeNotifier can read it. Concrete shape:

```dart
final notesRepository = HiveNotesRepository();
await notesRepository.init();

runApp(
  MultiProvider(
    providers: [
      Provider<NotesRepository>.value(value: notesRepository),
      ChangeNotifierProvider(
        create: (ctx) => Notes(repository: ctx.read<NotesRepository>())
          ..loadNotesFromDataBase(),
      ),
      // ...other existing providers (theme, user_data, search) untouched
    ],
    child: const NotiApp(),
  ),
);
```

> If `main.dart` currently calls `DbHelper.initBox(DbHelper.notesBoxName)` directly, replace it with `await notesRepository.init();`. Other `DbHelper.initBox(...)` calls for `userBoxName` and `settingsBoxName` stay until their respective repos land.

### F. Update [`context/architecture.md`](../context/architecture.md)

Augment the Section-F tree from Spec 03 to include `lib/repositories/` as a cross-cutting root, and add a clarifying rule:

```
lib/
├── main.dart
├── app/
├── features/<feature>/
│   ├── bloc/
│   ├── repository/             ← feature-private data, only this feature reads/writes
│   ├── widgets/
│   ├── screen.dart
│   └── legacy/
├── repositories/<resource>/    ← cross-cutting domain data (Note, Tag, Theme, NotiIdentity, …)
├── services/
├── models/
├── theme/
├── helpers/
├── widgets/
└── assets/
```

Add to the prose:

> A **cross-cutting repository** (under `lib/repositories/<resource>/`) owns a domain resource that is consumed by two or more features (e.g. `Note` is read by home, note_editor, search, and the future share flow). A **feature-private repository** (under `lib/features/<feature>/repository/`) is consumed only by its parent feature. When in doubt, start feature-private and promote to cross-cutting if a second feature needs to read it.

Update the "Data flow examples" section's first example ("Save a text note") to reflect the new path: `NoteEditorScreen` → BLoC (Spec 05) → `NotesRepository.save(note)` → `HiveNotesRepository` writes to `notes_v2` box → emits stream event.

### G. Update [`context/code-standards.md`](../context/code-standards.md)

Replace the existing "Repository layer" subsection with:

```markdown
## Repository layer

- Cross-cutting domain repositories live at `lib/repositories/<resource>/`. Feature-private repositories live at `lib/features/<feature>/repository/`. When a second feature needs to read a feature-private resource, promote it to cross-cutting.
- Each repository is an abstract class; concrete implementations are siblings (e.g. `notes_repository.dart` + `hive_notes_repository.dart`).
- Methods return immutable models and primitives — never raw Hive objects, raw `Map`s, or `Box` references.
- Future API for one-shot operations (`getAll`, `save`, `delete`); Stream API (`watchAll`) for collection observation. Streams are driven by `box.watch()`, emit the full snapshot on each change, and must close cleanly when no listener remains.
- Repositories own ALL native side effects of their resource (Hive writes, file deletes, future P2P send). They DO NOT own user-facing notifications, telemetry, or BLoC orchestration.
- Tests for repositories use a real Hive box opened against a temp dir (no mocking Hive). Mocking happens at the `NotesRepository` interface in BLoC tests.
```

### H. Update [`context/progress-tracker.md`](../context/progress-tracker.md)

- Mark Spec 04 complete in **Completed**.
- Add to **Architecture decisions**:
  ```markdown
  12. **Cross-cutting repositories at `lib/repositories/<resource>/`** when a domain resource is consumed by 2+ features (e.g. notes). Feature-private repos stay under `lib/features/<feature>/repository/`. JSON-string-in-Hive storage retained until Spec 04b.
  ```
- If the legacy provider couldn't be cleanly decoupled in any place, log the residual coupling under **Open questions**.

## Success Criteria

- [ ] `lib/repositories/notes/notes_repository.dart` and `lib/repositories/notes/hive_notes_repository.dart` exist and match Sections A and B.
- [ ] `Note.fromJson(...)` factory exists in `lib/models/note.dart` and matches the decoder logic from the original `Notes._loadNotesFromDataBase` byte-for-byte (no field added, removed, or re-typed).
- [ ] `lib/features/home/legacy/notes_provider.dart` no longer imports `database_helper.dart`, `dart:convert`, `dart:io`, or `photo_picker.dart`. Its public method signatures and return types are unchanged.
- [ ] `lib/main.dart` provides a `NotesRepository` to the widget tree before `Notes`. The Notes provider receives it via constructor.
- [ ] `flutter analyze` exits 0.
- [ ] `bash scripts/check-offline.sh` exits 0.
- [ ] `dart format --set-exit-if-changed -l 100 lib/ test/` exits 0.
- [ ] `flutter test` exits 0. New: at least one repository-level integration test in `test/repositories/notes/hive_notes_repository_test.dart` that opens a temp Hive box, persists a note, reads it back, deletes it, asserts the box is empty.
- [ ] `flutter run` boots the app on iOS simulator and Android emulator. Manual smoke (post-Spec-3 paths): create a note → save → app restart → note still listed; delete a note → image file gone from app docs dir; clear-all → no notes after restart.
- [ ] No screen, widget, or BLoC under `lib/features/` imports `package:hive_ce_flutter/hive_flutter.dart`. Verify with `grep -RnE "package:hive" lib/features` — must be empty.
- [ ] `LocalNotificationService.cancelNotification(...)` calls remain in the legacy provider (intentional, per design decision).
- [ ] [`context/architecture.md`](../context/architecture.md), [`context/code-standards.md`](../context/code-standards.md), and [`context/progress-tracker.md`](../context/progress-tracker.md) updated per Sections F, G, H.
- [ ] `pubspec.yaml` is unchanged (no new dependencies).
- [ ] No invariant in [`context/architecture.md`](../context/architecture.md) is changed.

## References

- [`context/architecture.md`](../context/architecture.md) — invariants 5 (Hive only via repositories) and 7 (blobs on disk)
- [`context/code-standards.md`](../context/code-standards.md) — Repository layer (rewritten by this spec)
- [`context/ai-workflow-rules.md`](../context/ai-workflow-rules.md) — verification commands
- [03-project-structure-migration](03-project-structure-migration.md) — provides the `lib/features/<feature>/legacy/` paths the provider uses
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md) — repository-pattern guidance
- Skill: [`dart-add-unit-test`](../.agents/skills/dart-add-unit-test/SKILL.md) — repo-level test scaffolding
- Skill: [`dart-flutter-patterns`](../.agents/skills/dart-flutter-patterns/SKILL.md) — abstract class + DI conventions
- Agent: `flutter-expert` — invoke after the legacy provider refactor to audit signature preservation
- Agent: `code-reviewer` — invoke pre-commit to catch any accidental behavior change
- Follow-up spec: `04b-hive-adapters.md` — typed Hive CE adapters + immutable Note + JSON-to-adapter migration
