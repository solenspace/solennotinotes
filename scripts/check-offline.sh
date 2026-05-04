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
        ${EXCLUDE_ARGS[@]+"${EXCLUDE_ARGS[@]}"} \
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
