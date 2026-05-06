# Notinotes — UI Context

## Aesthetic

Warm-paper indoor surface, tactile, low-distraction. The base background is **bone** (`#EDE6D6`) — a warm off-white that reads as paper, not gloss. Body ink is **narrow black** (`#1C1B1A`) — a warm-tinted near-black, never `#000000`. Custom hand-drawn pattern PNGs (waves, polygons, splashes, kaleidoscope, noise) live in `lib/assets/images/patterns/` and are part of the visual identity — they layer behind notes as low-opacity texture, never as flat color blocks.

Optional dark mode opt-in for outdoor or evening use; the canonical default is bone.

Type is **SF Pro Display** (already bundled). Body weight 400, semibold for emphasis, bold for headers. No decorative italics in chrome.

## Color tokens

Tokens are the *base* layer. Per-note `NotiThemeOverlay` (Spec 11) selectively replaces surface + accent + pattern + signature glyph.

The token values below are implemented in `lib/theme/tokens/` and consumed via `context.tokens.colors.<role>`. Raw `Color(0x…)` literals outside `lib/theme/tokens/` (and `lib/theme/curated_palettes.dart` for per-note swatches) are defects per [code-standards.md](code-standards.md) "Styling".

### Bone mode (canonical default)

#### Bones (warm off-white surfaces)
- `--bone-base`: `#EDE6D6` — primary surface, paper
- `--bone-lifted`: `#F5EFE2` — elevated surface (cards, sheets)
- `--bone-sunk`: `#E0D8C5` — recessed surface (dividers, notebook spines)
- `--bone-variant`: `#E8D8BD` — muted surface (read-only blocks)

#### Inks (narrow black, warm-tinted)
- `--ink-primary`: `#1C1B1A` — body text — **14.2:1** vs bone-base, AAA
- `--ink-secondary`: `#4A4640` — captions, metadata — **7.6:1**, AAA
- `--ink-subtle`: `#6B665D` — hints, placeholders — **4.7:1**, AA
- `--ink-barely`: `#9B958A` — disabled, dividers (chrome only, never body)

#### Accent (the Notinotes signature)
- `--accent-default`: `#4A8A7F` — muted teal — **5.2:1** vs bone-base, AA
- `--accent-muted`: `#6B9C92` — hover / disabled
- `--on-accent`: `#F5EFE2` — light ink for buttons painted with accent

#### Curated alternative accents (used in NotiThemeOverlay swatches)
- `slate` `#4A5F8F` — 4.9:1 vs bone-base
- `rose` `#A87878` — 4.6:1 vs bone-base
- `olive` `#6B7A4A` — 4.4:1 vs bone-base (large-text only on bone)
- `charcoal` `#3A3A3A` — 9.8:1 vs bone-base (secondary ink alternative)

#### State colors
- `--state-success`: `#5C7A4A` — paper-friendly moss
- `--state-warning`: `#A87B2D` — burnt amber
- `--state-error`: `#A0473A` — brick red
- `--state-info`: `#3F6B8A` — slate blue

#### Focus
- `--ring-focus`: `--accent-default` at 60% opacity, 2px

### Dark mode (opt-in)

Available in settings; honored by `MaterialApp.themeMode = system` if the device is in dark. Surface anchors:

- `--bg-base`: `#2D2D2D`
- `--bg-surface`: `#383838`
- `--bg-elevated`: `#454545`
- `--text-primary`: `#F2EFEA`
- `--text-secondary`: `#C9C2B6`
- `--text-muted`: `#8E867A`
- `--accent-default`: `#E5B26B` — warm parchment gold (the dark-mode accent counterpart)
- State colors adjusted for dark contrast — locked in [Spec 10](../specs/10-theme-tokens.md).

## Typography scale

- Display: 32 / 40
- Heading 1: 24 / 32
- Heading 2: 20 / 28
- Body: 16 / 24
- Body small: 14 / 20
- Label: 12 / 16
- Mono (for note timestamps, IDs): SF Mono fallback at body small

## Radii

- `sm`: 8 (chips, tag pills)
- `md`: 14 (cards, list items, the staggered grid tiles)
- `lg`: 22 (modals, bottom sheets)
- `pill`: 999 (action buttons in capture bar)

## Motion

- Fast: 120 ms, ease-out — chips, hover, focus
- Standard: 240 ms, ease-in-out — page transitions, sheets
- Calm: 480 ms, ease-out-cubic — note-card open, share success
- Pattern: 720 ms, ease-in-out-cubic — overlay swap inside the editor (App Style)
- Reduced motion (`MediaQuery.disableAnimations`) halves all durations.
- Use `flutter_animate` and `animations` (already in pubspec) — avoid custom `AnimationController` for one-offs.

Motion durations + curves are also reachable through `context.tokens.motion.{fast,standard,calm,pattern}` and `context.tokens.motion.{fast,standard,calm,pattern}Curve` for places where a token-routed read makes diffs easier to audit.

## NotiTheme override layer

Every note can carry its own [`NotiThemeOverlay`](../specs/11-noti-theme-overlay.md):

- **Surface palette** — replaces `--bone-base` + `--bone-lifted` + `--accent-default` per note. The 12 curated palettes (5 bone-first + 2 warm light + 5 dark; full list in Spec 11) are always WCAG-AA-safe.
- **Pattern key** — selects from the seven bundled pattern PNGs or `null`.
- **Signature accent** — single grapheme (emoji or glyph) shown as the note's signature.
- **Tagline** — short user-authored line carried with shared notes.

Patterns paint at full opacity in a 25–35% header band and at 8–18% behind body text, blended with a 16px feather. Receivers render the sender's overlay faithfully; the "from @sender" chip in the AppBar offers a one-tap "Convert to mine" escape hatch (Spec 11 §I).

## Pattern overlay readability

Four-defense system locked by Spec 11:

1. Build-time test — every curated palette passes `onSurface vs surface ≥ 4.5:1` and `onAccent vs accent ≥ 4.5:1`.
2. Pattern alpha clamp — body opacity ∈ [0.0, 0.18]; header opacity may go full but text never renders there.
3. Two-zone rendering — header band at full pattern, body fades via gradient mask.
4. Runtime APCA fallback — custom-color combos that fail body contrast auto-swap `onSurface` to the higher-contrast neighbor.

## Voice & copy

- Sentence case everywhere. No Title Case marketing text.
- Buttons are verbs: **Save**, **Share nearby**, **Discard**, **Accept**, **Transcribe**.
- Labels are nouns: **Tag**, **Reminder**, **Theme**, **Audio**.
- Errors say what + try: "Couldn't reach the device. Make sure both phones have Bluetooth on, then try again."
- No exclamation marks. No emoji in default copy (users may add their own).
- No second-person hand-holding: "Note saved" not "We've saved your note".

## Accessibility floor

- WCAG AA contrast minimum on text and primary chrome.
- All interactive elements have an accessible name (`Semantics` widget where needed).
- Touch targets ≥ 44×44 pt.
- Focus rings on every focusable widget; `focus-visible` style only.
- Reduce-motion respected via `MediaQuery.disableAnimations`.
- AI-streaming copy uses `Semantics(liveRegion: true)` for screen-reader announcement.
- Hold-to-record / hold-to-dictate gestures expose tap-to-toggle alternatives when `MediaQuery.accessibleNavigation` is true.

## Gestures and shortcuts

- Long-press on a note tile → multi-select mode (with tap alternative when accessible nav is on)
- Swipe right on a tile → archive
- Swipe left on a tile → delete (with undo snackbar, 5 s)
- Shake the device while editing → undo last destructive change
- Two-finger tap on home → toggle bone / dark mode
- Pull-down on home → quick capture sheet
- Pull-up on note → tag picker

## Layout patterns

- **Home**: staggered grid (kept from current code via `flutter_staggered_grid_view`) showing notes as cards. Each card paints its NotiThemeOverlay pattern at low opacity and renders a 12 px swatch dot in the top-right (Tot-style) — the note's accent or signature glyph.
- **Capture bar**: bottom-anchored, modal with quick actions (text · todo · image · audio).
- **Note editor**: full-screen, with the note's NotiThemeOverlay applied via App Style chrome (AppBar, status bar, sheets all retint). Toolbar at top, AI assist + share + paintbrush at bottom.
- **Share-nearby sheet**: discovers peers; each peer card shows their accent chip + display name; chunked progress while transferring; footer reads "Sent over Bluetooth — never through the internet."
- **Received inbox**: list view with preview thumbnails; tap to preview in sender's NotiThemeOverlay; accept / discard. AppBar carries "from @sender" chip with one-tap "Convert to mine".
- **Mobile-first; tablet adaptation deferred** to a layout spec.

## Things that are NOT in scope here

- Pixel-precise tokens beyond what's listed — Spec 10 locks every Material 3 ColorScheme role.
- Light-mode pattern luminance tuning — patterns are tuned for dark surfaces; bone-mode pattern variants are a polish-spec follow-up.
- Tablet / foldable adaptive layouts.
- Animation easing curves beyond the four named tiers.
