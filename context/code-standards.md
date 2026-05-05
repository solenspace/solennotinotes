# Notinotes — Code Standards

## General principles

- Small, single-purpose modules.
- Fix root causes; don't layer workarounds.
- Trust internal code; validate only at system boundaries (P2P payload, file imports, share manifest).
- Three similar lines is better than a premature abstraction.

## Comments

Default to writing no comments. Code with well-named identifiers, small functions, and clear types is self-documenting. Add a comment **only** when:

- The *why* is non-obvious (a hidden constraint, a workaround for a third-party bug, a subtle invariant).
- The reader cannot infer the intent from the names + types.

Never add comments that:

- Repeat the function name or restate what the next line does.
- Explain the spec or feature being implemented (that's progress-tracker / git history).
- Mark TODO without a tracking spec or open question.
- Tag the implementer or reviewer ("// TODO mateo: …", "// alex review this").

When a comment is needed, prefer a single-line above the relevant statement, not multi-line block comments. Doc comments (`///`) on public APIs are acceptable when they replace inferable types, never as decoration.

Code samples in `specs/` carry guide comments to explain the design; production code drops them.

## Dart and analyzer

- `analysis_options.yaml` extends `flutter_lints` (already present).
- Add (per code-standards spec, not in this bootstrap): `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, `avoid_print`, `unawaited_futures`, `prefer_single_quotes`, `require_trailing_commas`, `always_declare_return_types`.
- Null safety mandatory. No `dynamic` outside generated code.
- `dart format` enforced; `dart format --set-exit-if-changed -l 100 lib/ test/` runs in CI.

## Forbidden imports (offline invariant)

The following must never appear under `lib/`:
- `package:http`, `package:dio`, `package:chopper`, `package:retrofit`
- `dart:io.HttpClient` direct use
- `package:web_socket_channel`
- `package:cloud_firestore`, `package:firebase_*`, `package:supabase_*`, `package:appwrite`, `package:amplify_*`
- `package:google_sign_in`, `package:firebase_auth`
- `package:sentry`, `package:firebase_crashlytics`, `package:posthog_flutter`, `package:mixpanel_flutter`

Two gates enforce this — see [Spec 02](../specs/02-offline-invariant-ci-gate.md): a fast `scripts/check-offline.sh` grep run at pre-commit, and the `forbidden_import` rule in `tools/forbidden_imports_lint/` fired by `flutter analyze`. Both read from `scripts/.forbidden-imports.txt`.

## flutter_bloc usage

- One BLoC (or Cubit) per feature screen or per cohesive workflow.
- `<Feature>Cubit` for simple state-only flows; `<Feature>Bloc` when there are discrete events.
- States are immutable, prefer `Equatable` or `freezed` (introduce per spec).
- BLoCs receive repositories via constructor; provided in the tree via `RepositoryProvider`.
- BLoCs **never** import from `widgets/` or `screens/`. Tests assert this with `import_lint`-like grep.
- Every BLoC has a unit test using `bloc_test`.

## Repository layer

- Cross-cutting domain repositories live at `lib/repositories/<resource>/`. Feature-private repositories live at `lib/features/<feature>/repository/`. When a second feature needs to read a feature-private resource, promote it to cross-cutting.
- Each repository is an abstract class; concrete implementations are siblings (e.g. `notes_repository.dart` + `hive_notes_repository.dart`).
- Methods return immutable models and primitives — never raw Hive objects, raw `Map`s, or `Box` references.
- Future API for one-shot operations (`getAll`, `save`, `delete`); Stream API (`watchAll`) for collection observation. Streams are driven by `box.watch()`, emit the full snapshot on each change, and must close cleanly when no listener remains.
- Repositories own ALL native side effects of their resource (Hive writes, file deletes, future P2P send). They DO NOT own user-facing notifications, telemetry, or BLoC orchestration.
- Tests for repositories use a real Hive box opened against a temp dir (no mocking Hive). Mocking happens at the `NotesRepository` interface in BLoC tests.

## Models

- Immutable: `final` fields + a `copyWith` method (or `freezed` per spec).
- Hive CE adapters generated via `build_runner`.
- Equality and hashCode implemented (Equatable or freezed).
- No business logic on models — only data + serialization helpers.

## File organization

```
lib/
├── main.dart                  ← app entry; bootstraps Hive, providers, routing
├── app/                       ← MaterialApp, theme glue, route table, global providers
├── features/<feature>/        ← collocated feature unit
│   ├── bloc/                  ← BLoCs / Cubits for the feature; no widget imports
│   ├── repository/            ← feature-private data, only this feature reads/writes
│   ├── widgets/               ← UI components used only by this feature
│   ├── screen.dart            ← single-screen feature (or screens/ if multiple)
│   └── legacy/                ← Provider-based code in transition; retired in Spec 05+
├── repositories/<resource>/   ← cross-cutting domain data (Note, Tag, Theme, NotiIdentity, …)
├── services/                  ← cross-cutting native wrappers (STT, TTS, P2P, AI, permissions, notifications, image)
├── models/                    ← immutable domain models shared across features
├── theme/                     ← base ThemeData + NotiTheme overlay system
├── helpers/                   ← stateless utilities (validators, formatters)
├── widgets/                   ← shared widgets used by 2+ features
└── assets/                    ← icons, fonts, pattern images (frozen)
```

Imports: relative within a feature folder, absolute (`package:noti_notes_app/...`) across features.

## Tests

- Unit tests for every BLoC (`bloc_test` package, introduce per test spec).
- Unit tests for every repository (mock data sources via `mockito`/`mocktail`).
- Widget tests for every screen's golden-path interaction.
- Golden tests for the theme system (NotiTheme variants render consistently).
- Integration test for the share flow with two simulated peers (per integration spec).

## Localization

- All user-facing strings flow through `intl` ARB files.
- No hardcoded English in `screens/` or `widgets/` (English copy lives in the `en.arb` file).
- Validators return translation keys; UI resolves to display strings.

## Logging

- No `print`. Use `debugPrint`.
- Production logs are off-device (i.e., not shipped). On-device only `debugPrint` during development.
- Errors that previously would have been reported to a service get surfaced in a local "diagnostics" screen instead — never sent off-device.

## Permissions

- Request at point of use (when the user first taps a feature that needs it).
- Wrap each request in `PermissionsService`; UI receives a typed result, never raw plugin output.
- If permission denied permanently, show an in-app explainer with a deep link to OS settings.

## Pubspec discipline

- Adding a dependency requires checking it doesn't pull in any forbidden imports transitively.
- Lock with `pubspec.lock`; never edit by hand.
- Bump versions in dedicated specs; one bump per spec ideally.

## Verification commands (run before declaring a unit done)

- `flutter analyze` — clean
- `dart format --set-exit-if-changed -l 100 lib/ test/` — clean
- `flutter test` — green
- `flutter build apk --debug` — succeeds (smoke)
- Spec-specific: `flutter drive` integration suite, golden tests, etc.
