# 14 — ink-drawing (v2 stub, deferred)

> **Status: deferred to v2.** This spec is a placeholder. No code is written against it. The roadmap originally listed ink/sketch capture as a v1 feature; UI-pattern research (see [progress-tracker.md](../context/progress-tracker.md)) recommended deferring it because it is roughly a quarter of total project effort by itself.

## Why deferred

A first-class ink note surface needs:

1. A pressure-sensitive canvas with proper Apple Pencil and Samsung S Pen tilt + pressure handling.
2. A storage format (vector strokes vs rasterized PNG vs hybrid).
3. Tool palette (pen / pencil / marker / highlighter / eraser), per-stroke color + thickness.
4. Layering / undo / redo with bounded memory.
5. Rendering performance at 120 Hz on ProMotion displays without dropping frames at large stroke counts.
6. Integration with the existing block editor — ink blocks coexist with text/audio/image blocks.
7. Cross-platform parity (iOS pencil > Android stylus implementations).

GoodNotes, Apple Notes ink, Procreate, Concepts each spent multiple person-years on these problems. Notinotes would do well in v1 to ship the modalities it already nails (text, todo, image, audio) and defer ink until v2. The mic icon (`lib/assets/icons/mic.svg`) and brush icon (`lib/assets/icons/brush.svg`) already in `lib/assets/icons/` keep the affordance in the visual language; the brush button in the editor toolbar can be used for the **noti theme overlay picker** (Spec 11) until ink lands.

## When to revisit

After Specs 15–29 ship and a v1 release candidate is in TestFlight / internal Android distribution. Add a v2 epic; this stub becomes the basis for a real Spec 14 (renumbered or kept).

## Open questions to resolve before drafting the real spec

1. Stroke storage: vector (`Path` + tool metadata) vs rasterized PNG vs hybrid (vector for editing, rasterized for sharing)?
2. Library choice: `flutter_drawing_board`, `signature`, `perfect_freehand`, hand-rolled `CustomPainter` + `RenderObject`?
3. Pressure / tilt API on Flutter — current state of `PointerDownEvent.pressure` reliability across iOS / Android.
4. Canvas size — fixed page (Letter / A4) vs infinite (Concepts-style) vs note-card-sized?
5. Sharing: ink notes via P2P need a serialization format the receiver renders identically. Rasterize-on-share or transmit strokes?

## References

- [`context/project-overview.md`](../context/project-overview.md) — "Multi-modal capture" goal mentions drawing; this stub flags the deferral.
- [11-noti-theme-overlay](11-noti-theme-overlay.md) — currently consumes the brush icon for the picker affordance; will need to free it up if ink ships in v2.
- Research note (in `progress-tracker.md`): "Sketch is out of scope for v1 — it requires its own canvas tool, pressure handling, and storage format; it's a quarter of project effort by itself. Defer like GoodNotes is its own app."
