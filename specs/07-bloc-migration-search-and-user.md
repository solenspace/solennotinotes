# 07 — bloc-migration-search-and-user

## Goal

Migrate the remaining two legacy ChangeNotifier providers to BLoC/Cubit:

1. **`SearchCubit`** — replaces `Search` (pure UI state: search type, query, tag filter, top-bar `NoteFilter`). Cubit because it's trivial state-only with no async work.
2. **`UserRepository` + `UserCubit`** — replaces `UserData`. The repository extracts Hive access for the user record (mirroring Spec 04's pattern); the cubit owns the active user, profile-picture mutations, and the randomized greeting.

After this spec, the `home`, `note_editor`, `search`, `settings`, and `user_info` features all consume BLoCs/Cubits. The legacy `Search` and `UserData` ChangeNotifiers are deleted in this spec (no deprecation window — they have no shared consumers with the migrated home/editor flows beyond their own screens). The legacy `Notes` provider remains as a husk waiting for **Spec 08** to delete it.

## Dependencies

- [04-repository-layer](04-repository-layer.md) — repository pattern; this spec adds `UserRepository`.
- [05-bloc-introduction-home](05-bloc-introduction-home.md) — BLoC template, RepositoryProvider, bloc_test, fakes.
- [06-bloc-migration-editor](06-bloc-migration-editor.md) — per-route Cubit/Bloc mounting pattern.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — Cubit-vs-Bloc decision, repository pattern.
- `dart-flutter-patterns` — single-record repository conventions.
- `dart-add-unit-test` — coverage for cubits and the new repo.

**After-coding agents:**
- `flutter-expert` — audit cubit lifecycle and `BlocProvider` scoping.
- `test-automator` — coverage on `SearchCubit` (6 methods), `UserCubit` (load + 4 setters + greeting).
- `code-reviewer` — verify the legacy `Search` and `UserData` deletions don't leave dangling references; settings + user_info screens read from the cubits cleanly.

## Design Decisions

- **`SearchCubit` over `SearchBloc`.** Six state-mutation methods, no async, no streams. Cubit fits the "trivial state-only" carve-out from `code-standards.md`.
- **Search state is global to the home route.** Same lifetime as `NotesListBloc`. Mounted alongside it via `MultiBlocProvider` at the home screen.
- **`SearchCubit` does NOT filter notes.** It owns query/tag-set/filter-mode state only. The home screen (or `NotesListBloc` via a `BlocListener<SearchCubit>`) reads the search state and applies it to `NotesListBloc`'s `visibleNotes`. **Decision**: the home screen wires it directly via combined `BlocBuilder`s and applies a final filter in widget code. Future spec can lift this into a `HomeFeedCubit` that depends on both; not in scope here.
- **`UserRepository` follows Spec 04's pattern**: abstract interface + `HiveUserRepository` concrete + `Future`-based getters + a single-record `watch()` stream. Box name stays `'user_v2'` (legacy compatibility); JSON-string storage retained until a future user-adapter spec.
- **`UserCubit` owns the greeting logic.** `randomGreetings()` is moved verbatim from the legacy provider. The list of greeting strings is unchanged; only the location moves. Future localization spec will move the strings to ARB.
- **`UserCubit` exposes `Stream<User>` via Bloc.stream.** Subscription lifetime equals the cubit's; no separate stream subscription. Editor and other features can `BlocBuilder` against it.
- **`User` model stays mutable for now.** Same reasoning as `Note` — immutability comes with the typed-adapter spec for that resource. Add a `User.fromJson` factory in this spec (parity with `Note.fromJson` from Spec 04).
- **Profile-picture file cleanup lives in `UserRepository.removePhoto()`.** Mirrors `NotesRepository.delete`'s image-cleanup pattern.
- **No deprecation window.** `Search` and `UserData` are deleted in this spec. Legacy consumers are migrated in the same diff — `home/screen.dart` (already consumes Search), `user_info/screen.dart`, and `settings/screen.dart` (which reads the username via UserData).

## Implementation

### A. Files to create

```
lib/repositories/user/
├── user_repository.dart
└── hive_user_repository.dart

lib/features/search/cubit/
├── search_cubit.dart
└── search_state.dart

lib/features/user_info/cubit/
├── user_cubit.dart
├── user_event.dart        ← only if this becomes a Bloc; for Cubit, omit
└── user_state.dart

test/repositories/user/
├── fake_user_repository.dart
└── hive_user_repository_test.dart

test/features/search/cubit/
└── search_cubit_test.dart

test/features/user_info/cubit/
└── user_cubit_test.dart
```

### Files to delete

```
lib/features/search/legacy/search_provider.dart
lib/features/user_info/legacy/user_data_provider.dart
```

(`Notes` legacy stays — Spec 08 deletes it.)

### B. `UserRepository` (abstract) + `HiveUserRepository` (concrete)

Mirrors `NotesRepository`. Single-record store keyed by `'userFromDevice'`.

`lib/repositories/user/user_repository.dart`:

```dart
import 'dart:io';

import 'package:noti_notes_app/models/user.dart';

abstract class UserRepository {
  Future<void> init();

  /// Returns the current user, or `null` if no user record exists yet.
  Future<User?> getCurrent();

  /// Emits the current user on subscription, then on every save.
  Stream<User?> watch();

  /// Persists the user. Overwrites any existing record.
  Future<void> save(User user);

  /// Replaces the profile picture file. Removes the previous file if any.
  Future<void> setPhoto(User user, File? newPhoto);

  /// Deletes the profile picture file and clears the field.
  Future<void> removePhoto(User user);
}
```

`lib/repositories/user/hive_user_repository.dart` — implementation analogous to `HiveNotesRepository`. Uses `'user_v2'` box name and the `'userFromDevice'` key. Exact code pattern matches Spec 04 Section B; the implementer translates field-by-field.

### C. `User.fromJson(...)` factory

Add to `lib/models/user.dart`. Factory mirrors the decode logic in `UserData.loadUserFromDataBase` (lines 109–129 of the legacy file). No field changes.

### D. `SearchCubit`

`lib/features/search/cubit/search_state.dart`:

```dart
import 'package:equatable/equatable.dart';

enum SearchType { notSearching, searchingByTitle, searchingByTag }

enum NoteFilter { all, reminders, checklists, images }

class SearchState extends Equatable {
  const SearchState({
    this.type = SearchType.notSearching,
    this.query = '',
    this.tags = const {},
    this.filter = NoteFilter.all,
  });

  final SearchType type;
  final String query;
  final Set<String> tags;
  final NoteFilter filter;

  SearchState copyWith({
    SearchType? type,
    String? query,
    Set<String>? tags,
    NoteFilter? filter,
  }) {
    return SearchState(
      type: type ?? this.type,
      query: query ?? this.query,
      tags: tags ?? this.tags,
      filter: filter ?? this.filter,
    );
  }

  @override
  List<Object?> get props => [type, query, tags, filter];
}
```

`lib/features/search/cubit/search_cubit.dart`:

```dart
import 'package:bloc/bloc.dart';

import 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  SearchCubit() : super(const SearchState());

  void activateByTitle() => emit(state.copyWith(type: SearchType.searchingByTitle));

  void activateByTag() => emit(state.copyWith(type: SearchType.searchingByTag));

  void deactivate() {
    emit(state.copyWith(
      type: SearchType.notSearching,
      query: '',
      tags: const {},
    ));
  }

  void setQuery(String q) => emit(state.copyWith(query: q));

  void setFilter(NoteFilter f) => emit(state.copyWith(filter: f));

  void addTag(String tag) {
    final next = {...state.tags, tag};
    emit(state.copyWith(tags: next, type: SearchType.searchingByTag));
  }

  void removeTag(String tag) {
    final next = {...state.tags}..remove(tag);
    emit(state.copyWith(
      tags: next,
      type: next.isEmpty ? SearchType.notSearching : SearchType.searchingByTag,
    ));
  }
}
```

### E. `UserCubit`

`lib/features/user_info/cubit/user_state.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:noti_notes_app/models/user.dart';

enum UserStatus { initial, loading, ready, error }

class UserState extends Equatable {
  const UserState({
    this.status = UserStatus.initial,
    this.user,
    this.greeting = 'Noti',
    this.errorMessage,
  });

  final UserStatus status;
  final User? user;
  final String greeting;
  final String? errorMessage;

  UserState copyWith({
    UserStatus? status,
    User? user,
    String? greeting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return UserState(
      status: status ?? this.status,
      user: user ?? this.user,
      greeting: greeting ?? this.greeting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, user, greeting, errorMessage];
}
```

`lib/features/user_info/cubit/user_cubit.dart`:

```dart
import 'dart:io';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:intl/intl.dart';
import 'package:noti_notes_app/models/user.dart';
import 'package:noti_notes_app/repositories/user/user_repository.dart';
import 'package:uuid/uuid.dart';

import 'user_state.dart';

class UserCubit extends Cubit<UserState> {
  UserCubit({required UserRepository repository})
      : _repository = repository,
        super(const UserState());

  final UserRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: UserStatus.loading));
    final user = await _repository.getCurrent() ??
        User(
          null,
          const Uuid().v4(),
          name: '',
          bornDate: DateTime.now(),
        );
    final greeting = _pickGreeting(user);
    emit(state.copyWith(
      status: UserStatus.ready,
      user: user,
      greeting: greeting,
    ));
  }

  Future<void> updateName(String name) async {
    final user = state.user;
    if (user == null) return;
    user.name = name;
    await _repository.save(user);
    emit(state.copyWith(user: user));
  }

  Future<void> updatePhoto(File? photo) async {
    final user = state.user;
    if (user == null) return;
    await _repository.setPhoto(user, photo);
    emit(state.copyWith(user: user));
  }

  Future<void> removePhoto() async {
    final user = state.user;
    if (user == null || user.profilePicture == null) return;
    await _repository.removePhoto(user);
    emit(state.copyWith(user: user));
  }

  String _pickGreeting(User user) {
    final hour = DateTime.now().hour;
    final timeOfDay = hour < 12 ? 'Morning' : (hour < 17 ? 'Afternoon' : 'Evening');
    final day = DateFormat('EEEE').format(DateTime.now());
    final name = user.name.isEmpty ? 'User' : user.name.toLowerCase();

    final pool = switch (day) {
      'Monday' => [
          'Another monday, ugh...',
          'Starting the week.',
          "Let's get things done.",
          "$name, you'll crush it.",
        ],
      'Tuesday' => [
          'Tuesday, not monday.',
          'Taco tuesday?',
          'today is... not monday!',
          '$name, feeling good?',
        ],
      _ => [
          'Good $timeOfDay',
          'Today is the day.',
          "$name, glad you're back.",
          "You're doing great.",
          'Good $timeOfDay $name',
          'Plans for the weekend?',
          '$name, did you shower?',
          "Tonight's the night.",
          'This is your notinotes.',
        ],
    };

    return pool[Random().nextInt(pool.length)];
  }
}
```

### F. Update `lib/main.dart`

Provider tree gains `UserRepository` (alongside the existing `NotesRepository`) and the two new BLoC providers replace the deleted ChangeNotifiers.

```dart
final notesRepository = HiveNotesRepository();
final userRepository = HiveUserRepository();
await notesRepository.init();
await userRepository.init();

runApp(
  MultiRepositoryProvider(
    providers: [
      RepositoryProvider<NotesRepository>.value(value: notesRepository),
      RepositoryProvider<UserRepository>.value(value: userRepository),
    ],
    child: MultiProvider(
      providers: [
        // The legacy Notes ChangeNotifier still lives until Spec 08.
        ChangeNotifierProvider(
          create: (ctx) => Notes(repository: ctx.read<NotesRepository>())
            ..loadNotesFromDataBase(),
        ),
        // theme provider unchanged for now (still ChangeNotifier; Spec 09 owns it)
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) => NotesListBloc(repository: ctx.read<NotesRepository>())
              ..add(const NotesListSubscribed()),
          ),
          BlocProvider(create: (_) => SearchCubit()),
          BlocProvider(
            create: (ctx) => UserCubit(repository: ctx.read<UserRepository>())..load(),
          ),
        ],
        child: const NotiApp(),
      ),
    ),
  ),
);
```

### G. Update consuming screens

- `lib/features/home/screen.dart`, `lib/features/home/widgets/*`: replace `Provider.of<Search>` with `context.watch<SearchCubit>()`. Replace `Provider.of<UserData>` (for greeting) with `context.watch<UserCubit>()` and read `state.greeting` / `state.user.name`. Filtered list logic combines `NotesListBloc` and `SearchCubit` via two `BlocBuilder`s nested or a `BlocSelector`.
- `lib/features/user_info/screen.dart`: replace all `Provider.of<UserData>` reads with `context.watch<UserCubit>()`. Mutation calls `notes.user...` → `cubit.updateName(...)`, `cubit.updatePhoto(...)`, `cubit.removePhoto()`.
- `lib/features/settings/screen.dart`: same replacements where it reads username/profile.

### H. Delete legacy files

```bash
git rm lib/features/search/legacy/search_provider.dart
git rm lib/features/user_info/legacy/user_data_provider.dart
rmdir lib/features/search/legacy lib/features/user_info/legacy
# Spec 08 will delete lib/features/home/legacy/notes_provider.dart later.
```

Remove the now-orphaned `Search` and `UserData` import lines and Provider declarations from `lib/main.dart`. **Do not remove the `Notes` provider** from `main.dart` — Spec 08 owns that.

### I. Tests

- `search_cubit_test.dart`: each method (activate/deactivate/setQuery/setFilter/addTag/removeTag) — verify state transitions.
- `user_cubit_test.dart`: `load()` populates state; `updateName` saves to fake repo; `updatePhoto`/`removePhoto` delegate to repo with file cleanup recorded by the fake.
- `hive_user_repository_test.dart`: temp-dir Hive box, save → read → photo cleanup → clear; mirrors the notes repo test from Spec 04.

### J. Update [`context/code-standards.md`](../context/code-standards.md)

Append to Repository layer:

```markdown
- The "trivial state-only" Cubit pattern (no async, no streams) is acceptable for pure UI state machines. SearchCubit is the canonical example. When a Cubit grows async work or needs cancellation, promote it to a Bloc.
```

### K. Update [`context/progress-tracker.md`](../context/progress-tracker.md)

- Mark Spec 07 complete in **Completed**.
- Add to **Architecture decisions**:
  ```markdown
  15. **`SearchCubit` (UI-only) and `UserCubit` (with `UserRepository`)** complete the BLoC migration except for the `Notes` legacy husk that Spec 08 retires. Two repositories now exist: `notes/` and `user/`.
  ```

## Success Criteria

- [ ] `lib/repositories/user/{user_repository.dart, hive_user_repository.dart}` exist and pass repository tests.
- [ ] `lib/features/search/cubit/{search_cubit.dart, search_state.dart}` exist; `lib/features/search/legacy/` deleted.
- [ ] `lib/features/user_info/cubit/{user_cubit.dart, user_state.dart}` exist; `lib/features/user_info/legacy/` deleted.
- [ ] `User.fromJson` factory exists in `lib/models/user.dart`.
- [ ] `lib/main.dart` registers `UserRepository`, `SearchCubit`, `UserCubit`. The legacy `Notes` ChangeNotifier provider stays.
- [ ] No file under `lib/features/{home,note_editor,search,settings,user_info}/` (excluding the remaining `home/legacy/`) imports `package:provider`.
- [ ] `flutter analyze` exits 0; `bash scripts/check-offline.sh` exits 0; `dart format` clean.
- [ ] `flutter test` exits 0 with new tests for `SearchCubit`, `UserCubit`, `HiveUserRepository`.
- [ ] **Manual smoke**: home greeting matches the time of day; settings shows username; edit username on user_info → home greeting updates; remove profile picture → file gone; rotate filter chip → home list filters.
- [ ] No new packages in `pubspec.yaml`.
- [ ] [`context/code-standards.md`](../context/code-standards.md), [`context/progress-tracker.md`](../context/progress-tracker.md) updated.
- [ ] No invariant changed.

## References

- [04-repository-layer](04-repository-layer.md), [05-bloc-introduction-home](05-bloc-introduction-home.md), [06-bloc-migration-editor](06-bloc-migration-editor.md)
- [`context/architecture.md`](../context/architecture.md) — invariants 5, 6, 7
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Skill: [`dart-add-unit-test`](../.agents/skills/dart-add-unit-test/SKILL.md), [`dart-flutter-patterns`](../.agents/skills/dart-flutter-patterns/SKILL.md)
- Agent: `flutter-expert` — audit cubit lifecycle and BlocProvider scoping
- Follow-up: [08-provider-removal](08-provider-removal.md)
