#!/usr/bin/env bash
# Sparring is a separate pipeline (docs/SPARRING.md): a change that touches
# sparring may only touch sparring's own folders plus the few entry points.
# Fails when a sparring change edits anything else — the shadow / drill /
# import / session pipeline must stay exactly as it is.
#
# Usage: scripts/check_sparring_isolation.sh [base-ref]   (default origin/main)
set -euo pipefail

BASE="${1:-origin/main}"
CHANGED=$(git diff --name-only "$(git merge-base "$BASE" HEAD)" HEAD)

SPARRING='^(app/lib/sparring/|app/test/sparring/|app/packages/sparring_pose/|supabase/functions/sparring/|supabase/migrations/[0-9]+_sparring[^/]*\.sql$)'
ALLOWED="$SPARRING"'|^(app/lib/ui/screens/home_screen\.dart|app/lib/ui/screens/history_screen\.dart|app/lib/main\.dart|app/pubspec\.yaml|app/pubspec\.lock|README\.md|scripts/check_sparring_isolation\.sh|\.github/workflows/sparring-check\.yml|\.github/workflows/ios-build\.yml)$|^docs/'

if ! echo "$CHANGED" | grep -Eq "$SPARRING"; then
  echo "No sparring changes — nothing to check."
  exit 0
fi

OUTSIDE=$(echo "$CHANGED" | grep -Ev "$ALLOWED" || true)
if [ -n "$OUTSIDE" ]; then
  echo "::error::Sparring changes must not edit the single-person pipeline. Outside the allowed list:"
  echo "$OUTSIDE"
  exit 1
fi
echo "Sparring isolation OK ($(echo "$CHANGED" | wc -l | tr -d ' ') files changed)."
