# 09 — noti-identity

## Goal

Rename the legacy `User` model to **`NotiIdentity`** — the per-user identity that travels with every shared note — and extend it with the four signature fields that make a "noti" feel personal: `signaturePalette` (a small set of color swatches), `signaturePatternKey` (one of the bundled background patterns or null), `signatureAccent` (a single emoji or glyph), and `signatureTagline` (a short user-authored line shown on shared notes). The Hive box is migrated from `user_v2` to `noti_identity_v2` once, on first launch after this spec ships. `UserCubit` and `UserRepository` are renamed `NotiIdentityCubit` / `NotiIdentityRepository`; the cubit absorbs the greeting logic. After this spec, the codebase has no `User` symbol, and every consumer (home greeting, settings, user_info screen) reads from `NotiIdentityCubit`.

The cryptographic keypair for share-payload signing is **deferred to the P2P share spec** — Spec 09 ships only the user-facing identity fields.

## Dependencies

- [04-repository-layer](04-repository-layer.md) — repository pattern.
- [07-bloc-migration-search-and-user](07-bloc-migration-search-and-user.md) — `UserRepository` + `UserCubit` exist; this spec renames + extends them.
- [08-notes-legacy-removal](08-notes-legacy-removal.md) — confirms the BLoC migration is complete; this spec extends the established conventions.

## Agents & skills

**Pre-coding skills:**
- `dart-flutter-patterns` — model immutability + `copyWith`, repository conventions.
- `flutter-implement-json-serialization` — `User` → `NotiIdentity` JSON encoder/decoder for the migration path.
- `dart-add-unit-test` — repo + cubit tests including the legacy-box migration scenario.

**After-coding agents:**
- `flutter-expert` — audit the cubit lifecycle (especially the `load → setters → save` cycle) and the migration code.
- `code-reviewer` — verify the rename doesn't drop fields silently; the migration is idempotent and one-time.

## Design Decisions

- **Rename, don't coexist.** `User` is replaced by `NotiIdentity`. The `User` class is deleted in this spec; `lib/models/user.dart` becomes `lib/models/noti_identity.dart`. No bridge layer.
- **Keep all legacy fields except none.** `id`, `displayName` (renamed from `name`), `bornDate`, `profilePicture` all survive. We add four signature fields. No fields are dropped — even `bornDate`, which has no current use, stays since the user picked "deprecate User outright" without dropping fields.
- **One-time Hive migration on first launch.** `HiveNotiIdentityRepository.init()` does:
  1. Open `noti_identity_v2`.
  2. If empty AND the legacy `user_v2` box has data, read the legacy record, build a `NotiIdentity` with defaults for new fields, write to the new box, then `Hive.deleteBoxFromDisk('user_v2')`.
  3. If both empty, generate a fresh `NotiIdentity` with random defaults (random palette swatch, no pattern, no accent, empty tagline) and persist.
  4. If `noti_identity_v2` already has data, do nothing.
- **`signaturePalette` is a list of `Color` (typically 4 swatches).** Each palette swatch is encoded as ARGB int in JSON, mirroring how `Note.colorBackground` is already stored. Default for first launch: a randomly picked palette from the four "starter palettes" (defined in this spec's Section E) so two users get different defaults out of the box.
- **`signaturePatternKey` is a string key into a closed enum-like list of bundled patterns** (see [`lib/assets/images/patterns/`](../lib/assets/images/patterns/)): `'waves'`, `'wavesRegulated'`, `'polygons'`, `'kaleidoscope'`, `'splashes'`, `'noise'`, `'upScaleWaves'`, or `null`. This spec adds a `NotiPatternKey` enum at `lib/theme/noti_pattern_key.dart`. The actual pattern *rendering* on note cards lands in Spec 11 (noti-theme-overlay).
- **`signatureAccent` is a `String?` constrained to a single grapheme.** Validation runs on save: trim, ensure exactly one user-perceived character (using `characters` package — already a transitive dep via Flutter). Empty allowed; >1 grapheme rejected.
- **`signatureTagline` is a `String` capped at 60 chars.** Empty allowed.
- **`NotiIdentityCubit` absorbs the greeting.** `UserCubit.greeting` becomes `NotiIdentityState.greetingFor(now)` — a derived getter, not a stored field. The randomized greeting list is unchanged but now interpolates `displayName` instead of `name`. Greeting state is recomputed every time the cubit emits a new state, so when the user changes their display name, the next greeting reflects it.
- **No `package:cryptography`, no `flutter_secure_storage`, no keypair fields.** Deferred to the share spec.
- **Files renamed via `git mv` so history is preserved.** `lib/models/user.dart` → `lib/models/noti_identity.dart`; `lib/repositories/user/` → `lib/repositories/noti_identity/`; `lib/features/user_info/cubit/user_cubit.dart` → `noti_identity_cubit.dart` (folder unchanged — `user_info` is the screen folder, not the cubit's identity).
- **No new packages.** All new behavior is plain Dart + existing deps. The `characters` package is already pulled in transitively by Flutter.

## Implementation

### A. New model: `lib/models/noti_identity.dart`

```dart
import 'dart:io';
import 'dart:ui';

import 'package:uuid/uuid.dart';

/// A user's signature identity. Travels with every shared note so the
/// receiver renders the sender's preferred look (palette, pattern, accent,
/// tagline) faithfully.
class NotiIdentity {
  NotiIdentity({
    required this.id,
    required this.displayName,
    required this.bornDate,
    required this.signaturePalette,
    this.profilePicture,
    this.signaturePatternKey,
    this.signatureAccent,
    this.signatureTagline = '',
  });

  /// Stable per-install UUID. Never changes after first generation.
  final String id;

  String displayName;
  DateTime bornDate;
  File? profilePicture;

  /// 1–6 swatches the user picked as "their" colors. Receivers render
  /// shared notes' default backgrounds against this palette.
  List<Color> signaturePalette;

  /// Key into the bundled pattern set (see [NotiPatternKey]). Null = none.
  String? signaturePatternKey;

  /// Exactly 0 or 1 user-perceived character. Rendered as a small badge
  /// on the user's noti chip and on shared notes.
  String? signatureAccent;

  /// A short user-authored line (≤ 60 chars). Shown on the share-preview
  /// card the receiver sees before accepting a note.
  String signatureTagline;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'bornDate': bornDate.toIso8601String(),
        'profilePicture': profilePicture?.path,
        'signaturePalette':
            signaturePalette.map((c) => c.toARGB32()).toList(growable: false),
        'signaturePatternKey': signaturePatternKey,
        'signatureAccent': signatureAccent,
        'signatureTagline': signatureTagline,
      };

  factory NotiIdentity.fromJson(Map<String, dynamic> json) {
    return NotiIdentity(
      id: json['id'] as String,
      displayName: (json['displayName'] ?? json['name'] ?? '') as String,
      bornDate: DateTime.parse(json['bornDate'] as String),
      profilePicture: json['profilePicture'] != null
          ? File(json['profilePicture'] as String)
          : null,
      signaturePalette: (json['signaturePalette'] as List?)
              ?.cast<int>()
              .map(Color.new)
              .toList() ??
          NotiIdentityDefaults.starterPalettes.first,
      signaturePatternKey: json['signaturePatternKey'] as String?,
      signatureAccent: json['signatureAccent'] as String?,
      signatureTagline: (json['signatureTagline'] as String?) ?? '',
    );
  }

  /// Generates a fresh identity with a randomly-picked starter palette.
  factory NotiIdentity.fresh({String displayName = ''}) {
    final palettes = NotiIdentityDefaults.starterPalettes;
    return NotiIdentity(
      id: const Uuid().v4(),
      displayName: displayName,
      bornDate: DateTime.now(),
      signaturePalette: List.of(
        palettes[DateTime.now().microsecond % palettes.length],
      ),
    );
  }
}

class NotiIdentityDefaults {
  /// Starter palettes — each entry is an ordered list of swatches
  /// (background, surface, accent, text-on-accent). Picked at random
  /// for first-launch identities so two users get different defaults.
  static const List<List<Color>> starterPalettes = [
    [Color(0xFF2D2D2D), Color(0xFF383838), Color(0xFFE5B26B), Color(0xFFF2EFEA)],
    [Color(0xFF1B1F2A), Color(0xFF24293A), Color(0xFF7BAFD4), Color(0xFFEAF1FA)],
    [Color(0xFF1F2620), Color(0xFF2A332C), Color(0xFF8FA66F), Color(0xFFEDF1E6)],
    [Color(0xFF2A1F26), Color(0xFF362A32), Color(0xFFD37FA0), Color(0xFFF7EDF1)],
  ];
}
```

### B. New enum: `lib/theme/noti_pattern_key.dart`

```dart
/// Closed list of bundled pattern PNGs under lib/assets/images/patterns/.
/// Keys map to file basenames (without extension).
enum NotiPatternKey {
  waves('wavesRegulatedPNG'),
  wavesUnregulated('wavesUnregulatedPNG'),
  polygons('polygons'),
  kaleidoscope('klaeidoscope'),
  splashes('splashesPNG'),
  noise('pureNoisePNG'),
  upScaleWaves('upScaleWavesPNG');

  const NotiPatternKey(this.assetBasename);

  final String assetBasename;

  String get assetPath => 'lib/assets/images/patterns/$assetBasename.png';

  static NotiPatternKey? fromString(String? key) {
    if (key == null) return null;
    for (final p in NotiPatternKey.values) {
      if (p.name == key) return p;
    }
    return null;
  }
}
```

### C. Repository: `lib/repositories/noti_identity/`

Both `notes/` and `noti_identity/` follow the same pattern. Repository file structure:

```
lib/repositories/noti_identity/
├── noti_identity_repository.dart   ← abstract
└── hive_noti_identity_repository.dart
```

`noti_identity_repository.dart`:

```dart
import 'dart:io';

import 'package:noti_notes_app/models/noti_identity.dart';

abstract class NotiIdentityRepository {
  Future<void> init();
  Future<NotiIdentity> getCurrent();
  Stream<NotiIdentity> watch();
  Future<void> save(NotiIdentity identity);
  Future<void> setPhoto(NotiIdentity identity, File? newPhoto);
  Future<void> removePhoto(NotiIdentity identity);
}
```

`hive_noti_identity_repository.dart` — implementation with the migration logic in `init()`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';

class HiveNotiIdentityRepository implements NotiIdentityRepository {
  HiveNotiIdentityRepository({ImagePickerService? imageService})
      : _imageService = imageService ?? const ImagePickerService();

  static const String _newBoxName = 'noti_identity_v2';
  static const String _legacyBoxName = 'user_v2';
  static const String _key = 'identityFromDevice';

  final ImagePickerService _imageService;
  Box<dynamic>? _box;
  final _controller = StreamController<NotiIdentity>.broadcast();

  @override
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(_newBoxName);
    if (_box!.isEmpty && await Hive.boxExists(_legacyBoxName)) {
      await _migrateFromLegacy();
    }
    if (_box!.isEmpty) {
      // Fresh install — generate a new identity.
      final fresh = NotiIdentity.fresh();
      await save(fresh);
    }
  }

  Future<void> _migrateFromLegacy() async {
    final legacy = await Hive.openBox<dynamic>(_legacyBoxName);
    if (legacy.isNotEmpty) {
      final raw = legacy.values.first;
      if (raw is String) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final migrated = NotiIdentity(
          id: (json['id'] as String?) ?? '',
          displayName: (json['name'] as String?) ?? '',
          bornDate: DateTime.parse(
            (json['bornDate'] as String?) ?? DateTime.now().toIso8601String(),
          ),
          profilePicture: json['profilePicture'] != null
              ? File(json['profilePicture'] as String)
              : null,
          signaturePalette: List.of(NotiIdentityDefaults.starterPalettes.first),
        );
        await _box!.put(_key, jsonEncode(migrated.toJson()));
      }
    }
    await legacy.close();
    await Hive.deleteBoxFromDisk(_legacyBoxName);
  }

  @override
  Future<NotiIdentity> getCurrent() async {
    final raw = _box!.get(_key);
    if (raw is String) {
      return NotiIdentity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    final fresh = NotiIdentity.fresh();
    await save(fresh);
    return fresh;
  }

  @override
  Stream<NotiIdentity> watch() async* {
    yield await getCurrent();
    yield* _controller.stream;
  }

  @override
  Future<void> save(NotiIdentity identity) async {
    _validate(identity);
    await _box!.put(_key, jsonEncode(identity.toJson()));
    _controller.add(identity);
  }

  @override
  Future<void> setPhoto(NotiIdentity identity, File? newPhoto) async {
    final old = identity.profilePicture;
    if (old != null && old.path != newPhoto?.path) {
      await _imageService.removeImage(old);
    }
    identity.profilePicture = newPhoto;
    await save(identity);
  }

  @override
  Future<void> removePhoto(NotiIdentity identity) async {
    final old = identity.profilePicture;
    if (old != null) {
      await _imageService.removeImage(old);
    }
    identity.profilePicture = null;
    await save(identity);
  }

  void _validate(NotiIdentity i) {
    final accent = i.signatureAccent;
    if (accent != null && accent.isNotEmpty) {
      final length = accent.characters.length;
      if (length != 1) {
        throw ArgumentError('signatureAccent must be exactly one grapheme; got "$accent" ($length)');
      }
    }
    if (i.signatureTagline.length > 60) {
      throw ArgumentError('signatureTagline must be ≤ 60 chars; got ${i.signatureTagline.length}');
    }
    if (i.signaturePalette.isEmpty) {
      throw ArgumentError('signaturePalette must contain at least one swatch');
    }
  }
}
```

### D. Cubit: `lib/features/user_info/cubit/`

Rename + extend. The state grows three new fields; the cubit gains setters for them.

`lib/features/user_info/cubit/noti_identity_state.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';
import 'package:noti_notes_app/models/noti_identity.dart';

import 'dart:math';

enum NotiIdentityStatus { initial, loading, ready, error }

class NotiIdentityState extends Equatable {
  const NotiIdentityState({
    this.status = NotiIdentityStatus.initial,
    this.identity,
    this.errorMessage,
  });

  final NotiIdentityStatus status;
  final NotiIdentity? identity;
  final String? errorMessage;

  /// Time-of-day greeting derived from the current identity. Recomputed
  /// each time it's read so a name change reflects immediately.
  String greetingFor(DateTime now, {Random? random}) {
    final id = identity;
    if (id == null) return 'Noti';
    final rng = random ?? Random();
    final timeOfDay = now.hour < 12 ? 'Morning' : (now.hour < 17 ? 'Afternoon' : 'Evening');
    final day = DateFormat('EEEE').format(now);
    final name = id.displayName.isEmpty ? 'User' : id.displayName.toLowerCase();

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

    return pool[rng.nextInt(pool.length)];
  }

  NotiIdentityState copyWith({
    NotiIdentityStatus? status,
    NotiIdentity? identity,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotiIdentityState(
      status: status ?? this.status,
      identity: identity ?? this.identity,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, identity, errorMessage];
}
```

`lib/features/user_info/cubit/noti_identity_cubit.dart`:

```dart
import 'dart:io';
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';

import 'noti_identity_state.dart';

class NotiIdentityCubit extends Cubit<NotiIdentityState> {
  NotiIdentityCubit({required NotiIdentityRepository repository})
      : _repository = repository,
        super(const NotiIdentityState());

  final NotiIdentityRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: NotiIdentityStatus.loading));
    final identity = await _repository.getCurrent();
    emit(state.copyWith(status: NotiIdentityStatus.ready, identity: identity));
  }

  Future<void> updateDisplayName(String name) async {
    final id = state.identity;
    if (id == null) return;
    id.displayName = name;
    await _repository.save(id);
    emit(state.copyWith(identity: id));
  }

  Future<void> updatePhoto(File? photo) async {
    final id = state.identity;
    if (id == null) return;
    await _repository.setPhoto(id, photo);
    emit(state.copyWith(identity: id));
  }

  Future<void> removePhoto() async {
    final id = state.identity;
    if (id == null || id.profilePicture == null) return;
    await _repository.removePhoto(id);
    emit(state.copyWith(identity: id));
  }

  Future<void> updatePalette(List<Color> swatches) async {
    final id = state.identity;
    if (id == null) return;
    id.signaturePalette = List.of(swatches);
    await _repository.save(id);
    emit(state.copyWith(identity: id));
  }

  Future<void> updatePatternKey(String? key) async {
    final id = state.identity;
    if (id == null) return;
    id.signaturePatternKey = key;
    await _repository.save(id);
    emit(state.copyWith(identity: id));
  }

  Future<void> updateAccent(String? accent) async {
    final id = state.identity;
    if (id == null) return;
    id.signatureAccent = accent?.isEmpty == true ? null : accent;
    await _repository.save(id);
    emit(state.copyWith(identity: id));
  }

  Future<void> updateTagline(String tagline) async {
    final id = state.identity;
    if (id == null) return;
    id.signatureTagline = tagline;
    await _repository.save(id);
    emit(state.copyWith(identity: id));
  }
}
```

### E. Delete the old `User` artifacts

```bash
git rm lib/models/user.dart
git rm lib/repositories/user/user_repository.dart
git rm lib/repositories/user/hive_user_repository.dart
rmdir lib/repositories/user
git rm lib/features/user_info/cubit/user_cubit.dart
git rm lib/features/user_info/cubit/user_state.dart
```

Replace with the renamed files (Sections A, C, D).

### F. Update consumers

- `lib/features/home/screen.dart` and home widgets that read `state.user.name` / `state.greeting` → switch to `NotiIdentityCubit` and `state.greetingFor(DateTime.now())`. Greeting is now derived per-build, not stored.
- `lib/features/user_info/screen.dart` — every form field reads from `state.identity!.…`; mutations call the cubit's setters. Add UI controls for the four signature fields **only as plumbing** — actual UI design (palette picker, pattern picker, accent input, tagline field) is **deferred to Spec 11** (noti-theme-overlay). For Spec 09, add bare placeholder controls (basic `TextField` for tagline, simple swatch grid for palette, dropdown for pattern key, `TextField` for accent with grapheme-count validation) so the data layer is exercisable end-to-end.
- `lib/features/settings/screen.dart` — references to username switch to `state.identity?.displayName`.

### G. Update `lib/main.dart`

```dart
final notiIdentityRepository = HiveNotiIdentityRepository();
await notesRepository.init();
await notiIdentityRepository.init();

runApp(
  MultiRepositoryProvider(
    providers: [
      RepositoryProvider<NotesRepository>.value(value: notesRepository),
      RepositoryProvider<NotiIdentityRepository>.value(value: notiIdentityRepository),
    ],
    child: ChangeNotifierProvider(
      create: (_) => ThemeProvider(),  // still legacy; Spec 10 retires this
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) => NotesListBloc(repository: ctx.read<NotesRepository>())
              ..add(const NotesListSubscribed()),
          ),
          BlocProvider(create: (_) => SearchCubit()),
          BlocProvider(
            create: (ctx) => NotiIdentityCubit(
              repository: ctx.read<NotiIdentityRepository>(),
            )..load(),
          ),
        ],
        child: const NotiApp(),
      ),
    ),
  ),
);
```

### H. Tests

- `test/repositories/noti_identity/hive_noti_identity_repository_test.dart` — temp-dir Hive box; verifies:
  - Fresh install creates a `NotiIdentity` with one of the starter palettes.
  - Migration reads a legacy `user_v2` record, builds a `NotiIdentity`, deletes the legacy box.
  - Validation rejects multi-grapheme `signatureAccent` and `signatureTagline > 60 chars`.
- `test/features/user_info/cubit/noti_identity_cubit_test.dart` — covers `load`, all 7 setters, `state.greetingFor(now)` returns a non-empty string, name change reflects in next greeting.
- `test/repositories/noti_identity/fake_noti_identity_repository.dart` — fake test double mirroring `FakeNotesRepository` from Spec 05.

### I. Update `context/architecture.md`

Add `NotiIdentity` to the **Storage model** Hive box list:

```markdown
- `noti_identity` — single record: this user's noti (id, displayName, bornDate, profilePicture, signaturePalette, signaturePatternKey, signatureAccent, signatureTagline). Migrated from legacy `user_v2` on first launch after Spec 09.
```

Add to **System boundaries → cross-cutting**: `lib/repositories/noti_identity/`.

No invariant change.

### J. Update `context/code-standards.md`

No change — repository pattern conventions already cover this.

### K. Update `context/progress-tracker.md`

- Mark Spec 09 complete.
- Add to **Architecture decisions**:
  ```markdown
  17. **`NotiIdentity` replaces `User`.** Single per-install identity with palette + pattern + accent + tagline. Cryptographic keypair for share signing deferred to the share spec.
  ```
- Resolve open question on the user-data box name (now `noti_identity_v2`).

## Success Criteria

- [ ] `lib/models/noti_identity.dart` exists; `lib/models/user.dart` does not.
- [ ] `lib/theme/noti_pattern_key.dart` exists with the 7-pattern enum.
- [ ] `lib/repositories/noti_identity/{noti_identity_repository.dart, hive_noti_identity_repository.dart}` exist; `lib/repositories/user/` does not.
- [ ] `lib/features/user_info/cubit/{noti_identity_cubit.dart, noti_identity_state.dart}` exist; `user_cubit.dart` and `user_state.dart` do not.
- [ ] `grep -RnE "\\bUser\\b" lib/` returns matches only inside `package:` import paths or unrelated symbol names (verify each by hand). The class `User` is gone.
- [ ] `flutter analyze` exits 0; offline gate clean; format clean.
- [ ] `flutter test` exits 0 with new tests for repo + cubit + migration. Migration test seeds a fake `user_v2` box, runs `init()`, asserts the new box is populated and the legacy box is deleted.
- [ ] **Manual smoke**: 
  - Fresh install: app shows a starter palette signature, no accent, empty tagline, default greeting.
  - Existing install with legacy `user_v2` data: after first launch, settings shows the migrated display name + bornDate; legacy box is gone from disk.
  - Edit display name → home greeting reflects on next render.
  - Set pattern key + accent + tagline → values persist across app restart.
- [ ] No new packages in `pubspec.yaml`.
- [ ] `context/architecture.md` storage model updated.
- [ ] `context/progress-tracker.md` updated with decision 17.
- [ ] No invariant changed.

## References

- [04-repository-layer](04-repository-layer.md), [07-bloc-migration-search-and-user](07-bloc-migration-search-and-user.md)
- [`context/architecture.md`](../context/architecture.md) — storage model (extended)
- [`context/project-overview.md`](../context/project-overview.md) — "noti identity" definition + share-faithful-render goal
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Skill: [`dart-add-unit-test`](../.agents/skills/dart-add-unit-test/SKILL.md)
- Agent: `flutter-expert` — audit cubit lifecycle and migration code
- Agent: `code-reviewer` — verify the rename doesn't drop or rename fields silently
- Follow-up specs: [10-theme-tokens](10-theme-tokens.md), [11-noti-theme-overlay](11-noti-theme-overlay.md) — both consume `NotiIdentity.signature*` fields and provide the proper UI for editing them.
- Future: keypair generation for share-payload signing — added in the P2P share spec, not here.
