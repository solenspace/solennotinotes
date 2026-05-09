# Notinotes — Claude Code instructions

This is an offline-first Flutter notes app. The full project context lives in [context/](context/). Before any implementation, read these files **in order**:

1. [context/project-overview.md](context/project-overview.md) — product definition, goals, in/out of scope
2. [context/architecture.md](context/architecture.md) — system structure, stack, storage model, **12 invariants**
3. [context/ui-context.md](context/ui-context.md) — theme tokens, voice & copy, NotiTheme overlay, accessibility, gestures
4. [context/code-standards.md](context/code-standards.md) — Dart/BLoC/repository discipline, forbidden imports, file org
5. [context/ai-workflow-rules.md](context/ai-workflow-rules.md) — spec-driven workflow, scoping, protected files
6. [context/progress-tracker.md](context/progress-tracker.md) — current phase, completed work, open questions

## Hard rules

- **No cloud, ever.** This app makes zero network calls in production. See `architecture.md` invariant 1 and `code-standards.md` "Forbidden imports". The single authorized exception is the LLM / Whisper model download (Spec 19), allowlisted by file path.
- **Re-read the Invariants section** of `architecture.md` before any code change.
- **The v1 roadmap is fully drafted** at [specs/](specs/) — 30 numbered files (01–29 + 04b stub). Implement sequentially.
- **Update [context/progress-tracker.md](context/progress-tracker.md)** in the same commit as the unit's last change. The other five context files are append-only and timeless.
- **Never invent** Hive box names, BLoC class names that imply unspecified behavior, P2P payload fields, AI model identifiers, NotiTheme palette enum values, or permission strings. Resolve in context first or log under "Open questions".

## Branch and PR convention (gitflow)

- `main` is the production branch. Never commit or push to it directly.
- `development` is the integration branch. Never commit to it directly either — it only advances via merged PRs.
- **Before implementing a new spec or feature**, branch off `development`:
  ```
  git checkout development && git pull --ff-only
  git checkout -b feature/<short-slug>
  ```
  Use a slug that names the spec or feature (e.g. `feature/01-lint-and-format-hardening`, `feature/04-repository-layer`).
- Open a PR `feature/<slug>` → `development` when the spec's verification checklist is green.
- **After a PR is merged, delete the branch — both remote and local — in the same step**, so stale branches don't pile up:
  ```
  gh pr merge <number> --merge --delete-branch
  git checkout development && git pull --ff-only
  git branch -D feature/<slug>     # deletes the local copy
  ```
  Treat the merge as incomplete until both branches are gone. The same applies to `chore/<slug>` and `hotfix/<slug>` branches.
- Releases land on `main` via a PR `development` → `main`. No feature branches target `main` directly.
- Hotfix branches (`hotfix/<slug>`) may branch off `main` and merge back to both `main` and `development` — only when production is broken.

## Implementation protocol

1. Read [`context/progress-tracker.md`](context/progress-tracker.md) to find the **active spec**.
2. Read the active spec from start to finish.
3. Run the **pre-coding skills** listed in the spec's `## Agents & skills` section.
4. Re-read [`context/architecture.md`](context/architecture.md) "Invariants" section.
5. Implement the spec's `## Implementation` sections in order.
6. Run the **after-coding agents** listed in the spec's `## Agents & skills` section.
7. Run all `## Verification` commands in the spec.
8. Update [`context/progress-tracker.md`](context/progress-tracker.md) in the same commit as the spec's last code change.
9. The next active spec becomes the next-higher-numbered spec on disk.

Implement sequentially; do not skip ahead unless the current spec is explicitly blocked and the user authorizes a re-order.

## Verification before declaring a unit done

- `flutter analyze` clean
- `flutter test` green
- `dart format --set-exit-if-changed -l 100 lib/ test/` clean
- App boots on iOS simulator + Android emulator
- Forbidden-imports grep is clean (see `code-standards.md`)
- `progress-tracker.md` updated

## Skills

Validated Flutter/Dart agent skills are installed under [.agents/skills/](.agents/skills/) (canonical) with symlinks at [.claude/skills/](.claude/skills/). Restore from `skills-lock.json` with `pnpm dlx skills experimental_install`.

## Agents

Five validated subagents from [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) live at [.claude/agents/](.claude/agents/): `flutter-expert`, `code-reviewer`, `test-automator`, `ui-designer`, `accessibility-tester`. Invoke via the Task tool when their description matches the work — see [AGENTS.md](AGENTS.md) for details. Project policy: agents are validated, not invented.
