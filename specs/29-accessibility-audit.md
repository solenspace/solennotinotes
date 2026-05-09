# 29 — accessibility-audit

## Goal

Run a **comprehensive accessibility audit** of the v1 surface — every screen, sheet, button, gesture — and fix the issues found. Audit is driven by the validated `accessibility-tester` subagent, with hand-checks on physical devices using VoiceOver (iOS) and TalkBack (Android). Output: a **green sweep** where every interactive element has an accessible name, every gesture has a non-gesture alternative, every state change announces appropriately, contrast meets WCAG AA, and reduced-motion preferences are respected. Bugs found mid-audit are fixed in this spec, not deferred.

This is the **v1 finish line spec**. After it ships, Notinotes is releasable.

## Dependencies

- Every prior spec — every screen we built passes through this audit.
- The `accessibility-tester` agent (already installed, validated).

## Agents & skills

**Pre-coding skills:**
- `flutter-fix-layout-issues` — layout breakage at maximum dynamic-type / large-text scaling.

**After-coding agents:**
- `accessibility-tester` — primary tool; produces the punch list this spec resolves.
- `ui-designer` — review the fix pass; verify focus rings + non-color signals + tooltip placement.
- `code-reviewer` — confirm the new a11y widget tests guard against future regressions.

## Design Decisions

### Audit methodology

1. **Automated pass**: invoke the `accessibility-tester` agent across the full `lib/features/` tree. Output a punch list.
2. **Manual pass on iOS**: VoiceOver enabled on a real iPhone. Walk every screen in the app. Fix anything VoiceOver reads as "button" or "image" without context.
3. **Manual pass on Android**: TalkBack enabled. Same walkthrough.
4. **Reduced motion**: enable in OS settings. Verify all animations halve duration or skip entirely. Verify the App Style theme transition (Spec 11) is graceful, not jarring.
5. **Contrast verification**: re-run the build-time contrast tests from Spec 10/11 and ensure no regressions.
6. **Touch target audit**: every tappable element ≥ 44×44 pt. Tools like Flutter's `Semantics` debug overlay help.
7. **Dynamic Type / OS text scale**: bump iOS Dynamic Type and Android font scale to maximum. Verify no text is cropped, no UI breaks.

### Categories of issues to fix

- **Missing semantic labels**: every `IconButton`, `Image`, custom-painted icon needs a label.
- **Long-press without alternative**: long-press to enter edit mode (Spec 5) — also expose a button. Long-press for tag picker — also expose a sheet entry.
- **Hold-to-record and hold-to-dictate** (Specs 13, 15) — already have tap-to-toggle fallbacks behind `MediaQuery.accessibleNavigation`; verify they activate correctly.
- **Color-only state**: edit-mode selection, pin badge, audio "playing" state — must have a non-color signal (icon, text, semantic).
- **Focus rings**: every focusable widget shows a 2px focus ring on keyboard nav. The token system has `tokens.colors.focus`; audit every `InkWell` / `GestureDetector` for missing focus state.
- **`Semantics(liveRegion: true)`** for streaming AI tokens (Spec 20) and Whisper transcripts (Spec 21) so screen readers announce updates.
- **Reduced motion**: `MediaQuery.disableAnimations` → halve `tokens.motion.*` values via the `NotiMotion` extension's `lerp`.
- **Ambient announcements**: when a note is shared / received / saved, the screen reader should announce ("Note sent", "Note received from alex"). Use `SemanticsService.announce(...)`.

### Hand-off to `accessibility-tester` agent

The agent's prompt for this run:

> Audit the Notinotes v1 surface for accessibility. Cover: VoiceOver / TalkBack labels on every interactive element, color contrast for body + UI chrome, touch target sizes, gesture alternatives for long-press / hold actions, focus rings for keyboard nav, dynamic type compatibility, reduced-motion behavior. Output a punch list grouped by feature folder. Cite WCAG 2.1 AA criterion numbers.

The agent's punch list lands in `progress-tracker.md` under a temporary "A11y debt" subsection; each item gets fixed in this spec then removed from the list.

### Manual test plan

The implementer runs through this plan on iPhone + Pixel:

| Surface | Critical checks |
|---------|-----------------|
| Home grid | Notes labeled by title + tag + date; pin/select buttons labeled; multi-select via long-press has tap-toggle alternative |
| Note editor | Toolbar buttons labeled; AI assist sheet (✦) labeled; share button labeled; theme paintbrush labeled |
| Capture: text | Keyboard accessible; auto-save announces |
| Capture: image | "Add image" button labeled; permission explainer reads aloud |
| Capture: audio | Long-press alternative is tap-to-toggle when a11y on; recording state announced |
| Capture: dictation (STT) | Same as audio |
| TTS read-aloud | Highlighted word announced; pause/stop buttons labeled |
| Theme overlay sheet | Three tabs labeled; swatch tiles labeled by palette name; pattern tiles labeled |
| Share sheet | Discovery list labeled; peer cards labeled by display name; transfer progress announced |
| Inbox | Sender chip labeled; accept/discard labeled; preview screen reads sender's tagline |
| AI assist sheet | Streaming tokens announced via liveRegion |
| Settings | Toggle states announced; AI download progress announced |

## Implementation

### A. Run the audit

Spawn the `accessibility-tester` agent with the prompt above. Receive the punch list.

### B. Fix every item

Each fix is a small, targeted edit. Examples:

```dart
// Before:
IconButton(icon: SvgPicture.asset('lib/assets/icons/brush.svg'), onPressed: ...);

// After:
IconButton(
  icon: SvgPicture.asset('lib/assets/icons/brush.svg'),
  tooltip: context.t.editor_paintbrush_tooltip,
  onPressed: ...,
);
```

```dart
// Before:
GestureDetector(onLongPress: _enterEditMode, child: ...)

// After:
Semantics(
  button: true,
  label: context.t.home_long_press_to_select,
  child: GestureDetector(
    onLongPress: _enterEditMode,
    onTap: MediaQuery.of(context).accessibleNavigation ? _enterEditMode : null,
    child: ...,
  ),
);
```

### C. Tests

Add Flutter widget tests under `test/widget/a11y/`:

- `home_a11y_test.dart` — verifies every `IconButton` has a non-empty `tooltip` or `Semantics(label: ...)`.
- `editor_a11y_test.dart` — same for editor toolbar.
- `share_a11y_test.dart` — peer cards have semantic labels.

These guard against regression: if a future spec adds a new icon button without a label, the test fails.

### D. Documentation

Update `context/ui-context.md`'s "Accessibility floor" subsection with the actual minimums proven by this audit:

- Body contrast ≥ 4.5:1 (already enforced by Spec 10/11).
- Touch targets ≥ 44×44 pt.
- Every interactive widget has a `Semantics` label or a `tooltip`.
- Long-press / hold gestures have non-gesture alternatives.
- Reduced motion respected via `tokens.motion.*` halving.
- AI streaming + Whisper transcription use `liveRegion`.

### E. Update `progress-tracker.md`

- Mark Spec 29 complete.
- Architecture decision 30: accessibility audit complete; a11y debt list resolved.
- Mark v1 ready for release candidate.

## Success Criteria

- [ ] `accessibility-tester` agent's punch list is empty after the fix pass.
- [ ] VoiceOver walkthrough on real iPhone: no "button, button, button" without labels; every gesture has an alternative.
- [ ] TalkBack walkthrough on real Android: same.
- [ ] Reduced motion enabled: editor open/close transition feels graceful, not abrupt.
- [ ] Dynamic Type at maximum: no text cropped, no overlapping widgets.
- [ ] All a11y widget tests pass.
- [ ] No invariant changed.

## References

- Skill: [`flutter-fix-layout-issues`](../.agents/skills/flutter-fix-layout-issues/SKILL.md) — for layout breakage at large dynamic type
- Agent: `accessibility-tester` — primary tool
- WCAG 2.1 AA: <https://www.w3.org/WAI/WCAG21/quickref/?versions=2.1&levels=aa>
- Apple HIG accessibility: <https://developer.apple.com/design/human-interface-guidelines/accessibility>
- Material Design accessibility: <https://m3.material.io/foundations/accessible-design/overview>

**This is the last spec of the v1 roadmap. After this lands, Notinotes is in release-candidate state.**
