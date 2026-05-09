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

# Load allowlist as repo-relative paths into an array. Each entry exempts
# the matching `lib/...` or `test/...` file from the forbidden-imports
# check. Path-based — basename collisions are not allowed.
ALLOWLIST_PATHS=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    ALLOWLIST_PATHS+=("$line")
  done < "$ALLOWLIST_FILE"
fi

# Search lib/ and test/ for any forbidden import on a non-comment line.
# `^\s*import\s+['"]` ensures we match real import directives, not comments.
HITS="$(grep -RnE "^[[:space:]]*import[[:space:]]+['\"]($PATTERNS)" \
        --include='*.dart' \
        "${REPO_ROOT}/lib" "${REPO_ROOT}/test" 2>/dev/null || true)"

# Post-filter against the allowlist. `grep --exclude` matches against the
# basename only, so it cannot honor path-distinguishing entries like
# `lib/services/speech/stt_service.dart`; doing the filter in shell here
# matches the path-based semantics that the `forbidden_imports_lint`
# custom-lint rule applies on the IDE side. Resolves open question 10.
if [[ -n "$HITS" && ${#ALLOWLIST_PATHS[@]} -gt 0 ]]; then
  FILTERED=""
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    skip=0
    for entry in "${ALLOWLIST_PATHS[@]}"; do
      if [[ "$hit" == "${REPO_ROOT}/${entry}:"* ]]; then
        skip=1
        break
      fi
    done
    if [[ $skip -eq 0 ]]; then
      FILTERED+="${hit}"$'\n'
    fi
  done <<< "$HITS"
  HITS="${FILTERED%$'\n'}"
fi

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
