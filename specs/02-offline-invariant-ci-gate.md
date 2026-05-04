# 02 — offline-invariant-ci-gate

## Goal

Lock [`context/architecture.md`](../context/architecture.md) **invariant 1** ("zero network in runtime") with two layered enforcement mechanisms: a fast shell-grep that runs in a Git pre-commit hook, and a precise `custom_lint` rule that runs as part of `flutter analyze`. After this spec, attempting to import `package:http`, any Firebase / Supabase SDK, any analytics package, or `dart:io.HttpClient` from anywhere under `lib/` causes both `git commit` and `flutter analyze` to fail with a clear diagnostic.

## Dependencies

- [01-lint-and-format-hardening](01-lint-and-format-hardening.md) — establishes the `flutter analyze` baseline. The `custom_lint` rule plugs into the same `analysis_options.yaml`.

## Agents & skills

**Pre-coding skills:**
- `dart-flutter-patterns` — DI conventions, abstract-vs-concrete patterns; relevant for the `custom_lint` rule's interfaces.

**After-coding agents:**
- `flutter-expert` — verify the `custom_lint` plugin is wired correctly into `analysis_options.yaml` and the rule fires on a forbidden import.
- `code-reviewer` — confirm the pre-commit hook is symlinked, executable, and rejects an `import 'package:http/...'` injected into any `lib/` file.

## Design Decisions

- **Single source of truth for forbidden patterns.** Both the shell grep and the `custom_lint` rule read from one file: `scripts/.forbidden-imports.txt`. Add a new package to the list once, both gates pick it up.
- **Pre-commit hook over remote CI.** Per the user's directive, no GitHub Actions / CI service is added in this spec. Hooks live in the repo at `scripts/git-hooks/` and contributors run `scripts/install-hooks.sh` once after cloning. A future spec (post-launch) can layer GitHub Actions on top using the same `check-offline.sh` script.
- **Belt-and-suspenders enforcement.** Shell grep is fast (~50ms) and language-agnostic but produces false positives on comments mentioning forbidden packages. `custom_lint` is AST-aware (zero false positives) but slow (runs as part of `flutter analyze`). The hook runs grep first for instant feedback, then `flutter analyze` for the precise check.
- **`custom_lint` package lives at `tools/forbidden_imports_lint/` with a path dependency.** Notinotes is a single-package Flutter app; introducing a `pnpm-workspace`-style monorepo is overkill for one custom lint. A path-dep'd package at `tools/` is the standard Dart pattern.
- **`custom_lint` (^0.7.0) is the right tool for one rule.** The modern alternative is `analysis_server_plugin` (the official lint-plugin API). When the project accumulates ≥3 custom rules we revisit and migrate; until then `custom_lint` stays.
- **Allowlist mechanism, but unused at this stage.** `scripts/.offline-allowlist` exists as an empty file. A future spec (Spec 19, LLM model download) is the first that may legitimately need network access at runtime, and it will add that one file path with justification. The grep + lint both honor the allowlist by file path.
- **No new runtime dependencies.** All additions are dev-only (`custom_lint`, `custom_lint_builder`, `analyzer`, `analyzer_plugin`).
- **Hook install is voluntary but documented.** [`AGENTS.md`](../AGENTS.md) and [`CLAUDE.md`](../CLAUDE.md) mention `scripts/install-hooks.sh` as a one-time bootstrap step. No coercion; offering a future Husky-style auto-install is out of scope.
- **Forbidden list matches [`context/code-standards.md`](../context/code-standards.md) "Forbidden imports" verbatim.** Drift between the doc and the gate is a defect; the doc references the gate file as canonical.

## Implementation

### A. `scripts/.forbidden-imports.txt`

Path: `scripts/.forbidden-imports.txt`

```
# Forbidden imports — sourced from context/code-standards.md.
# One pattern per line. Lines starting with # are comments.
# Both scripts/check-offline.sh and tools/forbidden_imports_lint read this file.

# HTTP clients
package:http
package:dio
package:chopper
package:retrofit
dart:io.HttpClient

# Realtime
package:web_socket_channel

# Cloud SDKs
package:cloud_firestore
package:firebase_core
package:firebase_auth
package:firebase_storage
package:firebase_remote_config
package:firebase_crashlytics
package:firebase_analytics
package:firebase_messaging
package:supabase_flutter
package:supabase
package:appwrite
package:amplify_flutter
package:amplify_auth_cognito
package:amplify_storage_s3

# Auth (cloud)
package:google_sign_in

# Telemetry / analytics
package:sentry
package:sentry_flutter
package:posthog_flutter
package:mixpanel_flutter
package:amplitude_flutter
```

> Notes:
> - Patterns are matched as literal substrings of an `import` directive.
> - To extend: append the package import path. Both gates pick it up on next run.
> - Comments use `#`. Empty lines ignored.

### B. `scripts/.offline-allowlist`

Path: `scripts/.offline-allowlist`

```
# File-path allowlist for offline-invariant exemptions.
# One file path per line, relative to repo root.
# Each entry MUST include a comment with the spec number that authorized it.
# Empty at bootstrap; Spec 19 (llm-model-download) will add the first entry.
```

### C. `scripts/check-offline.sh`

Path: `scripts/check-offline.sh` (executable)

```bash
#!/usr/bin/env bash
# check-offline.sh — fast forbidden-imports grep
# Runs over lib/ and test/, honors scripts/.offline-allowlist.
# Exits non-zero on any violation; prints file:line for each.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATTERNS_FILE="${REPO_ROOT}/scripts/.forbidden-imports.txt"
ALLOWLIST_FILE="${REPO_ROOT}/scripts/.offline-allowlist"

if [[ ! -f "$PATTERNS_FILE" ]]; then
  echo "error: ${PATTERNS_FILE} not found" >&2
  exit 2
fi

# Build grep alternation from non-comment, non-empty lines.
PATTERNS="$(grep -vE '^\s*(#|$)' "$PATTERNS_FILE" | paste -sd '|' -)"
if [[ -z "$PATTERNS" ]]; then
  echo "error: ${PATTERNS_FILE} contains no patterns" >&2
  exit 2
fi

# Build allowlist exclude args.
EXCLUDE_ARGS=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    EXCLUDE_ARGS+=("--exclude=$line")
  done < "$ALLOWLIST_FILE"
fi

# Search lib/ and test/ for any forbidden import on a non-comment line.
# `^\s*import\s+['"]` ensures we match real import directives, not comments.
HITS="$(grep -RnE "^[[:space:]]*import[[:space:]]+['\"]($PATTERNS)" \
        --include='*.dart' \
        "${EXCLUDE_ARGS[@]}" \
        "${REPO_ROOT}/lib" "${REPO_ROOT}/test" 2>/dev/null || true)"

if [[ -n "$HITS" ]]; then
  echo "Forbidden imports found (offline invariant 1):" >&2
  echo "$HITS" >&2
  echo "" >&2
  echo "If a network call is genuinely required by an authorized spec," >&2
  echo "add the file path to scripts/.offline-allowlist with a comment" >&2
  echo "naming the spec number." >&2
  exit 1
fi

exit 0
```

### D. `scripts/git-hooks/pre-commit`

Path: `scripts/git-hooks/pre-commit` (executable)

```bash
#!/usr/bin/env bash
# pre-commit — Notinotes hooks
# Runs the offline-invariant grep, dart format check, and flutter analyze.
# Install via scripts/install-hooks.sh.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

echo "[hook] check-offline.sh"
"${REPO_ROOT}/scripts/check-offline.sh"

# Only check Dart files staged for this commit.
STAGED_DART="$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.dart$' || true)"
if [[ -n "$STAGED_DART" ]]; then
  echo "[hook] dart format -l 100 (check)"
  echo "$STAGED_DART" | xargs dart format --set-exit-if-changed -l 100

  echo "[hook] flutter analyze"
  flutter analyze --no-pub
fi

exit 0
```

### E. `scripts/install-hooks.sh`

Path: `scripts/install-hooks.sh` (executable)

```bash
#!/usr/bin/env bash
# install-hooks.sh — symlink scripts/git-hooks/* into .git/hooks/
# Run once after cloning.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SRC="${REPO_ROOT}/scripts/git-hooks"
DEST="${REPO_ROOT}/.git/hooks"

mkdir -p "$DEST"
for hook_path in "$SRC"/*; do
  hook_name="$(basename "$hook_path")"
  ln -sfn "../../scripts/git-hooks/${hook_name}" "${DEST}/${hook_name}"
  echo "linked: ${DEST}/${hook_name} -> scripts/git-hooks/${hook_name}"
done

echo "Done. Hooks installed."
```

### F. `tools/forbidden_imports_lint/` — Dart package

Create a new path-dep'd package implementing a single `custom_lint` rule.

#### `tools/forbidden_imports_lint/pubspec.yaml`

```yaml
name: forbidden_imports_lint
description: Custom Dart lint that enforces Notinotes' offline-invariant — bans network/cloud package imports under lib/.
version: 0.1.0
publish_to: none

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  analyzer: ^7.0.0
  analyzer_plugin: ^0.13.0
  custom_lint_builder: ^0.7.0
```

#### `tools/forbidden_imports_lint/lib/forbidden_imports_lint.dart`

```dart
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/forbidden_imports_rule.dart';

PluginBase createPlugin() => _Plugin();

class _Plugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) =>
      [const ForbiddenImportsRule()];
}
```

#### `tools/forbidden_imports_lint/lib/src/forbidden_imports_rule.dart`

```dart
import 'dart:io';

import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

class ForbiddenImportsRule extends DartLintRule {
  const ForbiddenImportsRule() : super(code: _code);

  static const _code = LintCode(
    name: 'forbidden_import',
    problemMessage:
        'Forbidden import: violates the offline invariant (architecture.md #1).',
    correctionMessage:
        'Remove the import or add the file path to scripts/.offline-allowlist with the authorizing spec number.',
    errorSeverity: ErrorSeverity.ERROR,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final patterns = _loadPatterns();
    if (patterns.isEmpty) return;

    context.registry.addImportDirective((node) {
      final uri = node.uri.stringValue;
      if (uri == null) return;
      for (final pattern in patterns) {
        if (uri.startsWith(pattern) || uri == pattern) {
          reporter.atNode(node, _code);
          return;
        }
      }
    });
  }

  static List<String> _loadPatterns() {
    final file = File('scripts/.forbidden-imports.txt');
    if (!file.existsSync()) return const [];
    return file
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList(growable: false);
  }
}
```

> Note: the rule reads the patterns file on each analysis run from the repo root (`scripts/.forbidden-imports.txt`). `flutter analyze` is invoked from the repo root, so the relative path resolves correctly.

### G. `pubspec.yaml` additions

Append to `dev_dependencies:`:

```yaml
  custom_lint: ^0.7.0
  forbidden_imports_lint:
    path: tools/forbidden_imports_lint
```

> No additions to `dependencies:` — these are dev-only.

### H. `analysis_options.yaml` update

Modify the file produced by Spec 01 to register `custom_lint` as an analyzer plugin:

```yaml
analyzer:
  plugins:
    - custom_lint
  # ...rest of the analyzer block from Spec 01...
```

Append a `custom_lint:` section at the end:

```yaml
custom_lint:
  rules:
    - forbidden_import
```

### I. Document the hook install in `AGENTS.md`

Append to [`AGENTS.md`](../AGENTS.md):

```markdown
## Pre-commit hooks

Notinotes ships Git hooks at `scripts/git-hooks/`. After cloning, run once:

\`\`\`bash
bash scripts/install-hooks.sh
\`\`\`

This symlinks the pre-commit hook into `.git/hooks/`. The hook runs `scripts/check-offline.sh` (forbidden-imports grep), `dart format --set-exit-if-changed -l 100` on staged files, and `flutter analyze` (which includes the `forbidden_import` custom lint).
```

### J. Update `progress-tracker.md`

Add to **Architecture decisions**:

```markdown
10. **Offline invariant enforced by two layered gates**: shell grep at pre-commit (`scripts/check-offline.sh`), and a `custom_lint` rule (`tools/forbidden_imports_lint`) wired into `flutter analyze`. Forbidden patterns sourced from `scripts/.forbidden-imports.txt` (single source of truth).
```

Add to **Open questions**:

```markdown
9. Pre-commit hook discoverability — should a future spec auto-run `scripts/install-hooks.sh` on first `flutter pub get` via a tool that detects unsymlinked hooks? (Husky pattern, lower friction.) Defer until contributor count > 1.
```

## Success Criteria

- [ ] `scripts/.forbidden-imports.txt`, `scripts/.offline-allowlist`, `scripts/check-offline.sh`, `scripts/install-hooks.sh`, `scripts/git-hooks/pre-commit` exist and are executable where appropriate.
- [ ] `bash scripts/check-offline.sh` exits 0 on the current codebase (sanity).
- [ ] Adding a temporary `import 'package:http/http.dart';` to any file under `lib/` causes `bash scripts/check-offline.sh` to exit non-zero with a `file:line` diagnostic.
- [ ] The same temporary import causes `flutter analyze` to report `forbidden_import` as an error on that line.
- [ ] After `bash scripts/install-hooks.sh`, `git commit` triggers the hook; a forbidden import blocks the commit.
- [ ] `tools/forbidden_imports_lint/` is a valid Dart package; `dart pub get` inside it succeeds.
- [ ] `pubspec.yaml` adds `custom_lint` and `forbidden_imports_lint` (path) under `dev_dependencies` only.
- [ ] `analysis_options.yaml` registers `custom_lint` as an analyzer plugin and lists `forbidden_import` under `custom_lint.rules`.
- [ ] [`AGENTS.md`](../AGENTS.md) documents `bash scripts/install-hooks.sh` as a one-time bootstrap step.
- [ ] [`context/progress-tracker.md`](../context/progress-tracker.md) marks Spec 02 complete, adds architecture decision #10, adds open question #9.
- [ ] No invariant in [`context/architecture.md`](../context/architecture.md) is changed.
- [ ] No code under `lib/` is modified by this spec (gate is enforcement-only).
- [ ] No new runtime dependencies (only dev_dependencies).

## References

- [`context/architecture.md`](../context/architecture.md) — invariant 1 (zero network)
- [`context/code-standards.md`](../context/code-standards.md) — "Forbidden imports" section (single source of truth)
- [`context/ai-workflow-rules.md`](../context/ai-workflow-rules.md) — verification commands
- [01-lint-and-format-hardening](01-lint-and-format-hardening.md) — provides the `analysis_options.yaml` baseline this spec extends
- Skill: [`flutter-fix-static-analysis-errors`](../.agents/skills/dart-fix-static-analysis-errors/SKILL.md) — workflow for resolving the `forbidden_import` warnings
- `custom_lint` package: <https://pub.dev/packages/custom_lint>
- Agent: `flutter-expert` (consult for analyzer-plugin idioms if the rule needs extension)
