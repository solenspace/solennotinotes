# 26 — localization-scaffold

## Goal

Stand up the `intl`-based ARB localization pipeline so every user-facing string flows through `t(key)` instead of inline literals. English (`en.arb`) is the only locale at MVP; the structure is in place so adding `es.arb`, `pt.arb`, etc. later is a copy-and-translate job, not a refactor. After this spec, hardcoded English in `lib/features/`, `lib/widgets/`, or `lib/screens/` is a defect caught by `flutter analyze`. The `flutter-setup-localization` validated skill (already installed) is the canonical reference.

## Dependencies

- [10-theme-tokens](10-theme-tokens.md) — typography is locale-aware (some scripts need different line heights).
- All previous specs — every visible string they introduced moves through `t(...)`.

## Agents & skills

**Pre-coding skills:**
- `flutter-setup-localization` — `gen_l10n` configuration, ARB conventions, `MaterialApp` wiring.

**After-coding agents:**
- `code-reviewer` — sweep the `Text('…')` literal grep results; confirm no chrome string survives outside `lib/l10n/`.

## Design Decisions

- **Generator**: `gen_l10n` (the official, in-SDK Flutter generator). Replaces the earlier provisional `intl_utils` choice — `gen_l10n` runs automatically as part of `flutter pub get` when `generate: true` is set in `pubspec.yaml`, so no extra codegen step or external plugin is required.
- **One ARB per locale, namespaced by feature folder.** `lib/l10n/en.arb` is the source of truth at MVP. Keys are namespaced: `home.empty_state`, `editor.share_button`, `inbox.empty`, etc. The flat-key model is simpler than nested JSON and matches the generator's output.
- **`l10n.yaml` at repo root** drives codegen.
- **Dev-only key tracking**: `flutter analyze` reports any `String` literal returned from a build method that isn't a constant identifier or a known whitelist — enforced via a custom_lint rule extension to `forbidden_imports_lint` (the rule from Spec 02 is extended to also flag literal strings inside widget trees).
- **Error messages, debug logs, and SKILL keys** are NOT localized. Only user-visible chrome.

## Implementation

### A. Files

```
lib/l10n/
└── en.arb

l10n.yaml                          ← repo root config

.dart_tool/flutter_gen/gen_l10n/   ← codegen output (gitignored; regenerated on every `flutter pub get`)
```

### B. `pubspec.yaml`

```yaml
flutter:
  generate: true

dependencies:
  flutter_localizations:
    sdk: flutter
```

`intl` is already in pubspec from the imported codebase. **No `intl_utils` dev dep** — `gen_l10n` is built into the Flutter SDK and runs as part of `flutter pub get` whenever `flutter.generate: true` is set.

### C. `l10n.yaml`

```yaml
arb-dir: lib/l10n
template-arb-file: en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
output-dir: lib/generated
nullable-getter: false
synthetic-package: false
```

### D. `lib/l10n/en.arb` — initial harvest

Run a sweep over every `Text(...)`, `appBarTitle`, `tooltip:`, `label:`, snackbar string, dialog title, button label, etc. Collect into `en.arb` with keys.

Seed entries (non-exhaustive):

```json
{
  "@@locale": "en",
  "home_empty_state": "Tap + to create your first note",
  "home_search_hint": "Search",
  "home_appbar_title": "Notes",
  "editor_save": "Save",
  "editor_share_button": "Share nearby",
  "editor_assist_button": "Assist",
  "editor_paintbrush_tooltip": "Theme",
  "editor_dictate_tooltip": "Dictate",
  "editor_record_audio_tooltip": "Record audio",
  "inbox_title": "Inbox",
  "inbox_empty": "Nothing waiting",
  "inbox_accept": "Accept",
  "inbox_discard": "Discard",
  "share_sheet_title": "Share nearby",
  "share_sheet_searching": "Looking for nearby people…",
  "share_sheet_privacy_footer": "Sent over Bluetooth — never through the internet.",
  "ai_disclosure_title": "Enable AI assist?",
  "ai_disclosure_body": "Notinotes will download the model file once (~720 MB). The download is a one-time, one-way connection. Nothing else leaves your device — not now, not later.",
  "permission_explainer_settings_button": "Open settings",
  "permission_microphone_body": "Notinotes uses the microphone to record audio notes and dictation. Audio never leaves your device.",
  "permission_camera_body": "Notinotes uses the camera to capture photos for image notes. Photos stay on your device."
}
```

### E. Sweep over consumers

Replace literals via mechanical search:

```dart
Text('Save')                  → Text(AppLocalizations.of(context).editor_save)
const Text('Share nearby')    → Text(AppLocalizations.of(context).editor_share_button)
```

A `BuildContextX` extension helps shorten:

```dart
extension AppL10n on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this);
}

// usage:
Text(context.t.editor_save)
```

### F. `MaterialApp` wiring

```dart
MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  // ...
)
```

### G. Custom_lint rule extension (optional)

A `hardcoded_text_in_widget` rule that walks widget trees and flags `Text(<string literal>)` outside `lib/l10n/` and `test/`. Implementer can defer this if codegen + manual review is enough.

### H. Updates

- `context/code-standards.md`: i18n section already existed; mark it as enforced by this spec.
- `context/progress-tracker.md`: mark Spec 26 complete.

## Success Criteria

- [ ] `lib/l10n/en.arb` exists with all keys in Section D plus everything else swept from the codebase.
- [ ] `flutter pub get` regenerates `app_localizations.dart` automatically (gen_l10n runs as part of pub-get when `flutter.generate: true`).
- [ ] `import 'package:flutter_gen/gen_l10n/app_localizations.dart';` works wherever `AppLocalizations.of(context)` is called.
- [ ] `grep -RnE "Text\\('[A-Z][^']*'\\)" lib/features lib/widgets lib/screens` returns zero matches outside test fixtures (heuristic — implementer makes a final pass for false positives).
- [ ] App boots; every screen reads its strings from `AppLocalizations`.
- [ ] `flutter analyze` / test / format clean; offline gate clean.
- [ ] No invariant changed.

## References

- Skill: [`flutter-setup-localization`](../.agents/skills/flutter-setup-localization/SKILL.md)
- Official: <https://docs.flutter.dev/ui/internationalization>
- Follow-ups: future polish spec adds `es.arb` + RTL audit when the project goes multi-locale.
