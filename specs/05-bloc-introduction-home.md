# 05 — bloc-introduction-home

## Goal

Introduce `flutter_bloc` to the codebase and migrate the **home (notes-list)** feature end-to-end as the canonical template for all subsequent BLoC migrations. After this spec, `lib/features/home/screen.dart` reads its state from a new `NotesListBloc`, the home-list responsibilities (load, filter, sort, edit mode, multi-select, bulk delete, pin toggle) are fully owned by the BLoC, and the legacy `Notes` ChangeNotifier retains only the editor-side mutations consumed by `note_editor`, `note_drop`, and `search`. The patterns established here — file layout, event/state shape, repository injection via `RepositoryProvider`, bloc test scaffolding — are what Specs 06–07 follow when migrating the rest.

## Dependencies

- [01-lint-and-format-hardening](01-lint-and-format-hardening.md), [02-offline-invariant-ci-gate](02-offline-invariant-ci-gate.md) — analyzer + offline gate baseline.
- [03-project-structure-migration](03-project-structure-migration.md) — collocated layout; the BLoC files land at `lib/features/home/bloc/`.
- [04-repository-layer](04-repository-layer.md) — `NotesRepository` (abstract) and `HiveNotesRepository` (concrete) exist; the BLoC subscribes to `repository.watchAll()` and calls `repository.delete(id)`. Spec 05 does **not** modify the repository.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — BLoC layering, `RepositoryProvider` injection, `emit.forEach` for stream-driven state.
- `dart-flutter-patterns` — Equatable state, sealed events, async cancellation in `close()`.
- `dart-add-unit-test` — `bloc_test` scaffolding against a `Fake<Resource>Repository`.

**After-coding agents:**
- `flutter-expert` — audit `BlocBuilder` placement in the home tree, confirm `context.read` vs `context.watch` choices, verify the `@Deprecated` annotations don't break unrelated call sites.
- `test-automator` — review bloc-test coverage; ensure each of the 8 events has at least one expectation.
- `code-reviewer` — visual + behavioral parity with the legacy home implementation.

## Design Decisions

- **Bloc, not Cubit, for `NotesListBloc`.** Per the user's directive (Bloc by default; Cubit only for trivial cases), and because the home feature has 7 discrete user actions (load, filter, sort, toggle edit mode, toggle selection, delete selected, toggle pin) plus an external trigger (repository emits a new list). Discrete events make replay/inspection trivial in test.
- **State class extends `Equatable`.** No `freezed` yet. If a later migration introduces union types we'll evaluate freezed; the home state is a single record-shaped class.
- **`RepositoryProvider` replaces the plain `Provider<NotesRepository>` from Spec 04.** `RepositoryProvider` ships with `flutter_bloc` and is the idiomatic way to expose repositories to the widget tree. The legacy `Notes` ChangeNotifier still lives under a `ChangeNotifierProvider` (untouched in this spec) until Specs 06–07 migrate its remaining consumers.
- **The legacy `Notes` provider keeps its public surface but loses its home-list ownership.** Methods called only from `home/screen.dart` (`activateEditMode`, `deactivateEditMode`, `removeSelectedNotes`, `sortByDateCreated`, `togglePin`, `filterByTag`, `getMostUsedTags`, `notesToDelete`, `editMode`) are **deprecated** with `@Deprecated('migrated to NotesListBloc; remove in Spec 08')` annotations and forward to the BLoC's event bus where reasonable, otherwise become no-ops with a debug log. Their bodies do not change yet — the BLoC implements the canonical version, the legacy methods are markers for the cleanup spec.
- **`Notes._notes` in-memory list stays the source of truth for the editor + search.** The BLoC subscribes to the repository's `watchAll()` stream — it does NOT read from the legacy provider. Both layers stay consistent because mutations go through the repo (per Spec 04). The BLoC ignores `notifyListeners()`; the provider ignores `BlocProvider`.
- **Notification cancellation moves into the BLoC's delete handler.** When `_NotesListBloc` handles `SelectedNotesDeleted`, it iterates the ids, calls `LocalNotificationService.cancelNotification(index)` for each (preserving the index-based API), and then calls `repository.deleteAll(ids)`. The legacy provider's `removeSelectedNotes` still calls `cancelNotification` if invoked elsewhere — leave that path alone in this spec; Specs 06–07 will retire those call sites.
- **No new behavior. No new UI.** The home screen looks and behaves identically to before the migration. This is a state-management refactor, full stop. Filter chips, sort order, multi-select, swipe-to-delete, pin pinning, empty state — all unchanged.
- **Tests use `bloc_test` against a fake repository.** A `FakeNotesRepository` that controls the `watchAll()` stream and records `delete*` / `save*` calls is added at `test/repositories/notes/fake_notes_repository.dart`. The BLoC test verifies state transitions for each event. No real Hive in this spec's tests.
- **Search query is NOT moved into this BLoC.** Title search lives in the `search` legacy provider; it'll be folded into a `SearchBloc` in Spec 06 or 07 (the spec that migrates `search`). The home screen's BLoC handles tag filter + sort + edit mode + bulk delete + pin only.
- **`bloc_observer` for dev-only logging.** A `LoggingBlocObserver` is added under `lib/app/` and registered in `main.dart` *only* when `kDebugMode`. Production builds get no observer; no logs leave the device (offline invariant 1).

## Implementation

### A. `pubspec.yaml` additions

Append to `dependencies:` (runtime):

```yaml
  flutter_bloc: ^9.1.1
  bloc: ^9.0.0
  equatable: ^2.0.7
```

Append to `dev_dependencies:` (test):

```yaml
  bloc_test: ^10.0.0
  mocktail: ^1.0.4
```

> No removals. `package:provider` stays — Specs 06–07 retire it.

### B. `lib/features/home/bloc/notes_list_state.dart`

```dart
import 'package:equatable/equatable.dart';
import 'package:noti_notes_app/models/note.dart';

enum NotesListStatus { initial, loading, ready, failure }

enum NotesSort { dateCreatedDesc, dateCreatedAsc }

class NotesListState extends Equatable {
  const NotesListState({
    this.status = NotesListStatus.initial,
    this.notes = const [],
    this.activeTagFilter = const {},
    this.sort = NotesSort.dateCreatedDesc,
    this.isEditMode = false,
    this.selectedIds = const {},
    this.errorMessage,
  });

  final NotesListStatus status;
  final List<Note> notes;
  final Set<String> activeTagFilter;
  final NotesSort sort;
  final bool isEditMode;
  final Set<String> selectedIds;
  final String? errorMessage;

  /// Notes after applying the active tag filter and sort. Pin order is
  /// applied here so the screen renders pinned-first by default.
  List<Note> get visibleNotes {
    var list = activeTagFilter.isEmpty
        ? notes
        : notes
            .where((n) => n.tags.intersection(activeTagFilter).isNotEmpty)
            .toList(growable: false);
    list = [...list];
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return switch (sort) {
        NotesSort.dateCreatedDesc => b.dateCreated.compareTo(a.dateCreated),
        NotesSort.dateCreatedAsc => a.dateCreated.compareTo(b.dateCreated),
      };
    });
    return list;
  }

  /// Top-N tags across the loaded set, sorted by frequency. Drives the
  /// filter chips row on the home screen.
  Set<String> get mostUsedTags {
    final counts = <String, int>{};
    for (final n in notes) {
      for (final t in n.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toSet();
  }

  NotesListState copyWith({
    NotesListStatus? status,
    List<Note>? notes,
    Set<String>? activeTagFilter,
    NotesSort? sort,
    bool? isEditMode,
    Set<String>? selectedIds,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotesListState(
      status: status ?? this.status,
      notes: notes ?? this.notes,
      activeTagFilter: activeTagFilter ?? this.activeTagFilter,
      sort: sort ?? this.sort,
      isEditMode: isEditMode ?? this.isEditMode,
      selectedIds: selectedIds ?? this.selectedIds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        notes,
        activeTagFilter,
        sort,
        isEditMode,
        selectedIds,
        errorMessage,
      ];
}
```

### C. `lib/features/home/bloc/notes_list_event.dart`

```dart
import 'package:equatable/equatable.dart';

import 'notes_list_state.dart';

sealed class NotesListEvent extends Equatable {
  const NotesListEvent();

  @override
  List<Object?> get props => const [];
}

/// Subscribes to the repository's `watchAll()` stream. Fired once on
/// BLoC creation; the subscription stays open for the BLoC's lifetime.
final class NotesListSubscribed extends NotesListEvent {
  const NotesListSubscribed();
}

/// Internal event dispatched by the stream subscription. NOT fired by the UI.
final class _NotesUpdated extends NotesListEvent {
  const _NotesUpdated(this.notes);
  final List notes;
  @override
  List<Object?> get props => [notes];
}

/// User toggled a tag chip on the filter row.
final class TagFilterToggled extends NotesListEvent {
  const TagFilterToggled(this.tag);
  final String tag;
  @override
  List<Object?> get props => [tag];
}

final class SortChanged extends NotesListEvent {
  const SortChanged(this.sort);
  final NotesSort sort;
  @override
  List<Object?> get props => [sort];
}

final class EditModeToggled extends NotesListEvent {
  const EditModeToggled();
}

final class NoteSelectionToggled extends NotesListEvent {
  const NoteSelectionToggled(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final class SelectedNotesDeleted extends NotesListEvent {
  const SelectedNotesDeleted();
}

final class PinToggled extends NotesListEvent {
  const PinToggled(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}
```

> Note: `_NotesUpdated` is library-private (no `library` directive needed since it's in the same file as the BLoC's `part of` consumer below; alternatively, define it inside the BLoC file directly to keep it private. The spec uses the same-file approach: move the event class into `notes_list_bloc.dart` if Dart's privacy rules complain.)

### D. `lib/features/home/bloc/notes_list_bloc.dart`

```dart
import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';

import 'notes_list_event.dart';
import 'notes_list_state.dart';

class NotesListBloc extends Bloc<NotesListEvent, NotesListState> {
  NotesListBloc({required NotesRepository repository})
      : _repository = repository,
        super(const NotesListState()) {
    on<NotesListSubscribed>(_onSubscribed);
    on<TagFilterToggled>(_onTagFilterToggled);
    on<SortChanged>(_onSortChanged);
    on<EditModeToggled>(_onEditModeToggled);
    on<NoteSelectionToggled>(_onNoteSelectionToggled);
    on<SelectedNotesDeleted>(_onSelectedNotesDeleted);
    on<PinToggled>(_onPinToggled);
  }

  final NotesRepository _repository;
  StreamSubscription<List<Note>>? _subscription;

  Future<void> _onSubscribed(
    NotesListSubscribed event,
    Emitter<NotesListState> emit,
  ) async {
    emit(state.copyWith(status: NotesListStatus.loading));
    await _subscription?.cancel();
    _subscription = _repository.watchAll().listen(
      (notes) {
        // Internal stream-fed update. Re-add via add() so the on<...>
        // handler is awaited cleanly in tests via emit.forEach pattern.
        // For brevity here we update directly.
        if (isClosed) return;
        // Re-emit by piping through an internal event so transformer
        // ordering is consistent. See _NotesUpdated handler below.
      },
      onError: (Object error, StackTrace stack) {
        if (isClosed) return;
        // Surface; production builds: no log shipping (offline invariant).
      },
    );
    // Bridge stream to event using emit.forEach so cancellation tracks state.
    await emit.forEach<List<Note>>(
      _repository.watchAll(),
      onData: (notes) => state.copyWith(
        status: NotesListStatus.ready,
        notes: notes,
        clearError: true,
      ),
      onError: (error, stack) => state.copyWith(
        status: NotesListStatus.failure,
        errorMessage: error.toString(),
      ),
    );
  }

  void _onTagFilterToggled(
    TagFilterToggled event,
    Emitter<NotesListState> emit,
  ) {
    final next = {...state.activeTagFilter};
    if (next.contains(event.tag)) {
      next.remove(event.tag);
    } else {
      next.add(event.tag);
    }
    emit(state.copyWith(activeTagFilter: next));
  }

  void _onSortChanged(SortChanged event, Emitter<NotesListState> emit) {
    emit(state.copyWith(sort: event.sort));
  }

  void _onEditModeToggled(
    EditModeToggled event,
    Emitter<NotesListState> emit,
  ) {
    final entering = !state.isEditMode;
    emit(state.copyWith(
      isEditMode: entering,
      selectedIds: entering ? state.selectedIds : const {},
    ));
  }

  void _onNoteSelectionToggled(
    NoteSelectionToggled event,
    Emitter<NotesListState> emit,
  ) {
    if (!state.isEditMode) return;
    final next = {...state.selectedIds};
    if (next.contains(event.id)) {
      next.remove(event.id);
    } else {
      next.add(event.id);
    }
    emit(state.copyWith(selectedIds: next));
  }

  Future<void> _onSelectedNotesDeleted(
    SelectedNotesDeleted event,
    Emitter<NotesListState> emit,
  ) async {
    final ids = state.selectedIds;
    if (ids.isEmpty) return;
    // Cancel notifications first (preserves legacy behavior); index-based.
    for (final id in ids) {
      final index = state.notes.indexWhere((n) => n.id == id);
      if (index >= 0) {
        await LocalNotificationService.cancelNotification(index);
      }
    }
    await _repository.deleteAll(ids);
    emit(state.copyWith(
      isEditMode: false,
      selectedIds: const {},
    ));
  }

  Future<void> _onPinToggled(
    PinToggled event,
    Emitter<NotesListState> emit,
  ) async {
    final note = state.notes.firstWhere(
      (n) => n.id == event.id,
      orElse: () => throw StateError('Note ${event.id} not in current state'),
    );
    note.isPinned = !note.isPinned;
    await _repository.save(note);
    // No emit needed — repo stream re-emits with the updated list.
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
```

> Note: the `_onSubscribed` handler uses `emit.forEach` to bridge the repository stream into BLoC state. This is the standard pattern recommended in `flutter_bloc` 9.x. Drop the duplicated `_subscription = ...listen(...)` block above `emit.forEach` — that's an artifact left in for clarity; the spec implementer should remove it. (Implementer: keep ONLY the `emit.forEach` block.)
>
> The `PinToggled` handler mutates `note.isPinned` directly because `Note` is currently mutable (Spec 04b will introduce immutability + `copyWith`). Once 04b lands, this handler becomes `await _repository.save(note.copyWith(isPinned: !note.isPinned))`.

### E. `lib/app/logging_bloc_observer.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:bloc/bloc.dart';

/// Dev-only observer. Registered in main.dart inside `if (kDebugMode)`.
/// Emits debugPrint output ONLY; never ships anywhere off-device.
class LoggingBlocObserver extends BlocObserver {
  @override
  void onTransition(Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    super.onTransition(bloc, transition);
    if (kDebugMode) {
      debugPrint('[bloc] ${bloc.runtimeType}: ${transition.event.runtimeType} -> ${transition.nextState.runtimeType}');
    }
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    if (kDebugMode) {
      debugPrint('[bloc] ${bloc.runtimeType} error: $error');
    }
  }
}
```

### F. `lib/main.dart` updates

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/logging_bloc_observer.dart';
import 'features/home/bloc/notes_list_bloc.dart';
import 'features/home/bloc/notes_list_event.dart';
// ...existing imports

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    Bloc.observer = LoggingBlocObserver();
  }

  final notesRepository = HiveNotesRepository();
  await notesRepository.init();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<NotesRepository>.value(value: notesRepository),
      ],
      child: MultiProvider(
        providers: [
          // Legacy ChangeNotifier providers stay until Specs 06–07.
          ChangeNotifierProvider(
            create: (ctx) => Notes(repository: ctx.read<NotesRepository>())
              ..loadNotesFromDataBase(),
          ),
          // ...other legacy providers (theme, user_data, search) untouched
        ],
        child: BlocProvider(
          create: (ctx) => NotesListBloc(
            repository: ctx.read<NotesRepository>(),
          )..add(const NotesListSubscribed()),
          child: const NotiApp(),
        ),
      ),
    ),
  );
}
```

> The `BlocProvider` is mounted at the app root for now because `HomeScreen` is the entry route. When routing is introduced (later spec), the BLoC should be scoped to the home route only.

### G. `lib/features/home/screen.dart` rewrite

The home screen's data reads switch from `Provider.of<Notes>(context)` to `BlocBuilder<NotesListBloc, NotesListState>`. Mutation calls switch from `notes.activateEditMode()` etc. to `context.read<NotesListBloc>().add(const EditModeToggled())`.

Concrete swap table for the implementer (every call site in `home/screen.dart` and its children under `home/widgets/`):

| Legacy call | New call |
|-------------|----------|
| `notes.notes` | `state.visibleNotes` (inside a BlocBuilder) |
| `notes.activateEditMode()` | `bloc.add(const EditModeToggled())` |
| `notes.deactivateEditMode()` | `bloc.add(const EditModeToggled())` |
| `notes.editMode` | `state.isEditMode` |
| `notes.notesToDelete.add(id)` | `bloc.add(NoteSelectionToggled(id))` |
| `notes.notesToDelete.remove(id)` | `bloc.add(NoteSelectionToggled(id))` |
| `notes.removeSelectedNotes(ids)` | `bloc.add(const SelectedNotesDeleted())` |
| `notes.sortByDateCreated()` | `bloc.add(const SortChanged(NotesSort.dateCreatedDesc))` |
| `notes.togglePin(id)` | `bloc.add(PinToggled(id))` |
| `notes.filterByTag(tags)` | use `state.visibleNotes` (filter is in state) |
| `notes.getMostUsedTags()` | `state.mostUsedTags` |

The widgets under `lib/features/home/widgets/` (`note_card.dart`, `filter_chips_row.dart`, `home_app_bar.dart`, `expandable_fab.dart`, `empty_state.dart`, `section_header.dart`, `long_press_menu_sheet.dart`) are updated in-place to consume the BLoC instead of the provider. **No visual change.**

### H. Mark legacy provider methods as deprecated

In `lib/features/home/legacy/notes_provider.dart`, annotate the eight migrated methods:

```dart
@Deprecated('migrated to NotesListBloc; remove in Spec 08')
void activateEditMode() { /* unchanged body */ }

@Deprecated('migrated to NotesListBloc; remove in Spec 08')
void deactivateEditMode() { /* unchanged body */ }

@Deprecated('migrated to NotesListBloc; remove in Spec 08')
Future<void> removeSelectedNotes(Set<String> ids) async { /* unchanged */ }

@Deprecated('migrated to NotesListBloc; remove in Spec 08')
void sortByDateCreated() { /* unchanged */ }

@Deprecated('migrated to NotesListBloc; remove in Spec 08')
void togglePin(String id) { /* unchanged */ }

@Deprecated('migrated to NotesListBloc; remove in Spec 08')
List<Note> filterByTag(Set<String> tags) { /* unchanged */ }

@Deprecated('migrated to NotesListBloc; remove in Spec 08')
Set<String> getMostUsedTags() { /* unchanged */ }
```

The bodies are not changed in this spec — note_editor / search may still call them. Spec 08 deletes the bodies once those features migrate.

### I. Tests

#### `test/repositories/notes/fake_notes_repository.dart`

A test double exposing a controllable `Stream<List<Note>>`:

```dart
import 'dart:async';

import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';

class FakeNotesRepository implements NotesRepository {
  final _controller = StreamController<List<Note>>.broadcast();
  List<Note> _store = [];

  void emit(List<Note> notes) {
    _store = notes;
    _controller.add(notes);
  }

  final List<String> deletedIds = [];
  final List<Note> savedNotes = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<Note>> getAll() async => _store;

  @override
  Stream<List<Note>> watchAll() async* {
    yield _store;
    yield* _controller.stream;
  }

  @override
  Future<void> save(Note note) async {
    savedNotes.add(note);
    _store = [..._store.where((n) => n.id != note.id), note];
    _controller.add(_store);
  }

  @override
  Future<void> saveAll(Iterable<Note> notes) async {
    for (final n in notes) {
      await save(n);
    }
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    _store = _store.where((n) => n.id != id).toList();
    _controller.add(_store);
  }

  @override
  Future<void> deleteAll(Iterable<String> ids) async {
    for (final id in ids) {
      await delete(id);
    }
  }

  @override
  Future<void> clear() async {
    _store = const [];
    _controller.add(const []);
  }

  Future<void> dispose() async => _controller.close();
}
```

#### `test/features/home/bloc/notes_list_bloc_test.dart`

Use `bloc_test` to verify each event:

- `NotesListSubscribed` → emits `loading` → `ready` with notes.
- `TagFilterToggled('work')` → adds 'work' to `activeTagFilter`; toggling again removes it.
- `SortChanged(NotesSort.dateCreatedAsc)` → emits with new sort.
- `EditModeToggled` → toggles `isEditMode`; toggling off clears `selectedIds`.
- `NoteSelectionToggled(id)` while NOT in edit mode → no state change.
- `NoteSelectionToggled(id)` while in edit mode → adds/removes id.
- `SelectedNotesDeleted` → calls `repository.deleteAll(...)` with selected ids; clears `isEditMode` and `selectedIds`.
- `PinToggled(id)` → calls `repository.save(note)` with toggled `isPinned`.

Each test sets up the fake, instantiates the BLoC, drains a frame, and asserts via `bloc_test`'s `expect:` clause. Sample:

```dart
blocTest<NotesListBloc, NotesListState>(
  'emits loading then ready when subscribed',
  build: () {
    fake.emit([_buildNote(id: 'a'), _buildNote(id: 'b')]);
    return NotesListBloc(repository: fake);
  },
  act: (bloc) => bloc.add(const NotesListSubscribed()),
  expect: () => [
    isA<NotesListState>().having((s) => s.status, 'status', NotesListStatus.loading),
    isA<NotesListState>()
        .having((s) => s.status, 'status', NotesListStatus.ready)
        .having((s) => s.notes.length, 'notes.length', 2),
  ],
);
```

### J. Update [`context/architecture.md`](../context/architecture.md)

Add to **Data flow examples** a new block:

```markdown
### Load + render the home screen
`HomeScreen` mounts → `BlocProvider` creates `NotesListBloc` and dispatches `NotesListSubscribed` → BLoC subscribes to `repository.watchAll()` → `HiveNotesRepository` yields current snapshot → BLoC emits `ready` state → `BlocBuilder` rebuilds the staggered grid. Subsequent `repository.save(...)` / `repository.delete(...)` calls (from any feature) trigger re-emits via `box.watch()` → BLoC re-emits with the fresh list → grid rebuilds.
```

No invariant change.

### K. Update [`context/code-standards.md`](../context/code-standards.md)

Refine the "flutter_bloc usage" section with concrete defaults established by this spec:

```markdown
- Default to `Bloc` over `Cubit` when there are 3+ user-driven triggers; reserve `Cubit` for trivial state-only flows.
- State classes extend `Equatable`; introduce `freezed` only when union types appear.
- Stream-driven BLoCs use `emit.forEach` to bridge repository streams into state. Subscription cancellation lives in `close()`.
- `RepositoryProvider` (from `flutter_bloc`) is the canonical injection mechanism for repositories. Plain `Provider` is used only for legacy `ChangeNotifier` instances during the migration window.
- Tests use `bloc_test` against a `Fake<Resource>Repository` (not mocktail mocks). Fakes live at `test/repositories/<resource>/fake_<resource>_repository.dart`.
```

### L. Update [`context/progress-tracker.md`](../context/progress-tracker.md)

- Mark Spec 05 complete in **Completed**.
- Add to **Architecture decisions**:
  ```markdown
  13. **`flutter_bloc` introduced; `NotesListBloc` is the migration template.** Bloc-default-Cubit-for-trivial; Equatable for state; `RepositoryProvider` for repos; `emit.forEach` for stream-driven state; `bloc_test` + fake repos for tests. Specs 06–07 follow this template.
  ```
- Add to **Open questions**:
  ```markdown
  10. `NotificationsService` is currently static (`LocalNotificationService.cancelNotification`). Future spec should instance-ify it and inject via `RepositoryProvider` so BLoCs receive it as a dependency rather than calling a static.
  11. Index-based notification cancellation (`cancelNotification(index)`) is a leaky abstraction inherited from the legacy provider. The notifications spec should refactor to id-based.
  ```

## Success Criteria

- [ ] `pubspec.yaml` adds `flutter_bloc`, `bloc`, `equatable` to runtime deps and `bloc_test`, `mocktail` to dev deps. No removals.
- [ ] `lib/features/home/bloc/{notes_list_bloc.dart, notes_list_event.dart, notes_list_state.dart}` exist and match Sections B–D.
- [ ] `lib/app/logging_bloc_observer.dart` exists and matches Section E.
- [ ] `lib/main.dart` uses `MultiRepositoryProvider` and `BlocProvider` per Section F. The legacy `MultiProvider` block remains for the still-unmigrated providers.
- [ ] `lib/features/home/screen.dart` and every widget under `lib/features/home/widgets/` consume `NotesListBloc` via `BlocBuilder` / `context.read`. **No widget under `lib/features/home/` imports `package:provider`** (verify with `grep -RnE "package:provider" lib/features/home`).
- [ ] The eight migrated methods on `Notes` (legacy provider) are annotated `@Deprecated('migrated to NotesListBloc; remove in Spec 08')`. Their bodies are unchanged.
- [ ] `flutter analyze` exits 0. The `@Deprecated` annotations may surface `provide_deprecation_message` style hints — those are expected, not failures.
- [ ] `bash scripts/check-offline.sh` exits 0 (no new forbidden imports — `flutter_bloc` is local-state only).
- [ ] `dart format --set-exit-if-changed -l 100 lib/ test/` exits 0.
- [ ] `flutter test` exits 0. New tests:
  - `test/repositories/notes/fake_notes_repository.dart` (Section I)
  - `test/features/home/bloc/notes_list_bloc_test.dart` covers all 8 events listed in Section I, ≥ 1 expectation per event.
- [ ] `flutter run` boots iOS simulator + Android emulator. **Manual smoke (visual parity):** open app → home shows the same list as before → tap a tag chip filters → long-press a note enters edit mode → multi-select → trash icon deletes → swipe pin → restart → state persists.
- [ ] No screen, widget, or BLoC under `lib/features/` imports `package:hive_ce_flutter/hive_flutter.dart` (invariant 5 still holds).
- [ ] `LocalNotificationService.cancelNotification(...)` is called from the BLoC's `_onSelectedNotesDeleted` for each deleted id (parity with legacy behavior).
- [ ] `NotesListBloc.close()` cancels any open subscription. Verify with a test that closes the BLoC and asserts the fake's stream has no listeners.
- [ ] [`context/architecture.md`](../context/architecture.md), [`context/code-standards.md`](../context/code-standards.md), [`context/progress-tracker.md`](../context/progress-tracker.md) updated per Sections J, K, L.
- [ ] No invariant in [`context/architecture.md`](../context/architecture.md) is changed.
- [ ] No file under `lib/assets/` is touched.

## References

- [`context/architecture.md`](../context/architecture.md) — invariants 5 (repos own Hive), 6 (BLoCs no widgets), 8 (cancellation discipline)
- [`context/code-standards.md`](../context/code-standards.md) — flutter_bloc usage (refined by this spec)
- [`context/ai-workflow-rules.md`](../context/ai-workflow-rules.md) — verification commands
- [04-repository-layer](04-repository-layer.md) — `NotesRepository` contract this BLoC consumes
- Skill: [`flutter-managing-state`](../.agents/skills/dart-flutter-patterns/SKILL.md) — BLoC patterns (covered indirectly via `dart-flutter-patterns`; the official `flutter-managing-state` skill name does not currently exist in the registry, so we lean on `flutter-apply-architecture-best-practices` instead)
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Skill: [`dart-add-unit-test`](../.agents/skills/dart-add-unit-test/SKILL.md), [`dart-generate-test-mocks`](../.agents/skills/dart-generate-test-mocks/SKILL.md) — bloc_test scaffolding
- Agent: `flutter-expert` — invoke after the screen rewrite to audit `BlocBuilder` placement, `context.read` vs `context.watch` usage, missing `const`s
- Agent: `code-reviewer` — invoke pre-commit to confirm visual + behavioral parity with the legacy implementation
- Agent: `test-automator` — consult before adding more tests; the spec's 8-event coverage is the floor, not a ceiling
- Follow-ups: [06-bloc-migration-editor](06-bloc-migration-editor.md), [07-bloc-migration-search-and-settings](07-bloc-migration-search-and-settings.md), [08-provider-removal](08-provider-removal.md)
