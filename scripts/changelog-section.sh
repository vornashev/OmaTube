#!/usr/bin/env bash
# Print the body of one CHANGELOG.md section, without its heading.
#   scripts/changelog-section.sh 0.2.0
#   scripts/changelog-section.sh Unreleased
# Exits 1 when the section is missing or empty. Used for GitHub release notes and tag messages.
set -euo pipefail
cd "$(dirname "$0")/.."

name="${1:?usage: $0 <version|Unreleased>}"
body="$(awk -v name="$name" '
  /^## \[/ { if (found) exit; found = index($0, "## [" name "]") == 1; next }
  /^\[[^]]+\]: / { if (found) exit }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"
[[ -n $body ]] || exit 1
printf '%s\n' "$body"
