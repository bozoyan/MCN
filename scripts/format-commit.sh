#!/usr/bin/env bash
set -euo pipefail

REF="${1:-HEAD}"

FILES=$(git diff-tree --no-commit-id --diff-filter=ACMR --name-only -r "$REF" -- '*.dart')

if [ -z "$FILES" ]; then
  echo "No Dart files changed in $REF"
  exit 0
fi

echo "$FILES" | tr '\n' '\0' | xargs -0 dart format
