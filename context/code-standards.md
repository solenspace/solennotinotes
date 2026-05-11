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
- `package:provider` — banned post-Spec-10; the last consumer (`ThemeProvider`) was migrated to `ThemeCubit`. `flutter_bloc` re-exports the `RepositoryProvider` we still rely on.

Two gates enforce this — see [Spec 02](../specs/02-offline-invariant-ci-gate.md): a fast `scripts/check-offline.sh` grep run at pre-commit, and the `forbidden_import` rule in `tools/forbidden_imports_lint/` fired by `flutter analyze`. Both read from `scripts/.forbidden-imports.txt`.

### Forbidden imports (hygiene)

The following imports are also forbidden under `lib/` for hygiene reasons (not enforced by `scripts/check-offline.sh` or `forbidden_import` because they are not network-related):

- `package:permission_handler` — go through `PermissionsService` (`lib/services/permissions/`) instead. The wrapper is the sole gate; consumers receive a typed `PermissionResult`. Established by [Spec 12](../specs/12-permissions-service.md).
- `package:flutter_local_notifications` (raw) — go through `LocalNotificationService` (`lib/services/notifications/`). Instance-ification of that service is tracked in open question 11.
- `package:record` and `package:audioplayers` — direct imports are confined to `lib/services/audio/`, `lib/repositories/audio/`, and `lib/features/note_editor/widgets/audio_*.dart`. Other consumers go through `AudioRepository` (capture lifecycle) and `AudioBlockView` (playback). Established by [Spec 13](../specs/13-audio-capture.md).
- `package:speech_to_text` — direct imports are confined to `lib/services/speech/` (the `SttService` wrapper and `SttCapabilityProbe`). Listed in `scripts/.forbidden-imports.txt` and carved out per file in `scripts/.offline-allowlist`; both `scripts/check-offline.sh` and the `forbidden_imports_lint` custom rule honor the path-based allowlist. The wrapper enforces `onDevice: true` on every recognition request so the offline invariant cannot be relaxed by a consumer. Established by [Spec 15](../specs/15-stt-integration.md).
- `package:flutter_tts` — direct imports are confined to `lib/services/speech/tts_service.dart` (the `TtsService` wrapper). Listed in `scripts/.forbidden-imports.txt` and carved out in `scripts/.offline-allowlist`; both gates honor the carve-out. The native engines (`AVSpeechSynthesizer` / Android `TextToSpeech`) bundle their own voices and run fully offline, so no extra runtime guard is needed beyond the path confinement. Established by [Spec 16](../specs/16-tts-integration.md).
- `package:device_info_plus` — direct imports are confined to `lib/services/device/device_capability_probe.dart` (the cold-start probe; consumers go through `DeviceCapabilityService` at `lib/services/device/device_capability_service.dart`). Listed in `scripts/.forbidden-imports.txt` and carved out in `scripts/.offline-allowlist`. The plugin reads system properties (`UIDevice` on iOS, `android.os.Build` on Android) and makes no network calls. Established by [Spec 17](../specs/17-device-capability-service.md).
- `package:flutter_secure_storage` and `package:cryptography` — direct imports are confined to `lib/services/crypto/flutter_secure_keypair_service.dart` (the `KeypairService` wrapper). Listed in `scripts/.forbidden-imports.txt` and carved out in `scripts/.offline-allowlist`. Neither package makes network calls; the wrapper centralizes private-key handling so no other layer can read the raw bytes. Established by [Spec 22](../specs/22-p2p-transport-service.md).
- The P2P transport itself is **native platform channels** (iOS `MultipeerConnectivity`, Android `Nearby.getConnectionsClient()`); no Dart plugin is involved. Channel names (`noti.peer/control`, `noti.peer/{peers,invites,payloads,transfers}`) are private to `lib/services/share/channel_peer_service.dart` and the matching `ios/Runner/PeerServicePlugin.swift` + `android/app/src/main/kotlin/com/example/noti_notes_app/PeerServicePlugin.kt`. All consumers go through `PeerService` (`lib/services/share/peer_service.dart`). Established by [Spec 22](../specs/22-p2p-transport-service.md).

## Styling

All UI reads colors / type / motion / shape / elevation / spacing from `context.tokens.<category>.<role>`. Hardcoded `Color(0x…)` literals, magic radii, magic durations, and hand-rolled `TextStyle` outside `lib/theme/tokens/` are defects. The token system layers are: primitives (private to `lib/theme/tokens/`) → semantics (`ThemeExtension<T>` per category — colors, text, motion, shape, elevation, spacing, patternBackdrop, signature) → access (`context.tokens.<category>.<role>`). Per-note overlays (Spec 11) clone and patch the active `NotiColors` / `NotiPatternBackdrop` / `NotiSignature` extensions; no other extensions are ever overridden.

Curated palette data (per-note background swatches, gradient presets, starter palettes) lives in `lib/theme/curated_palettes.dart`; that file is the only path outside `lib/theme/tokens/` allowed to construct raw `Color(0x…)` literals. The `no_hardcoded_color` `custom_lint` rule (in `tools/forbidden_imports_lint/`) enforces this at WARNING severity; `lib/models/` and `test/` are exempt because they construct `Color` from persisted ints / fixtures, not from hex literals.

## flutter_bloc usage

- Default to `Bloc` over `Cubit` when there are 3+ user-driven triggers; reserve `Cubit` for trivial state-only flows.
- State classes extend `Equatable`. `freezed` is introduced only when union types appear.
- Stream-driven BLoCs use `emit.forEach(stream, onData: ..., onError: ...)` to bridge repository streams into state. The handler is awaited so the subscription is owned by the bloc-base lifecycle.
- `RepositoryProvider` (re-exported by `flutter_bloc`) is the canonical injection mechanism for repositories. Plain `Provider` is used only for legacy `ChangeNotifier` instances during the migration window.
- BLoCs receive repositories (and any platform side-effects that aren't pure functions, e.g. notification cancellation) via constructor. Defaults point at the production implementation; tests pass fakes/recording lambdas.
- BLoCs **never** import from `widgets/` or `screens/`. Tests assert this with `import_lint`-like grep.
- Tests use a hand-rolled `Fake<Resource>Repository` exposing a controllable broadcast stream. Fakes live at `test/repositories/<resource>/fake_<resource>_repository.dart`. Each event handler has at least one expectation.
- A `LoggingBlocObserver` may be registered in `main.dart` under `kDebugMode` only — never in release builds (offline invariant 1: nothing leaves the device).
- Per-route BLoCs are mounted via `BlocProvider.create` inside the screen's `build` (or a `MaterialPageRoute.builder`). The BLoC's lifetime equals the route's. Initial-load events fire from the cascade in `create:` (`..add(InitEvent())`).
- Side-effect signals (route pop, snackbars, navigation) ride on a one-shot boolean field in state; `BlocListener` reacts and the next state resets the flag. BLoCs do not import `BuildContext`.

## Repository layer

- Cross-cutting domain repositories live at `lib/repositories/<resource>/`. Feature-private repositories live at `lib/features/<feature>/repository/`. When a second feature needs to read a feature-private resource, promote it to cross-cutting.
- Each repository is an abstract class; concrete implementations are siblings (e.g. `notes_repository.dart` + `hive_notes_repository.dart`).
- Methods return immutable models and primitives — never raw Hive objects, raw `Map`s, or `Box` references.
- Future API for one-shot operations (`getAll`, `save`, `delete`); Stream API (`watchAll`) for collection observation. Streams are driven by `box.watch()`, emit the full snapshot on each change, and must close cleanly when no listener remains.
- Repositories own ALL native side effects of their resource (Hive writes, file deletes, future P2P send). They DO NOT own user-facing notifications, telemetry, or BLoC orchestration.
- Tests for repositories use a real Hive box opened against a temp dir (no mocking Hive). Mocking happens at the `NotesRepository` interface in BLoC tests.
- Single-record repositories (e.g. `UserRepository`) follow the same pattern: abstract interface + Hive impl + `@visibleForTesting` `withBox` constructor + `getCurrent()`/`watch()` paired API. Box-key lifecycle (e.g. `'user_v2'` / `'userFromDevice'`) and on-disk image cleanup live behind the interface.
- The "trivial state-only" Cubit pattern (no async, no streams) is acceptable for pure UI state machines. `SearchCubit` is the canonical example. When a Cubit grows async work or needs cancellation, promote it to a Bloc.
- When a cubit owns a mutable domain model (e.g. legacy `User`/`Note` without `copyWith`), clone the model into a fresh instance before emitting state. Reusing the same reference makes Equatable's `==` see no change and silently suppresses the emit. Cloning becomes redundant once the model is migrated to immutable + `copyWith` (future adapter spec).

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
- _Enforced by Spec 26 (2026-05-11): `gen_l10n` codegen from [`lib/l10n/en.arb`](../lib/l10n/en.arb) drives [`lib/generated/app_localizations.dart`](../lib/generated/app_localizations.dart) (gitignored; regenerated by every `flutter pub get`). Call sites read via `context.l10n.<key>` through the [`AppL10n`](../lib/l10n/build_context_l10n.dart) `BuildContext` extension. The `hardcoded_text_in_widget` rule in [`tools/forbidden_imports_lint`](../tools/forbidden_imports_lint/lib/src/hardcoded_text_in_widget_rule.dart) flags any new `Text(<literal>)` outside `lib/l10n/`, `lib/generated/`, `lib/models/`, `lib/services/`, `lib/repositories/`, `lib/theme/`, and `test/`. Single-character glyphs (e.g. `'☼'`, `'+'`) and empty strings are exempt — they are icon-equivalent decorations, not chrome. Out of scope per Spec 26: bloc/cubit `errorMessage` strings (validator-key pattern is a follow-up)._

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
