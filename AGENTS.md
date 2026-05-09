# Notinotes — Agents

All project instructions live in [CLAUDE.md](CLAUDE.md), which points to the six-file context system in [context/](context/).

## Skill locations

- Canonical: [.agents/skills/](.agents/skills/) — populated by `pnpm dlx skills add` calls
- Symlinks for Claude Code: [.claude/skills/](.claude/skills/) — auto-created by the `pnpm dlx skills add` CLI

Both directories surface the same `SKILL.md` files. Editing a skill in either location is a no-op for the symlink consumer; treat `.agents/skills/` as the source of truth.

## Reproducing the skill set

On a fresh clone:

```bash
pnpm dlx skills experimental_install   # restores from skills-lock.json
```

To list what's installed:

```bash
pnpm dlx skills list
```

## Custom agents

Ten validated agents are installed at [.claude/agents/](.claude/agents/), all sourced from [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) (a curated public collection, not invented for this project):

**Core five (used per spec):**
- [`flutter-expert`](.claude/agents/flutter-expert.md) — Flutter 3+ architecture, state management, animations, platform features, performance
- [`code-reviewer`](.claude/agents/code-reviewer.md) — pre-merge review for quality, security, maintainability
- [`test-automator`](.claude/agents/test-automator.md) — test framework design, scripts, CI integration
- [`ui-designer`](.claude/agents/ui-designer.md) — visual + interaction design, design systems
- [`accessibility-tester`](.claude/agents/accessibility-tester.md) — WCAG compliance, assistive tech support

**Cross-spec auditors (invoked at trigger specs):**
- [`architect-reviewer`](.claude/agents/architect-reviewer.md) — guards the 12 invariants across spec boundaries; trigger after Specs 02, 04, 09, 22
- [`security-auditor`](.claude/agents/security-auditor.md) — owns zero-network + P2P payload surface; trigger after Specs 19, 22–25
- [`performance-engineer`](.claude/agents/performance-engineer.md) — on-device LLM + Hive memory/latency budgets; trigger after Specs 06, 18, 19, 21
- [`dependency-manager`](.claude/agents/dependency-manager.md) — vets every new pkg against the no-cloud invariant; trigger before any spec adding a dep
- [`refactoring-specialist`](.claude/agents/refactoring-specialist.md) — keeps drift bounded across 30 sequential specs; trigger after Specs 10, 20, 29

Project policy: **no invented agents.** New agents are added only when sourced from a validated public collection or repository. To add one:

```bash
curl -fsSL "https://raw.githubusercontent.com/VoltAgent/awesome-claude-code-subagents/main/categories/<category>/<agent>.md" \
  -o ".claude/agents/<agent>.md"
```

## When to invoke an agent

Each spec's `## Agents & skills` section names which skills to load before coding and which agents to dispatch after coding. Pattern:

- **Skills are loaded BEFORE coding** to refresh conventions. Read the SKILL.md, internalize, write code.
- **Agents are dispatched AFTER coding** to audit. Provide the agent with the diff or the changed file paths; consume its punch list; fix; iterate.
- **Multiple agents run in parallel** when their concerns don't overlap (e.g. `flutter-expert` + `accessibility-tester` after a UI spec).
- **`code-reviewer`** is the last call before commit; it cross-checks behavioral parity for refactor specs (everything from Specs 03–08, 10, 11).

Never skip a spec's named agent. If an agent's punch list is empty, that's a green signal — note it in `context/progress-tracker.md` and move on.

## Codex / OpenCode / other harnesses

Skills are installed in "universal" mode — they're picked up by Claude Code, OpenCode, Amp, Antigravity, Cline, Codex, and others. No additional config needed for those harnesses; they read from `.agents/skills/` directly.

## CLI tools

Installed system-wide on the developer machine (Homebrew + `dart pub global activate`):

| Tool | Install | Purpose |
|---|---|---|
| FVM (Flutter Version Manager) | `brew tap leoafarias/fvm && brew install fvm` | Pin Flutter SDK per-project via `.fvmrc` |
| Lefthook | `brew install lefthook` | Polyglot Git hooks (format / analyze / test on commit) |
| lcov | `brew install lcov` | Coverage HTML reports (`genhtml coverage/lcov.info -o coverage/html`) |
| gh | `brew install gh` | GitHub CLI for issues/PRs/releases |
| Mason CLI | `dart pub global activate mason_cli` | Brick-based code scaffolding (BLoC, repo, feature folders) |
| coverage | `dart pub global activate coverage` | `format_coverage` / `test_with_coverage` runners |
| very_good_cli | `dart pub global activate very_good_cli` | `very_good test --min-coverage 80` gate |

`dart mcp-server` is built into the Dart SDK (3.6+); no separate install needed.

## MCP servers (Claude Code autonomous tooling)

One project-scoped MCP is registered in [`.mcp.json`](.mcp.json) at the repo root, auto-loaded by every Claude Code session in this project:

| MCP | Purpose | Workflow unlocked |
|---|---|---|
| `playwright` | Microsoft `@playwright/mcp` | Drive Chromium against `flutter run -d chrome`; AX-tree snapshots; visual screenshots — no test code needed |

**Why only one MCP?** Most MCPs duplicate CLI tools that Claude Code can already invoke via Bash. The single MCP that survives is the one with no CLI equivalent: browser automation. Specifically rejected:

| Rejected MCP | Use this instead |
|---|---|
| `dart` (`dart mcp-server`) | `flutter analyze`, `dart test`, `dart format`, `flutter run` via Bash |
| `git` (`mcp-server-git`) | `git` CLI directly (Bash tool has built-in git workflow per CLAUDE.md) |
| `ios-simulator-mcp` | `xcrun simctl boot/io/install/shutdown` via Bash |
| `@mobilenext/mobile-mcp` | `adb` + `xcrun simctl` via Bash |
| `@modelcontextprotocol/server-memory` | Claude Code built-in auto-memory at `~/.claude/projects/.../memory/MEMORY.md` |
| `@modelcontextprotocol/server-sequential-thinking` | Native reasoning; adds no capability |
| `@modelcontextprotocol/server-github` | `gh` CLI (more flexible, already authenticated) |

The principle: **if a CLI tool exists and works, use it.** MCPs are reserved for capabilities Claude can't reach through Bash.

### Visual verification workflow (Playwright MCP)

For Flutter web builds, Claude verifies visual changes directly without writing test code:

1. Developer runs `flutter run -d web-server --web-port=8080` in a terminal.
2. Claude calls `browser_navigate` → `browser_snapshot` (semantic AX tree of the Flutter canvas).
3. For pixel diffs, Claude calls `browser_take_screenshot`, saves under `docs/visuals/spec-NN/`, and compares to baselines.
4. Developer reviews screenshots in PR; no Dart test code authored.

This is the canonical visual-regression path for surfaces where golden tests (Spec 27) would be over-engineered.

## Pre-commit hooks (offline-invariant gate)

Lefthook owns `.git/hooks/*`. After cloning, run once:

```bash
lefthook install
```

The `pre-commit` block runs three commands in parallel on every commit:

1. `dart format --set-exit-if-changed -l 100` on staged Dart files.
2. `bash scripts/check-offline.sh` — fast forbidden-imports grep over `lib/` and `test/`, sourced from `scripts/.forbidden-imports.txt`. Honors `scripts/.offline-allowlist`.
3. `dart run custom_lint` — fires the `forbidden_import` rule from `tools/forbidden_imports_lint/`. (`custom_lint` v0.7 ships its own runner; `analyzer.plugins: [custom_lint]` in `analysis_options.yaml` powers IDE surfacing only.)

Full `flutter analyze` is intentionally **not** in pre-commit while the 61 strict-mode lint-debt items from Spec 01 (see [`progress-tracker.md`](context/progress-tracker.md) "Lint debt") are still open. They land per-file across Specs 04 / 04b / 08; once that backlog is clear, a future spec can promote `flutter analyze --no-pub` to pre-push or pre-commit.

To extend the offline gate with a new banned package, append the import path to `scripts/.forbidden-imports.txt` — both gates pick it up.

Bypass (maintainer-only, with justification): `LEFTHOOK=0 git commit ...`.
