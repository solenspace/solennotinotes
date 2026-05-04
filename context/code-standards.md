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

A grep gate enforces this in CI; spec 0X will add it.

## flutter_bloc usage

- One BLoC (or Cubit) per feature screen or per cohesive workflow.
- `<Feature>Cubit` for simple state-only flows; `<Feature>Bloc` when there are discrete events.
- States are immutable, prefer `Equatable` or `freezed` (introduce per spec).
- BLoCs receive repositories via constructor; provided in the tree via `RepositoryProvider`.
- BLoCs **never** import from `widgets/` or `screens/`. Tests assert this with `import_lint`-like grep.
- Every BLoC has a unit test using `bloc_test`.

## Repository layer

- The only layer that talks to Hive boxes, the filesystem, native plugins, or platform channels.
- One repository per resource: `NoteRepository`, `TagRepository`, `ThemeRepository`, `NotiIdentityRepository`, `ShareRepository`, `ReceivedInboxRepository`, `AiAssistRepository`, `SttRepository`, `TtsRepository`.
- Each repository returns immutable models; never raw Hive objects.
- Streams (e.g. `watchNotes()`) close cleanly when listeners detach.

## Models

- Immutable: `final` fields + a `copyWith` method (or `freezed` per spec).
- Hive CE adapters generated via `build_runner`.
- Equality and hashCode implemented (Equatable or freezed).
- No business logic on models — only data + serialization helpers.

## File organization

```
lib/
├── main.dart
├── app/                   ← MaterialApp, route table, global providers
├── blocs/<feature>/
│   ├── <feature>_bloc.dart       (or _cubit.dart)
│   ├── <feature>_event.dart      (when a Bloc, not Cubit)
│   └── <feature>_state.dart
├── repositories/<feature>/
│   ├── <feature>_repository.dart
│   └── <feature>_data_source.dart   (Hive / fs / plugin wrapper)
├── services/
│   ├── ai/llm_service.dart
│   ├── ai/whisper_service.dart
│   ├── ai/device_capability_service.dart
│   ├── speech/stt_service.dart
│   ├── speech/tts_service.dart
│   ├── share/peer_service.dart
│   ├── share/payload_codec.dart
│   ├── notifications/notifications_service.dart
│   └── permissions/permissions_service.dart
├── models/
│   ├── note.dart
│   ├── todo.dart
│   ├── tag.dart
│   ├── noti_theme.dart
│   ├── noti_identity.dart
│   ├── share_payload.dart
│   └── received_item.dart
├── screens/<feature>/
├── widgets/<feature>/
├── theme/
│   ├── app_theme.dart
│   ├── noti_theme.dart
│   └── tokens.dart
├── helpers/
└── assets/
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
