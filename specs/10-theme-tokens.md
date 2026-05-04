# 10 — theme-tokens

## Goal

Establish the **two-layer design-token system** that the rest of the app reads from: a primitive layer of raw const values (colors, radii, durations, type scale) and a semantic `ThemeExtension` layer that names them by role (`surface`, `onSurface`, `accent`, `accentMuted`, …). The `MaterialApp` builds its `ThemeData` from these tokens via `ColorScheme.fromSeed`, with semantic overrides applied. The legacy `lib/theme/theme_provider.dart` ChangeNotifier is migrated to a `ThemeCubit` backed by a new `SettingsRepository`, and **`package:provider` is removed from `pubspec.yaml`** since `ThemeProvider` was its last consumer. After this spec, every widget, screen, and BLoC reads colors via `context.tokens.colors.*`, fonts via `context.tokens.text.*`, motion via `context.tokens.motion.*` — never via hardcoded `Color(0x…)` literals or magic numbers.

The token system is designed to be **overlaid by a per-note `NotiThemeOverlay`** in Spec 11. `ThemeExtension`'s `lerp` and `copyWith` give us free animated transitions between the base theme and a note's overlay.

## Dependencies

- [03-project-structure-migration](03-project-structure-migration.md) — `lib/theme/` exists as a top-level shared root.
- [07-bloc-migration-search-and-user](07-bloc-migration-search-and-user.md) — repository + cubit conventions.
- [08-notes-legacy-removal](08-notes-legacy-removal.md) — `Notes` legacy is gone; `ThemeProvider` is the last `ChangeNotifier` standing.
- [09-noti-identity](09-noti-identity.md) — the `NotiIdentity.signaturePalette` is the user's *default* palette; this spec defines the palette **structure** that Spec 11's overlay then customizes per note.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — token-system layering, `ThemeExtension` patterns, `ColorScheme.fromSeed` usage.

**After-coding agents:**
- `flutter-expert` — audit the token assembly: `ColorScheme.fromSeed` overrides are surgical, not wholesale; `ThemeExtension.lerp` produces continuous transitions.
- `ui-designer` — visual fidelity check after the `Color(0x…)` sweep; eyeball the bone-mode rendering against pre-spec screenshots.
- `accessibility-tester` — confirm WCAG AA on every `onSurface vs surface`, `onAccent vs accent` pair across both bone and dark modes.

## Design Decisions

### Token philosophy (informed by 2025 Flutter design-system research)

- **Two layers, not one.** Primitives (raw consts) → semantics (named roles). Components consume only semantics; primitives are private to the token files.
- **Split files at ~300 LOC.** One file per token category: `primitives.dart`, `color_tokens.dart`, `typography_tokens.dart`, `motion_tokens.dart`, `shape_tokens.dart`, `elevation_tokens.dart`. `app_theme.dart` assembles them into `ThemeData`.
- **`ThemeExtension` for everything Spec 11 will overlay.** Specifically: `NotiColors`, `NotiPatternBackdrop`, `NotiSignature`. Other token categories (`typography`, `motion`, `shape`, `elevation`) are global; the user's noti or a per-note overlay only ever changes color, pattern, and signature accent.
- **`ColorScheme.fromSeed` for the M3 baseline**, then surgical overrides for `surface`, `surfaceVariant`, `primary`, `onSurface`. Avoids hand-rolling 30+ M3 color roles and surviving every M3 token-update Flutter ships.
- **Type-safe access via `context.tokens.*`.** A single `BuildContextX.tokens` extension method returns a `Tokens` aggregator object that exposes `colors`, `text`, `motion`, `shape`, `elevation`. Keeps call sites short (`context.tokens.colors.surface`) without 5-line `Theme.of(context).extension<…>()!` chains.
- **Skip codegen tools (`theme_tailor`) for v1.** ~25 tokens; codegen pays off above 50.
- **No hardcoded color literals outside `primitives.dart`.** A new `custom_lint` rule enforces this in Spec 02's plugin (extension to `forbidden_imports_lint`); for now, this spec adds the rule scaffold and the rule itself ships disabled-with-warning until the existing legacy theme files are converted.

### Color decisions (locked in `context/ui-context.md` rewrite)

- **Bone-first.** Every token has a bone-mode value (canonical) and a dark-mode value (opt-in via settings). Bone is the canonical default; the user opts into dark via a setting or system preference.
- **Concrete tokens** (replaces the previous dark-only baseline): bone surface `#EDE6D6`, narrow-black ink `#1C1B1A`, accent `#4A8A7F`. WCAG-AA verified at build time (Section H test).
- **Curated alternative accents on bone**: `slate #4A5F8F`, `rose #A87878`, `olive #6B7A4A`, `charcoal #3A3A3A`. All pass 4.4:1+ vs `#EDE6D6` (olive at large-text only).
- **No Material You dynamic color** at MVP. `ColorScheme.fromSeed` runs against a static seed (the user's `signaturePalette[2]`, the accent swatch). System wallpaper has no input. We can add `DynamicColorBuilder` later behind a settings toggle.

### Typography

- **`AppTypography` (the existing enum at `lib/theme/app_typography.dart`)** is preserved as the writing-font selector for the editor body. Its three options (`inter`, `serif`, `mono`) become the `editorBody` token set.
- **Chrome typography is fixed**: SF Pro Display (already bundled). Chrome = AppBar, sheets, toolbar, captions, labels.
- **Type scale** follows Material 3 type-scale roles (display, headline, title, body, label) with concrete sizes locked in `typography_tokens.dart`.

### Motion

- **Four named tiers** (matches `context/ui-context.md`):
  - `fast` (120ms, easeOut) — chips, hover, focus
  - `standard` (240ms, easeInOut) — page transitions, sheets
  - `calm` (480ms, easeOutCubic) — note-card open, share success
  - `pattern` (720ms, easeInOutCubic) — overlay swap inside the editor
- **Reduced motion** halves all durations when `MediaQuery.disableAnimations == true`.

### Shape

- `pill: 999`, `lg: 22`, `md: 14`, `sm: 8`, `xs: 4`. Per `ui-context.md`. Locked.

### Elevation

- Five steps mapped to dark-mode surface tints (no shadows on `#2D2D2D` baseline; we lighten the surface instead, M3-style):
  - `e0` — base (no tint)
  - `e1` — +4% lightness (cards)
  - `e2` — +8% (lifted cards on hover)
  - `e3` — +12% (sheets, modals)
  - `e4` — +16% (dialogs)

### Settings repository + cubit

- **`SettingsRepository`** (abstract) + **`HiveSettingsRepository`** (concrete) at `lib/repositories/settings/`. Reads/writes `settings_v2` Hive box (the same one `ThemeProvider` uses; preserves user data).
- Settings stored: `themeMode`, `writingFont`, `appThemeColor`. The `appThemeColor` field is **deprecated by Spec 11** because per-note overlays subsume it; for Spec 10 we keep it (back-compat) and Spec 11 retires it.
- **`ThemeCubit`** owns the active `ThemeData` derivation. Listens to `NotiIdentityRepository.watch()` so when the user changes their `signaturePalette`, the app theme rebuilds.
- **Streams over events**: `ThemeCubit` is a Cubit (no events), reacts to identity + settings changes via two stream subscriptions, emits `ThemeState`.

### Package:provider removal

- After the migration, `lib/main.dart` no longer wraps anything in `ChangeNotifierProvider` or `MultiProvider`. The `provider` package is removed from `pubspec.yaml`. The `import 'package:provider/provider.dart';` lines disappear from every consumer.

## Implementation

### A. New files

```
lib/theme/
├── tokens/
│   ├── primitives.dart            ← raw const values (private to tokens/)
│   ├── color_tokens.dart          ← NotiColors ThemeExtension
│   ├── typography_tokens.dart     ← NotiText ThemeExtension
│   ├── motion_tokens.dart         ← NotiMotion ThemeExtension
│   ├── shape_tokens.dart          ← NotiShape ThemeExtension
│   ├── elevation_tokens.dart      ← NotiElevation ThemeExtension
│   ├── pattern_backdrop_tokens.dart ← NotiPatternBackdrop ThemeExtension (consumed by Spec 11)
│   └── signature_tokens.dart      ← NotiSignature ThemeExtension (consumed by Spec 11)
├── app_theme.dart                 ← assembles ThemeData (rewritten)
├── tokens.dart                    ← Tokens aggregator + BuildContextX extension
└── noti_pattern_key.dart          ← (already exists from Spec 09)

lib/repositories/settings/
├── settings_repository.dart
└── hive_settings_repository.dart

lib/features/settings/cubit/
├── theme_cubit.dart
└── theme_state.dart
```

### B. Files deleted

```
lib/theme/theme_provider.dart        ← migrated to ThemeCubit
lib/theme/notes_color_palette.dart   ← values absorbed into primitives.dart + color_tokens.dart
lib/theme/app_tokens.dart            ← values absorbed into primitives.dart + color_tokens.dart
```

`lib/theme/app_typography.dart` (the `WritingFont` enum) is **kept** — it's the runtime user choice for editor body font. Its content moves into `typography_tokens.dart` if it makes sense; otherwise it stays as a sibling.

### C. `lib/theme/tokens/primitives.dart`

```dart
import 'dart:ui';

class _ColorPrimitives {
  static const boneBase = Color(0xFFEDE6D6);
  static const boneLifted = Color(0xFFF5EFE2);
  static const boneSunk = Color(0xFFE0D8C5);
  static const boneVariant = Color(0xFFE8D8BD);

  static const inkPrimary = Color(0xFF1C1B1A);
  static const inkSecondary = Color(0xFF4A4640);
  static const inkSubtle = Color(0xFF6B665D);
  static const inkBarely = Color(0xFF9B958A);

  static const accentDefault = Color(0xFF4A8A7F);
  static const accentMuted = Color(0xFF6B9C92);
  static const onAccent = Color(0xFFF5EFE2);

  static const accentSlate = Color(0xFF4A5F8F);
  static const accentRose = Color(0xFFA87878);
  static const accentOlive = Color(0xFF6B7A4A);
  static const accentCharcoal = Color(0xFF3A3A3A);

  static const grey900 = Color(0xFF1A1A1A);
  static const grey800 = Color(0xFF2D2D2D);
  static const grey750 = Color(0xFF383838);
  static const grey700 = Color(0xFF454545);
  static const grey300 = Color(0xFFC9C2B6);
  static const grey200 = Color(0xFFD9D9D9);
  static const grey050 = Color(0xFFF2EFEA);
  static const darkAccent = Color(0xFFE5B26B);

  static const success = Color(0xFF5C7A4A);
  static const warning = Color(0xFFA87B2D);
  static const error = Color(0xFFA0473A);
  static const info = Color(0xFF3F6B8A);
}

class _RadiusPrimitives {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 22.0;
  static const pill = 999.0;
}

class _DurationPrimitives {
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 240);
  static const calm = Duration(milliseconds: 480);
  static const pattern = Duration(milliseconds: 720);
}

class _TextSizes {
  static const display = 32.0;
  static const headlineLg = 24.0;
  static const headlineMd = 20.0;
  static const titleLg = 18.0;
  static const bodyLg = 16.0;
  static const bodyMd = 14.0;
  static const label = 12.0;
}

// Typed exports so other token files can import explicit names.
class Primitives {
  static const colors = _ColorPrimitives();
  static const radius = _RadiusPrimitives();
  static const duration = _DurationPrimitives();
  static const text = _TextSizes();

  const Primitives._();
}
```

### D. `lib/theme/tokens/color_tokens.dart`

```dart
import 'package:flutter/material.dart';

import 'primitives.dart';

@immutable
class NotiColors extends ThemeExtension<NotiColors> {
  const NotiColors({
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.onSurfaceSubtle,
    required this.accent,
    required this.accentMuted,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.divider,
    required this.focus,
  });

  final Color surface;
  final Color surfaceVariant;
  final Color surfaceMuted;
  final Color surfaceElevated;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color onSurfaceSubtle;
  final Color accent;
  final Color accentMuted;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color divider;
  final Color focus;

  static const bone = NotiColors(
    surface: _ColorPrimitives.boneBase,
    surfaceVariant: _ColorPrimitives.boneLifted,
    surfaceMuted: _ColorPrimitives.boneSunk,
    surfaceElevated: _ColorPrimitives.boneLifted,
    onSurface: _ColorPrimitives.inkPrimary,
    onSurfaceMuted: _ColorPrimitives.inkSecondary,
    onSurfaceSubtle: _ColorPrimitives.inkSubtle,
    accent: _ColorPrimitives.accentDefault,
    accentMuted: _ColorPrimitives.accentMuted,
    onAccent: _ColorPrimitives.onAccent,
    success: _ColorPrimitives.success,
    warning: _ColorPrimitives.warning,
    error: _ColorPrimitives.error,
    info: _ColorPrimitives.info,
    divider: _ColorPrimitives.boneSunk,
    focus: _ColorPrimitives.accentDefault,
  );

  static const dark = NotiColors(
    surface: _ColorPrimitives.grey800,
    surfaceVariant: _ColorPrimitives.grey750,
    surfaceMuted: _ColorPrimitives.grey900,
    surfaceElevated: _ColorPrimitives.grey700,
    onSurface: _ColorPrimitives.grey050,
    onSurfaceMuted: _ColorPrimitives.grey300,
    onSurfaceSubtle: _ColorPrimitives.inkBarely,
    accent: _ColorPrimitives.darkAccent,
    accentMuted: _ColorPrimitives.accentMuted,
    onAccent: _ColorPrimitives.grey900,
    success: _ColorPrimitives.success,
    warning: _ColorPrimitives.warning,
    error: _ColorPrimitives.error,
    info: _ColorPrimitives.info,
    divider: _ColorPrimitives.grey700,
    focus: _ColorPrimitives.darkAccent,
  );

  @override
  NotiColors copyWith({
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceMuted,
    Color? surfaceElevated,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? onSurfaceSubtle,
    Color? accent,
    Color? accentMuted,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? divider,
    Color? focus,
  }) {
    return NotiColors(
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      onSurfaceSubtle: onSurfaceSubtle ?? this.onSurfaceSubtle,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      divider: divider ?? this.divider,
      focus: focus ?? this.focus,
    );
  }

  @override
  NotiColors lerp(ThemeExtension<NotiColors>? other, double t) {
    if (other is! NotiColors) return this;
    return NotiColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      onSurfaceSubtle: Color.lerp(onSurfaceSubtle, other.onSurfaceSubtle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
    );
  }
}
```

### E. The other token extensions

`typography_tokens.dart`, `motion_tokens.dart`, `shape_tokens.dart`, `elevation_tokens.dart`, `pattern_backdrop_tokens.dart`, `signature_tokens.dart` follow the same `ThemeExtension<T>` pattern with `copyWith` and `lerp`. The full file content for each is mechanical given the values listed in Sections "Typography / Motion / Shape / Elevation" of Design Decisions; the implementer writes them directly.

`pattern_backdrop_tokens.dart` (consumed by Spec 11) has the shape:

```dart
class NotiPatternBackdrop extends ThemeExtension<NotiPatternBackdrop> {
  const NotiPatternBackdrop({
    required this.patternKey,            // null = no pattern
    required this.bodyOpacity,           // 0.08–0.18 by design
    required this.headerOpacity,         // 1.0 in the header band, 0 below
    required this.headerHeightFraction,  // 0.25–0.35; the band that takes the pattern at full opacity
  });
  // ...lerp/copyWith
}
```

Default for the base theme: `NotiPatternBackdrop(patternKey: null, bodyOpacity: 0, headerOpacity: 0, headerHeightFraction: 0)`. Spec 11's overlay swaps these.

`signature_tokens.dart` carries `accent` (the user/note's signature emoji or glyph) and `tagline` (string). Default: empty.

### F. `lib/theme/tokens.dart` — aggregator

```dart
import 'package:flutter/material.dart';

import 'tokens/color_tokens.dart';
import 'tokens/elevation_tokens.dart';
import 'tokens/motion_tokens.dart';
import 'tokens/pattern_backdrop_tokens.dart';
import 'tokens/shape_tokens.dart';
import 'tokens/signature_tokens.dart';
import 'tokens/typography_tokens.dart';

class Tokens {
  const Tokens({
    required this.colors,
    required this.text,
    required this.motion,
    required this.shape,
    required this.elevation,
    required this.patternBackdrop,
    required this.signature,
  });

  final NotiColors colors;
  final NotiText text;
  final NotiMotion motion;
  final NotiShape shape;
  final NotiElevation elevation;
  final NotiPatternBackdrop patternBackdrop;
  final NotiSignature signature;
}

extension BuildContextX on BuildContext {
  /// Type-safe access to the active token set. Reads ThemeExtensions from
  /// `Theme.of(this)`. Throws if any extension is missing — that's a setup
  /// bug, not a runtime condition.
  Tokens get tokens {
    final theme = Theme.of(this);
    return Tokens(
      colors: theme.extension<NotiColors>()!,
      text: theme.extension<NotiText>()!,
      motion: theme.extension<NotiMotion>()!,
      shape: theme.extension<NotiShape>()!,
      elevation: theme.extension<NotiElevation>()!,
      patternBackdrop: theme.extension<NotiPatternBackdrop>()!,
      signature: theme.extension<NotiSignature>()!,
    );
  }
}
```

### G. `lib/theme/app_theme.dart` — assembly

```dart
import 'package:flutter/material.dart';

import 'tokens/color_tokens.dart';
import 'tokens/elevation_tokens.dart';
import 'tokens/motion_tokens.dart';
import 'tokens/pattern_backdrop_tokens.dart';
import 'tokens/shape_tokens.dart';
import 'tokens/signature_tokens.dart';
import 'tokens/typography_tokens.dart';

class AppTheme {
  static ThemeData bone({Color? seedAccent, NotiText? text}) {
    final colors = NotiColors.bone.copyWith(
      accent: seedAccent ?? NotiColors.bone.accent,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: Brightness.light,
    ).copyWith(
      surface: colors.surface,
      onSurface: colors.onSurface,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      error: colors.error,
    );
    return _build(scheme: scheme, colors: colors, text: text ?? NotiText.bone);
  }

  static ThemeData dark({Color? seedAccent, NotiText? text}) {
    final colors = NotiColors.dark.copyWith(
      accent: seedAccent ?? NotiColors.dark.accent,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface: colors.surface,
      onSurface: colors.onSurface,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      error: colors.error,
    );
    return _build(scheme: scheme, colors: colors, text: text ?? NotiText.dark);
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required NotiColors colors,
    required NotiText text,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surface,
      extensions: [
        colors,
        text,
        NotiMotion.standard,
        NotiShape.standard,
        NotiElevation.dark,
        NotiPatternBackdrop.none,
        NotiSignature.empty,
      ],
    );
  }
}
```

### H. `SettingsRepository` + `ThemeCubit`

Repository follows the Spec 04 pattern; box `settings_v2`, three keys (`themeMode`, `writingFont`, `signaturePalette`-derived seed). The `appThemeColor` enum is migrated as follows: on first read after this spec, if `appThemeColor` is set in the box, copy its `Color` value into the user's `NotiIdentity.signaturePalette[2]` (accent slot) IF that slot is still default; then clear the legacy key. After this one-shot, the `appThemeColor` key is dead.

`ThemeCubit` listens to:
1. `SettingsRepository.watch()` → `themeMode`, `writingFont`
2. `NotiIdentityRepository.watch()` → `signaturePalette` (drives the seed accent)

Emits `ThemeState(themeMode: …, boneTheme: …, darkTheme: …)`. `MaterialApp` reads `state.themeMode`, the bone theme (canonical), and the dark theme (opt-in); the framework picks based on `themeMode` and the system brightness when `ThemeMode.system`.

### I. `lib/main.dart` — final shape

```dart
final settingsRepository = HiveSettingsRepository();
final notesRepository = HiveNotesRepository();
final notiIdentityRepository = HiveNotiIdentityRepository();
await settingsRepository.init();
await notesRepository.init();
await notiIdentityRepository.init();

runApp(
  MultiRepositoryProvider(
    providers: [
      RepositoryProvider<SettingsRepository>.value(value: settingsRepository),
      RepositoryProvider<NotesRepository>.value(value: notesRepository),
      RepositoryProvider<NotiIdentityRepository>.value(value: notiIdentityRepository),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (ctx) => ThemeCubit(
            settingsRepository: ctx.read<SettingsRepository>(),
            identityRepository: ctx.read<NotiIdentityRepository>(),
          )..start(),
        ),
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
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (ctx, state) => MaterialApp(
          themeMode: state.themeMode,
          theme: state.boneTheme,
          darkTheme: state.darkTheme,
          home: const HomeScreen(),
        ),
      ),
    ),
  ),
);
```

### J. Sweep the codebase for hardcoded colors and magic numbers

Find-and-replace pass after the tokens land. Every `Color(0x…)`, `BorderRadius.circular(N)`, `Duration(milliseconds: N)`, hardcoded `TextStyle` outside `tokens/` is a defect.

Tooling-assisted: run `grep -RnE "Color\\(0x[0-9A-Fa-f]+\\)" lib/ | grep -v "lib/theme/tokens/"` — every hit gets refactored to `context.tokens.colors.<role>`. Same for radii, durations, type sizes.

The legacy `lib/theme/notes_color_palette.dart` file (deleted in Section B) had a list of swatches consumed by the per-note color-picker UI. Those swatches move into `lib/theme/curated_palettes.dart` as the **starter palette set** that Spec 11 will use in its picker. This spec creates the file but doesn't use it.

### K. `pubspec.yaml` cleanup

Remove from `dependencies:`:

```yaml
  provider: ^6.1.5
```

Run `flutter pub get`. `dart fix --apply` cleans up any leftover unused `import 'package:provider/provider.dart';` lines.

### L. Forbidden-imports gate extension

Append `package:provider` to `scripts/.forbidden-imports.txt`:

```
# Banned post-Spec-10 (last consumer migrated to BLoC + RepositoryProvider).
package:provider
```

This catches future regressions if anyone adds a `provider` dep again.

### M. Update `context/architecture.md`, `context/code-standards.md`, `context/ui-context.md`, `context/progress-tracker.md`

- `architecture.md` Stack table: add `lib/theme/tokens/` as the canonical token home. Add `SettingsRepository` to the cross-cutting repos. No invariant change.
- `code-standards.md` "Styling": replace the existing styling section with:
  > All UI reads colors / type / motion / shape / elevation from `context.tokens.*`. Hardcoded `Color(0x…)` literals, magic radii, magic durations, and hand-rolled `TextStyle` outside `lib/theme/tokens/` are defects. The token system layers are: primitives (private to `tokens/`) → semantics (`ThemeExtension<T>` per category) → access (`context.tokens.<category>.<role>`). Per-note overlays (Spec 11) clone and patch the active `NotiColors` / `NotiPatternBackdrop` / `NotiSignature` extensions; no other extensions are ever overridden.
- `ui-context.md` Color tokens section: replace the provisional values with the new dark/light token set (Sections C and D). Update the notes about gestures/shortcuts to reference `context.tokens.motion.*` durations.
- `progress-tracker.md`:
  - Mark Spec 10 complete.
  - Add architecture decision 18: **two-layer design tokens with ThemeExtension; `package:provider` removed; ThemeCubit listens to identity + settings; per-note overlay system designed in Spec 11**.
  - Resolve open question on the signature accent color (now `accent500` = `#E5B26B`, with the user's `signaturePalette[2]` taking precedence).

## Success Criteria

- [ ] All files in Section A exist and the files in Section B are deleted.
- [ ] `lib/main.dart` no longer imports `package:provider` and contains no `ChangeNotifierProvider`/`MultiProvider`.
- [ ] `pubspec.yaml` no longer lists `provider` in `dependencies:`.
- [ ] `scripts/.forbidden-imports.txt` includes `package:provider`.
- [ ] `flutter analyze` exits 0; offline gate clean (including the new `package:provider` ban); format clean.
- [ ] `flutter test` exits 0 with at least:
  - `test/theme/tokens/color_tokens_test.dart` — verifies `NotiColors.dark.copyWith(accent: x).accent == x`, `lerp` produces continuous output, every dark-mode color pair (`onSurface`/`surface`, `onAccent`/`accent`, `onSurfaceMuted`/`surface`) passes WCAG AA contrast (build-time check using a small Dart helper).
  - `test/repositories/settings/hive_settings_repository_test.dart` — temp-dir Hive box round-trip.
  - `test/features/settings/cubit/theme_cubit_test.dart` — cubit reacts to identity stream changes by emitting a new `ThemeState` whose `darkTheme.colorScheme.primary` matches the new accent.
- [ ] **Manual smoke**: app boots; visually identical to pre-spec rendering except where the new token values intentionally tightened the palette (verify by side-by-side screenshot of home + editor against pre-spec build); changing `signaturePalette` in user_info reflects in the AppBar accent within one second.
- [ ] `grep -RnE "Color\\(0x[0-9A-Fa-f]+\\)" lib/ | grep -v "lib/theme/tokens/"` — only legitimate exceptions: `app_theme.dart` (M3 `fromSeed` plumbing) and any colors inside generated `.g.dart` files. Anything else is fixed in this spec.
- [ ] `grep -RnE "BorderRadius\\.circular\\([0-9]" lib/ | grep -v "lib/theme/"` — zero unintentional matches.
- [ ] `lib/theme/curated_palettes.dart` exists with at least 12 starter swatch sets, ready for Spec 11.
- [ ] `lib/theme/theme_provider.dart` and `lib/theme/notes_color_palette.dart` deleted.
- [ ] No invariant in `context/architecture.md` is changed.

## References

- [`context/architecture.md`](../context/architecture.md), [`context/code-standards.md`](../context/code-standards.md), [`context/ui-context.md`](../context/ui-context.md) — all updated by this spec
- [09-noti-identity](09-noti-identity.md) — `NotiIdentity.signaturePalette` is the seed source
- [11-noti-theme-overlay](11-noti-theme-overlay.md) — the consumer of `NotiPatternBackdrop` + `NotiSignature` + `NotiColors.copyWith`
- Skill: [`flutter-theming-apps`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md) (theming guidance lives across the architecture + layouts skills since `flutter-theming-apps` was deprecated upstream)
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Skill: [`dart-flutter-patterns`](../.agents/skills/dart-flutter-patterns/SKILL.md)
- Agent: `ui-designer` — invoke after Section J (the hardcoded-color sweep) to audit the resulting visual fidelity
- Agent: `accessibility-tester` — invoke against the contrast tests in Section H to confirm WCAG AA across both light + dark
- Research sources: [Flutter M3 token update](https://docs.flutter.dev/release/breaking-changes/material-design-3-token-update), [ThemeExtension API](https://api.flutter.dev/flutter/material/ThemeExtension-class.html), [vibe-studio Flutter design system](https://vibe-studio.ai/insights/building-a-reusable-design-system-in-flutter-with-theme-extensions), [WebAIM contrast](https://webaim.org/articles/contrast/)
- Follow-up: [11-noti-theme-overlay](11-noti-theme-overlay.md) — uses every ThemeExtension declared here
