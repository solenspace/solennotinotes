# 11 — noti-theme-overlay

## Goal

Ship the **per-note visual overlay** that makes Notinotes distinctive: each note can carry its own palette, pattern, accent glyph, and tagline; that overlay flows into the editor's chrome (AppBar, status bar, sheets) when the note is open; and it travels with the note when it's shared peer-to-peer in a later spec. The picker is a **bottom sheet with three tabs** (Palette / Pattern / Accent) invoked from a paintbrush in the editor toolbar. Contrast guardrails block visually unreadable combinations at pick time. The home note-card list renders a small **Tot-style swatch dot** so each card carries its overlay's signature even at thumbnail size. Receivers of shared notes see a "from @sender" chip with a one-tap "convert to my style" escape hatch — the chip is wired in this spec; the share-receive plumbing lands in the share-flow spec (24).

This is the first of the **UI-heavy specs** and was preceded by a UI-pattern research pass — see [progress-tracker.md](../context/progress-tracker.md) "Research notes" and the references at the bottom of this spec.

## Dependencies

- [09-noti-identity](09-noti-identity.md) — the user's `NotiIdentity` provides the *default* overlay applied to a note when it's first created and the *baseline* the picker opens to.
- [10-theme-tokens](10-theme-tokens.md) — `NotiColors`, `NotiPatternBackdrop`, `NotiSignature` ThemeExtensions are what the overlay copies and patches; `lib/theme/curated_palettes.dart` is the swatch source.
- [06-bloc-migration-editor](06-bloc-migration-editor.md) — `NoteEditorBloc` events dispatch overlay changes.

## Agents & skills

**Pre-coding skills:**
- `flutter-build-responsive-layout` — bottom sheet sizing, `DraggableScrollableSheet` usage, tab transitions.
- `flutter-fix-layout-issues` — overflow / unbounded-height guards on the picker tabs.
- `flutter-add-widget-test` — picker sheet widget tests.
- `flutter-add-widget-preview` — preview the picker tabs in isolation while iterating.

**After-coding agents:**
- `ui-designer` — visual review of the picker sheet, App Style chrome, Tot-style swatch dots, from-sender chip; verify the curated palettes feel intentional, not generic.
- `accessibility-tester` — semantic labels on every swatch tile, contrast guardrails verified on the picker tabs themselves, keyboard navigation works.
- `flutter-expert` — audit `AnimatedTheme` placement, status-bar tinting, route-pop animation; verify the overlay-derived `Theme` boundary doesn't leak into sibling routes.

## Design Decisions

### Picker shape — informed by research

Top note-takers (Bear, Notion, Apple Notes, Tot, Day One, Anytype, Drafts, Things, Standard Notes) **almost universally do not ship per-note theming**. Craft is the only mature precedent, and it uses a sidebar sheet on macOS that does not translate to mobile. We borrow the pattern that *does* fit mobile: **Notion's "Add cover / Add icon" inline affordance**, but extended into a three-tab bottom sheet because we offer three customization axes.

- **Bottom sheet, not full-screen.** Lets the user keep the note visible behind the sheet so changes preview live. Drag-handle at top, snap heights at `0.5` and `0.92` of screen height (Flutter `DraggableScrollableSheet`).
- **Three tabs**: `Palette` · `Pattern` · `Accent`. Single sheet, segmented control at top. No separate screens — Craft's sidebar pattern bloats mobile.
- **Picker invocation**: a paintbrush icon in the editor toolbar (already in `lib/assets/icons/brush.svg`). Long-press resets the note to the user's `NotiIdentity` default.
- **Curated swatches first**, custom HSL second. The Palette tab opens to a 4-column grid of **12 starter palettes** (each is 4 swatches: surface / surface-variant / accent / on-accent). A "Custom" tile at the end opens a contrast-validated HSL picker that disables swatches whose accent contrast against `onAccent` falls below 4.5:1.
- **Pattern tab** shows the seven bundled `NotiPatternKey` options (waves / wavesUnregulated / polygons / kaleidoscope / splashes / noise / upScaleWaves) as 100px tiles, plus a "None" tile at index 0. Each tile renders the pattern at the *body* opacity (8–18%) on top of the currently-selected palette's surface, so the user sees the actual outcome.
- **Accent tab** is a `TextField` constrained to one user-perceived character via the `characters` package, plus a horizontally-scrolling row of suggested accents (☼, ✦, ⌘, △, ❍, ✕, ☾, ◆, ✿, ★, ❀, ◯). Tapping a suggestion fills the field; the user can type any single grapheme (including emoji).
- **Tagline picker is NOT in this sheet.** Tagline is a per-user identity field (set on the user-info screen from Spec 09), not per-note. The overlay just *carries* the identity's tagline so receivers see it on shared notes.

### App Style — chrome reflects the note

When a note is open in the editor, the chrome around it inherits the overlay:

- `AppBar` background = `overlay.colors.surfaceVariant`.
- `SystemUiOverlayStyle` (status bar tint) matches `overlay.colors.surface` luminance.
- Editor toolbar (`NoteAppBar` widget) uses `overlay.colors.surfaceElevated`.
- `BottomSheet` for the picker itself uses `overlay.colors.surface` so it *also* inherits — the picker tints to the note's palette.
- When the user pops the editor route, the chrome animates back to the base theme over `tokens.motion.pattern` (720ms) — long enough to feel intentional, short enough to feel responsive.

The mechanism: wrap the editor route's subtree in `Theme(data: baseTheme.copyWith(extensions: overlay.applyTo(baseTheme.extensions)))`. ThemeExtension `lerp` makes the route-pop transition smooth automatically; we don't write custom animation code.

### Contrast guardrails

WCAG AA = 4.5:1 for normal text, 3:1 for large text (≥ 18.5px bold or ≥ 24px). Since WCAG provides no formal method against patterned/textured backgrounds, we layer four defenses:

1. **Build-time validation of curated palettes.** A test in `test/theme/curated_palettes_contrast_test.dart` asserts every starter palette passes `onSurface vs surface ≥ 4.5:1` and `onAccent vs accent ≥ 4.5:1`. If anyone adds a swatch set, the build fails until the swatches are tuned.
2. **Pattern alpha clamp.** `NotiPatternBackdrop.bodyOpacity` is clamped to `[0.0, 0.18]` at construction; values higher than 18% reject the build (assert in `assertNotiPatternBackdrop`). The header band may go full opacity because text never sits there.
3. **Two-zone rendering.** Patterns paint at `headerOpacity` in the top `headerHeightFraction` of every note card and editor canvas, and at `bodyOpacity` below. A `LinearGradient` mask blends the two zones over a 16px feather.
4. **Runtime APCA fallback.** When a custom-color combo is selected (the "Custom" tile path), we run an APCA contrast check at apply-time. If `Lc < 60` (rough APCA equivalent of WCAG AA at body sizes), we swap `overlay.colors.onSurface` to whichever of `surface`'s neighbors (`grey050` for dark surfaces, `grey950` for light) gives the highest Lc. The user never sees the unreadable state.

The custom HSL picker also disables swatches in real time: each swatch tile runs the contrast check; failing tiles render at 30% opacity with a "low readability" tooltip on long-press.

### Tot-style swatch dot in the note list

Each note card on the home screen carries a 12px dot in its top-right corner painted with the note's `overlay.colors.accent`. If the note has no overlay (default = user's identity overlay), the dot is `accentMuted`. If the note was *received* from another user (share inbox spec), the dot is replaced by a 14px accent-glyph rendered in `overlay.colors.accent`. Tapping the dot in multi-select mode toggles overlay-edit mode for the selection. (Multi-select overlay editing — applying one overlay to N notes — is its own follow-up spec; for Spec 11 the dot is read-only outside multi-select.)

### Receiver chrome ("from @sender" chip)

When a note's overlay carries a `NotiSignature.fromIdentityId` value that doesn't match the current user's `NotiIdentity.id`, the editor renders a small chip in the AppBar:

```
┌──────────────────────────────────────┐
│  ←   [accent]  from @alex     ▾      │
└──────────────────────────────────────┘
```

The chip is a `PopupMenu` with two options: "Keep their style" (no-op) and "Convert to mine" (replaces the note's overlay with the current user's identity overlay, persists). This is the unreadability escape hatch + the social signal in one element. The chip wires up here; its data source (the `fromIdentityId` field) populates from the share-receive flow in a later spec — until then, the chip never renders because the field is null on every locally-created note.

### Backward compatibility with the existing schema

The `Note` model from the imported codebase has scattered overlay-shaped fields: `colorBackground`, `fontColor`, `patternImage` (string), `gradient`, `hasGradient`. We **do not delete** these in Spec 11 — Spec 04b (typed Hive adapters) will replace them with a single `NotiThemeOverlay` value field. For now, this spec adds:

- An extension method `Note.toOverlay()` that derives a `NotiThemeOverlay` from the existing fields.
- Setters on `NoteEditorBloc` that dispatch through new overlay-aware events (`OverlayPaletteChanged`, `OverlayPatternChanged`, `OverlayAccentChanged`) **and continue to populate the legacy fields** so Hive storage stays compatible.
- A migration TODO logged in `progress-tracker.md` for Spec 04b: "Replace `Note.{colorBackground, fontColor, patternImage, gradient, hasGradient}` with a single `Note.overlay: NotiThemeOverlay`."

The existing six legacy events (`BackgroundColorChanged`, `PatternImageSet`, `PatternImageRemoved`, `FontColorChanged`, `GradientChanged`, `GradientToggled`) are **kept and deprecated** with a one-line annotation pointing to the three new overlay events. They forward to the same handler internally so old call sites keep working until the editor's widgets are fully refactored to dispatch the new events.

### What's explicitly NOT in this spec

- **Sketch / ink overlay surface** — out of scope for v1 per research; deferred indefinitely.
- **Multi-select bulk overlay edit** — separate spec.
- **Per-note custom font** — `WritingFont` stays a global setting (not part of overlay) because typography choice belongs to the *reader* on share-receive, per the research's identity-as-metadata principle.
- **Overlay export / share format encoding** — Spec 23 (share-payload codec) defines the wire format. This spec only defines the in-memory model.
- **Light-mode tuning of patterns** — patterns currently look best on dark surfaces (the research recommends pre-processing PNGs to L\* 15–35). Light-mode pattern luminance tuning is its own spec.

## Implementation

### A. Files to create

```
lib/theme/
├── noti_theme_overlay.dart        ← the model
├── curated_palettes.dart          ← 12 starter palettes (file created in Spec 10; populated here)
└── contrast.dart                  ← APCA + WCAG helpers + clampForReadability

lib/features/note_editor/widgets/
├── overlay_picker_sheet.dart      ← the 3-tab bottom sheet
├── overlay_palette_grid.dart
├── overlay_pattern_grid.dart
├── overlay_accent_picker.dart
└── from_sender_chip.dart          ← AppBar chip; invisible until share spec wires data

lib/features/home/widgets/
└── note_overlay_dot.dart          ← Tot-style swatch dot for the home grid

test/theme/
├── noti_theme_overlay_test.dart
├── curated_palettes_contrast_test.dart   ← build-time AA contrast check
└── contrast_test.dart                    ← APCA helper tests
```

### B. `lib/theme/noti_theme_overlay.dart`

```dart
import 'dart:ui';

import 'package:noti_notes_app/theme/tokens/color_tokens.dart';
import 'package:noti_notes_app/theme/tokens/pattern_backdrop_tokens.dart';
import 'package:noti_notes_app/theme/tokens/signature_tokens.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';

/// A note's per-note visual overlay. Selectively replaces the base theme's
/// surface + accent + pattern + signature when the note is rendered.
class NotiThemeOverlay {
  const NotiThemeOverlay({
    required this.surface,
    required this.surfaceVariant,
    required this.accent,
    required this.onAccent,
    this.onSurface,           // null = derive from surface via contrast helper
    this.patternKey,
    this.signatureAccent,
    this.signatureTagline = '',
    this.fromIdentityId,
  });

  final Color surface;
  final Color surfaceVariant;
  final Color accent;
  final Color onAccent;

  /// Foreground for body text. If null, the theme assembler derives a
  /// safe value via `clampForReadability(surface)`.
  final Color? onSurface;

  final NotiPatternKey? patternKey;
  final String? signatureAccent;
  final String signatureTagline;

  /// Identity id of the note's authoring user. Null for locally-authored
  /// notes; non-null on notes received via share. Drives the `from @sender`
  /// chip in the editor AppBar.
  final String? fromIdentityId;

  NotiThemeOverlay copyWith({
    Color? surface,
    Color? surfaceVariant,
    Color? accent,
    Color? onAccent,
    Color? onSurface,
    NotiPatternKey? patternKey,
    String? signatureAccent,
    String? signatureTagline,
    String? fromIdentityId,
    bool clearPattern = false,
    bool clearAccentChar = false,
    bool clearOrigin = false,
  }) {
    return NotiThemeOverlay(
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      onSurface: onSurface ?? this.onSurface,
      patternKey: clearPattern ? null : (patternKey ?? this.patternKey),
      signatureAccent:
          clearAccentChar ? null : (signatureAccent ?? this.signatureAccent),
      signatureTagline: signatureTagline ?? this.signatureTagline,
      fromIdentityId:
          clearOrigin ? null : (fromIdentityId ?? this.fromIdentityId),
    );
  }

  /// Applies this overlay on top of a base [NotiColors] extension, returning
  /// a new extension with surface/accent slots replaced. Other slots (state
  /// colors, divider, focus) are preserved.
  NotiColors applyToColors(NotiColors base) {
    return base.copyWith(
      surface: surface,
      surfaceVariant: surfaceVariant,
      surfaceElevated: Color.lerp(surface, base.surfaceElevated, 0.4)!,
      surfaceMuted: Color.lerp(surface, base.surfaceMuted, 0.6)!,
      onSurface: onSurface ?? _deriveOnSurface(surface),
      accent: accent,
      onAccent: onAccent,
      focus: accent,
    );
  }

  NotiPatternBackdrop applyToPatternBackdrop(NotiPatternBackdrop base) {
    return base.copyWith(
      patternKey: patternKey?.name,
      bodyOpacity: patternKey == null ? 0.0 : 0.12,
      headerOpacity: patternKey == null ? 0.0 : 1.0,
      headerHeightFraction: patternKey == null ? 0.0 : 0.30,
    );
  }

  NotiSignature applyToSignature(NotiSignature base) {
    return base.copyWith(
      accent: signatureAccent ?? base.accent,
      tagline: signatureTagline.isEmpty ? base.tagline : signatureTagline,
    );
  }

  Color _deriveOnSurface(Color s) {
    // Quick WCAG luminance fallback; precise APCA path lives in contrast.dart.
    final luminance = (0.299 * s.r + 0.587 * s.g + 0.114 * s.b) / 255.0;
    return luminance < 0.5 ? const Color(0xFFF7F5F2) : const Color(0xFF0F0F0F);
  }
}
```

### C. `lib/theme/curated_palettes.dart`

```dart
import 'dart:ui';

import 'noti_theme_overlay.dart';
import 'noti_pattern_key.dart';

/// Twelve starter palettes. Each one is a built [NotiThemeOverlay] template
/// (no pattern, no accent — the user picks those independently from their
/// own tabs in the picker). Validated at build time by
/// `test/theme/curated_palettes_contrast_test.dart`.
const List<NotiThemeOverlay> kCuratedPalettes = [
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFF4A8A7F),
    onAccent: Color(0xFFF5EFE2),
  ),
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFF4A5F8F),
    onAccent: Color(0xFFF5EFE2),
  ),
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFFA87878),
    onAccent: Color(0xFFF5EFE2),
  ),
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFF6B7A4A),
    onAccent: Color(0xFFF5EFE2),
  ),
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFF3A3A3A),
    onAccent: Color(0xFFF5EFE2),
  ),
  NotiThemeOverlay(
    surface: Color(0xFFF5EFE2),
    surfaceVariant: Color(0xFFF8F2E7),
    accent: Color(0xFFB8704A),
    onAccent: Color(0xFFFFFFFF),
  ),
  NotiThemeOverlay(
    surface: Color(0xFFE8D8BD),
    surfaceVariant: Color(0xFFEDE2C9),
    accent: Color(0xFF6B5B4A),
    onAccent: Color(0xFFF8F2E7),
  ),
  NotiThemeOverlay(
    surface: Color(0xFF2D2D2D),
    surfaceVariant: Color(0xFF383838),
    accent: Color(0xFFE5B26B),
    onAccent: Color(0xFF1A1A1A),
  ),
  NotiThemeOverlay(
    surface: Color(0xFF1F2A35),
    surfaceVariant: Color(0xFF2A3744),
    accent: Color(0xFF7BAFD4),
    onAccent: Color(0xFF0E1822),
  ),
  NotiThemeOverlay(
    surface: Color(0xFF1F2620),
    surfaceVariant: Color(0xFF2A332C),
    accent: Color(0xFF8FA66F),
    onAccent: Color(0xFF111712),
  ),
  NotiThemeOverlay(
    surface: Color(0xFF2A1F26),
    surfaceVariant: Color(0xFF362A32),
    accent: Color(0xFFD37FA0),
    onAccent: Color(0xFF180F14),
  ),
  NotiThemeOverlay(
    surface: Color(0xFF0F0F0F),
    surfaceVariant: Color(0xFF1A1A1A),
    accent: Color(0xFFEDEDED),
    onAccent: Color(0xFF0F0F0F),
  ),
];

/// Palette names, parallel-indexed with `kCuratedPalettes`. Used by the picker
/// for accessibility labels and the from-sender chip for analytics-free display.
const List<String> kCuratedPaletteNames = [
  'Bone',
  'Bone + Slate',
  'Bone + Rose',
  'Bone + Olive',
  'Bone + Charcoal',
  'Cream',
  'Sand',
  'Charcoal',
  'Slate',
  'Moss',
  'Plum',
  'Onyx',
];
```

### D. `lib/theme/contrast.dart`

```dart
import 'dart:math';
import 'dart:ui';

/// WCAG 2.x relative luminance.
double luminance(Color c) {
  double channel(double v) {
    final n = v / 255.0;
    return n <= 0.03928 ? n / 12.92 : pow((n + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.x contrast ratio.
double contrastRatio(Color a, Color b) {
  final la = luminance(a);
  final lb = luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// WCAG AA gate for body text.
bool isAccessibleBody(Color fg, Color bg) => contrastRatio(fg, bg) >= 4.5;

/// WCAG AA gate for large text (≥ 18.5pt bold or ≥ 24pt).
bool isAccessibleLarge(Color fg, Color bg) => contrastRatio(fg, bg) >= 3.0;

/// Returns whichever of (light, dark) has the highest contrast against [bg].
/// Used as a runtime fallback when a custom-color combo would otherwise
/// fail body-text contrast.
Color clampForReadability(
  Color bg, {
  Color light = const Color(0xFFF7F5F2),
  Color dark = const Color(0xFF0F0F0F),
}) {
  return contrastRatio(light, bg) >= contrastRatio(dark, bg) ? light : dark;
}
```

### E. The picker bottom sheet — `overlay_picker_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_accent_picker.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_palette_grid.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_pattern_grid.dart';
import 'package:noti_notes_app/theme/tokens.dart';

class OverlayPickerSheet extends StatefulWidget {
  const OverlayPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.tokens.shape.lg),
        ),
      ),
      builder: (_) => const OverlayPickerSheet(),
    );
  }

  @override
  State<OverlayPickerSheet> createState() => _OverlayPickerSheetState();
}

class _OverlayPickerSheetState extends State<OverlayPickerSheet>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          const _DragHandle(),
          TabBar(
            controller: _tabs,
            indicatorColor: tokens.colors.accent,
            labelColor: tokens.colors.onSurface,
            unselectedLabelColor: tokens.colors.onSurfaceMuted,
            tabs: const [
              Tab(text: 'Palette'),
              Tab(text: 'Pattern'),
              Tab(text: 'Accent'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                OverlayPaletteGrid(scroll: scroll),
                OverlayPatternGrid(scroll: scroll),
                OverlayAccentPicker(scroll: scroll),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: context.tokens.colors.divider,
        borderRadius: BorderRadius.circular(context.tokens.shape.pill),
      ),
    );
  }
}
```

`OverlayPaletteGrid`, `OverlayPatternGrid`, `OverlayAccentPicker` — full code follows the same pattern: `BlocBuilder<NoteEditorBloc, NoteEditorState>` reads the current `note.toOverlay()`, dispatches `OverlayPaletteChanged` / `OverlayPatternChanged` / `OverlayAccentChanged` events on tap. Implementer writes them; samples in this spec are sufficient guidance.

### F. New `NoteEditorBloc` events

Add three events that supersede the legacy six:

```dart
final class OverlayPaletteChanged extends NoteEditorEvent {
  const OverlayPaletteChanged(this.overlay);
  final NotiThemeOverlay overlay;
  @override
  List<Object?> get props => [overlay];
}

final class OverlayPatternChanged extends NoteEditorEvent {
  const OverlayPatternChanged(this.patternKey);
  final NotiPatternKey? patternKey;
  @override
  List<Object?> get props => [patternKey];
}

final class OverlayAccentChanged extends NoteEditorEvent {
  const OverlayAccentChanged(this.accent);
  final String? accent;
  @override
  List<Object?> get props => [accent];
}

final class OverlayResetToIdentityDefault extends NoteEditorEvent {
  const OverlayResetToIdentityDefault();
}

final class OverlayConvertToMine extends NoteEditorEvent {
  const OverlayConvertToMine();
}
```

Handlers update the **legacy fields** on the Note for storage compatibility, mirroring the overlay shape:

```dart
Future<void> _onOverlayPaletteChanged(
  OverlayPaletteChanged event,
  Emitter<NoteEditorState> emit,
) async {
  final note = state.note;
  if (note == null) return;
  note.colorBackground = event.overlay.surface;
  note.fontColor = event.overlay.onSurface ?? clampForReadability(event.overlay.surface);
  // (gradient cleared so the palette is the only background source)
  note.gradient = null;
  note.hasGradient = false;
  await _repository.save(note);
  emit(state.copyWith(note: note));
}
```

The legacy events (`BackgroundColorChanged`, `FontColorChanged`, `PatternImageSet`, `PatternImageRemoved`, `GradientChanged`, `GradientToggled`) gain `@Deprecated('use OverlayPaletteChanged / OverlayPatternChanged; remove in spec 04b')` and forward into the new handlers (extracting the `NotiThemeOverlay` from the legacy color/gradient/pattern args).

### G. Editor screen — App Style chrome

Wrap the editor's body subtree in a `Theme` widget that layers the overlay on top of the base theme:

```dart
@override
Widget build(BuildContext context) {
  return BlocBuilder<NoteEditorBloc, NoteEditorState>(
    buildWhen: (prev, next) => prev.note?.toOverlay() != next.note?.toOverlay()
        || prev.status != next.status,
    builder: (ctx, state) {
      final base = Theme.of(ctx);
      final overlay = state.note?.toOverlay();
      final themed = overlay == null
          ? base
          : base.copyWith(extensions: <ThemeExtension<dynamic>>[
              overlay.applyToColors(ctx.tokens.colors),
              ctx.tokens.text,
              ctx.tokens.motion,
              ctx.tokens.shape,
              ctx.tokens.elevation,
              overlay.applyToPatternBackdrop(ctx.tokens.patternBackdrop),
              overlay.applyToSignature(ctx.tokens.signature),
            ]);
      return AnimatedTheme(
        data: themed,
        duration: ctx.tokens.motion.pattern,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: themed.extension<NotiColors>()!.surface,
            statusBarIconBrightness:
                themed.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
          ),
          child: Scaffold(
            appBar: NoteAppBar(
              fromSenderChip: state.note?.toOverlay().fromIdentityId == null
                  ? null
                  : const FromSenderChip(),
            ),
            body: const _EditorBody(),
          ),
        ),
      );
    },
  );
}
```

### H. `note_overlay_dot.dart` — home grid signature

```dart
class NoteOverlayDot extends StatelessWidget {
  const NoteOverlayDot({super.key, required this.overlay});
  final NotiThemeOverlay overlay;

  @override
  Widget build(BuildContext context) {
    final glyph = overlay.signatureAccent;
    if (glyph != null) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          glyph,
          style: TextStyle(color: overlay.accent, fontSize: 14),
        ),
      );
    }
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: overlay.accent,
        shape: BoxShape.circle,
      ),
    );
  }
}
```

Mounted in `lib/features/home/widgets/note_card.dart` at top-right.

### I. `from_sender_chip.dart`

```dart
class FromSenderChip extends StatelessWidget {
  const FromSenderChip({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NoteEditorBloc, NoteEditorState>(
      buildWhen: (a, b) => a.note?.toOverlay().fromIdentityId
          != b.note?.toOverlay().fromIdentityId,
      builder: (ctx, state) {
        final overlay = state.note?.toOverlay();
        final fromId = overlay?.fromIdentityId;
        if (fromId == null) return const SizedBox.shrink();
        // Display name lookup against received-inbox metadata lands in
        // the share-receive spec; until then we render the id truncated.
        final shortId = fromId.substring(0, 6);
        return PopupMenuButton<String>(
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'keep', child: Text('Keep their style')),
            const PopupMenuItem(value: 'mine', child: Text('Convert to mine')),
          ],
          onSelected: (v) {
            if (v == 'mine') {
              ctx.read<NoteEditorBloc>().add(const OverlayConvertToMine());
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (overlay!.signatureAccent != null) ...[
                  Text(
                    overlay.signatureAccent!,
                    style: TextStyle(color: overlay.accent),
                  ),
                  const SizedBox(width: 6),
                ],
                Text('from $shortId', style: ctx.tokens.text.label),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

### J. `Note.toOverlay()` extension

In `lib/models/note.dart` (or a sibling extensions file), add:

```dart
extension NoteToOverlay on Note {
  NotiThemeOverlay toOverlay() {
    return NotiThemeOverlay(
      surface: colorBackground,
      surfaceVariant: Color.lerp(colorBackground, fontColor, 0.08)!,
      accent: hasGradient && gradient != null
          ? gradient!.colors.last
          : Color.lerp(colorBackground, fontColor, 0.6)!,
      onAccent: colorBackground,
      onSurface: fontColor,
      patternKey: NotiPatternKey.fromString(patternImage),
      // signatureAccent + tagline + fromIdentityId not stored on legacy Note;
      // they default to null until Spec 04b adds the dedicated overlay field.
    );
  }
}
```

### K. Update `context/architecture.md`

Add to **Storage model**:

> Per-note overlay fields are currently scattered across `Note.{colorBackground, fontColor, patternImage, gradient, hasGradient}`. The `Note.toOverlay()` extension synthesizes a `NotiThemeOverlay`. Spec 04b will replace these scattered fields with a single `Note.overlay: NotiThemeOverlay` value.

Add to **Data flow examples**:

> **Open editor → render with note's overlay**: route push mounts `NoteEditorBloc` → BLoC emits `ready` with `Note` → editor `BlocBuilder` calls `note.toOverlay()` → wraps subtree in `AnimatedTheme(data: base.copyWith(extensions: overlay.applyTo(...)))` → `AppBar`, `Scaffold`, sheets, status bar all reflect the overlay → user pops route → `AnimatedTheme` interpolates back to the base theme over `tokens.motion.pattern`.

### L. Update `context/ui-context.md`

Replace the "NotiTheme override layer" section with:

> Each note carries a [`NotiThemeOverlay`](../lib/theme/noti_theme_overlay.dart): surface palette + pattern key + signature accent + signature tagline + (for received notes) origin identity id. The overlay is selected via a three-tab bottom sheet (Palette / Pattern / Accent) invoked from the paintbrush button in the editor toolbar. Curated swatches first; custom HSL gated behind a contrast check. Patterns paint at full opacity in a 25–35% header band and at 8–18% behind body text, blended with a 16px feather. The home grid renders a 12px swatch dot per card so the signature reads at thumbnail size. When the note's overlay carries a non-null `fromIdentityId`, the editor AppBar shows a "from @sender" chip with a one-tap "convert to mine" escape hatch.

Add a new "Pattern overlay readability" subsection naming the four guardrails from this spec's Design Decisions.

### M. Update `context/progress-tracker.md`

- Mark Spec 11 complete.
- Add **Architecture decisions** entry 19: per-note overlay system landed; bottom-sheet picker; App Style chrome propagation; contrast guardrails; Tot-style swatch dots in home grid; from-sender chip wired (data populates in share spec).
- Append to **Open questions**:
  > 12. Pattern luminance pre-processing — the bundled pattern PNGs are tuned for `#2D2D2D` surfaces. Patterns over light-mode surfaces (Sand, Paper, Frost palettes) currently render too contrasty. Light-mode pattern variants are deferred to a polish spec.

## Success Criteria

- [ ] All files in Section A exist; the picker mounts via `OverlayPickerSheet.show(context)` from the toolbar paintbrush.
- [ ] `flutter analyze` exits 0; offline gate clean; format clean.
- [ ] `flutter test` exits 0 with:
  - `test/theme/curated_palettes_contrast_test.dart` — every palette in `kCuratedPalettes` passes `onAccent vs accent ≥ 4.5:1` and `clampForReadability(surface) vs surface ≥ 4.5:1`.
  - `test/theme/contrast_test.dart` — covers `contrastRatio`, `isAccessibleBody`, `clampForReadability` for known reference pairs.
  - `test/theme/noti_theme_overlay_test.dart` — covers `applyToColors`, `applyToPatternBackdrop`, `applyToSignature`, `_deriveOnSurface`, and the round-trip `Note.toOverlay()` for legacy notes.
  - `test/features/note_editor/bloc/note_editor_bloc_test.dart` (extended) — `OverlayPaletteChanged`, `OverlayPatternChanged`, `OverlayAccentChanged`, `OverlayResetToIdentityDefault`, `OverlayConvertToMine` each verified.
- [ ] **Manual smoke**:
  - Open a note → tap paintbrush → sheet rises → tap a curated palette → editor surface, AppBar, status bar all retint over ~720ms → pop route → home retints back.
  - Pattern tab → tap "Polygons" → editor body shows the pattern at low opacity behind text and at full opacity in the top header band.
  - Accent tab → type "★" → save → home card top-right shows "★" in accent color (instead of the dot).
  - Long-press paintbrush → overlay resets to user's `NotiIdentity` defaults.
  - On a freshly-shared note (mocked by setting `fromIdentityId` in a debug-only fixture): AppBar shows "from xxxxxx" chip → tap → "Convert to mine" → overlay swaps and chip disappears.
- [ ] No `Color(0x…)` literals introduced outside `lib/theme/`.
- [ ] `lib/features/note_editor/widgets/note_style_sheet.dart` (the legacy sheet) is **removed**; the toolbar references `OverlayPickerSheet.show` instead.
- [ ] The home grid renders the swatch dot / accent glyph for every note.
- [ ] No invariant in `context/architecture.md` is changed.
- [ ] No new runtime dependencies. (The overlay model is plain Dart; the picker uses only existing widgets.)

## References

- [09-noti-identity](09-noti-identity.md), [10-theme-tokens](10-theme-tokens.md)
- [`context/ui-context.md`](../context/ui-context.md) — rewritten by this spec
- [`context/project-overview.md`](../context/project-overview.md) — "noti identity travels with shared notes" goal
- Skill: [`flutter-build-responsive-layout`](../.agents/skills/flutter-build-responsive-layout/SKILL.md), [`flutter-fix-layout-issues`](../.agents/skills/flutter-fix-layout-issues/SKILL.md)
- Skill: [`flutter-add-widget-test`](../.agents/skills/flutter-add-widget-test/SKILL.md), [`flutter-add-widget-preview`](../.agents/skills/flutter-add-widget-preview/SKILL.md) — preview the picker tabs in isolation
- Agent: `ui-designer` — invoke after Section E (the picker sheet) to audit the visual design + curated-palette set
- Agent: `accessibility-tester` — invoke against the contrast + APCA + readable-fallback paths; verify VoiceOver / TalkBack labels on the picker
- Agent: `flutter-expert` — invoke after Section G (App Style chrome) to audit `AnimatedTheme` placement, status bar tinting, and route-pop animation
- **Research sources** (read before drafting): Tot 2.0 (MacStories), Bear FAQ + 2.7 release notes, Day One journal headers blog, Craft Document Styling, Notion page icons & covers, Drafts action bar docs, WebAIM contrast, Flutter ThemeExtension API, Flutter M3 token update.
- Follow-up: Spec 04b retires the scattered legacy overlay fields on `Note`. The share-payload codec spec wires `fromIdentityId` real data and shows a real display name in the chip.
