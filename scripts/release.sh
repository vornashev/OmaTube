#!/usr/bin/env bash
# Cut a release locally: bump the version everywhere, turn [Unreleased] into a dated CHANGELOG section,
# run the checks and tests, commit "Release vX.Y.Z" and create an annotated tag. Nothing is pushed.
#   scripts/release.sh 0.2.1
#   scripts/release.sh 0.2.1 --skip-tests
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_URL="https://github.com/vornashev/OmaTube"
version="${1:-}"
skip_tests=0
[[ ${2:-} == --skip-tests ]] && skip_tests=1
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  sed -n '2,5p' "$0" >&2
  exit 2
fi
tag="v$version"
say() { printf '==> %s\n' "$*"; }
die() { echo "release: $*" >&2; exit 1; }

[[ $(git branch --show-current) == main ]] || die "releases are cut from main"
[[ -z $(git status --porcelain) ]] || die "the working tree has uncommitted changes"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists"
scripts/changelog-section.sh Unreleased >/dev/null || die "CHANGELOG.md [Unreleased] is empty; nothing to release"
previous="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"

say "bumping the version to $version"
for file in manifest.json package.json browser-extension/manifest.json; do
  # Edit in place so each file keeps its own formatting.
  sed -i -E '0,/"version": *"[^"]+"/s//"version": "'"$version"'"/' "$file"
done
jq --arg v "$version" '.version = $v | .packages[""].version = $v' package-lock.json > package-lock.json.tmp
mv package-lock.json.tmp package-lock.json

say "dating the CHANGELOG section"
today="$(date +%F)"
compare="$REPO_URL/releases/tag/$tag"
[[ -n $previous ]] && compare="$REPO_URL/compare/$previous...$tag"
awk -v version="$version" -v today="$today" -v tag="$tag" -v compare="$compare" -v url="$REPO_URL" '
  /^## \[Unreleased\]/ { print; print ""; print "## [" version "] - " today; next }
  /^\[Unreleased\]: / { print "[Unreleased]: " url "/compare/" tag "...HEAD"; print "[" version "]: " compare; next }
  { print }
' CHANGELOG.md > CHANGELOG.md.tmp
mv CHANGELOG.md.tmp CHANGELOG.md

say "checking"
scripts/check.sh --tag "$tag"
if ((!skip_tests)); then
  python="${PYTHON:-}"
  for candidate in .venv/bin/python "$HOME/.local/share/omatube/app/.venv/bin/python"; do
    [[ -z $python && -x $candidate ]] && python="$candidate"
  done
  [[ -n $python ]] || die "no Python with the backend dependencies; create .venv (see docs/development.md) or set PYTHON"
  "$python" -m unittest discover -s tests
  node --test browser-extension/lib/
fi

say "committing and tagging $tag"
git add manifest.json package.json package-lock.json browser-extension/manifest.json CHANGELOG.md
git commit -q -m "Release $tag"
{ printf 'OmaTube %s\n\n' "$tag"; scripts/changelog-section.sh "$version"; } | git tag -a --cleanup=verbatim "$tag" -F -

say "done. Review with: git show $tag"
echo "Publish with:   git push --atomic origin main $tag"
