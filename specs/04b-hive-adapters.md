# 04b — hive-adapters

> **Status: stub.** This spec is a placeholder. Body is drafted in conversation with the user when we're ready to migrate from JSON-string storage to typed Hive CE adapters. **Do not implement against this stub.**

## Goal

Replace the current `String`-keyed-to-JSON-encoded-`String` storage in the `notes_v2` Hive box with **typed Hive CE adapters** for `Note` (and any embedded types: `DisplayMode`, gradient, todo entries, blocks). Make `Note` immutable (final fields + `copyWith`). Generate adapters via `build_runner`. Ship a one-time read-side migration that detects legacy JSON-string entries on first open and rewrites them as typed objects, then bumps the box name to `notes_v3`.

## Dependencies

- [04-repository-layer](04-repository-layer.md) — `HiveNotesRepository` is the only Hive consumer for notes; the migration is contained inside that one class.

## Open questions to resolve before drafting

1. Make `Note` fully immutable (`final` everywhere) or accept some mutability for the editor's in-flight changes?
2. Use `freezed` for codegen vs hand-written `copyWith` + `==` / `hashCode`?
3. Migration trigger: on every app start, or only when `notes_v2` is detected and `notes_v3` is empty?
4. What happens to entries that fail to decode during migration — quarantine to a sidecar box, log + skip, or hard fail?
5. Do we drop the legacy `blocks` vs `content`/`todoList`/`imageFile` duality during migration, or carry it through to a later editor refactor?

## Implementation, success criteria, and references

To be drafted with the user when this spec becomes the active unit. Reference [04-repository-layer](04-repository-layer.md), [`context/architecture.md`](../context/architecture.md) invariants 5 and 7, and the `dart-flutter-patterns` skill before drafting.
