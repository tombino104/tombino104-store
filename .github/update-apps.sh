#!/usr/bin/env bash
# Keeps the tracked apps up to date. See ../AGENTS.md ("Auto-updates").
#
# For each line of .github/tracked-apps.txt (app|image|source):
#   1. work out the image tag: "latest" (or any fixed tag), or the tag of the
#      project's newest GitHub release (gh:owner/repo, gh-nov:owner/repo drops a leading "v")
#      or newest version tag (tag-nov:owner/repo)
#   2. resolve that tag to a digest and pin it in the app's docker-compose.yml
#   3. when something changed, bump `version` in umbrel-app.yml so Umbrel offers
#      the update (release number for gh sources, today's date for the others)
# A broken line is reported and skipped; the others still run. Exit 1 at the end if any failed.
set -uo pipefail
cd "$(dirname "$0")/.."
today="$(date -u +%Y.%-m.%-d)"
failed=0

fail() { echo "::error::$*"; failed=1; }

track() {
  local app="$1" image="$2" source="$3" tag version
  case "$source" in
    gh:*|gh-nov:*)
      tag="$(gh api "repos/${source#*:}/releases/latest" --jq .tag_name)" || { fail "$app: no release found for ${source#*:}"; return; }
      [[ "$source" == gh-nov:* ]] && tag="${tag#v}"
      version="${tag#v}"
      ;;
    tag-nov:*)
      # Projects that push version tags without publishing a GitHub release.
      tag="$(gh api "repos/${source#*:}/tags" --paginate --jq '.[].name' | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -V | tail -n 1)"
      [[ -n "$tag" ]] || { fail "$app: no version tag found for ${source#*:}"; return; }
      version="$tag"
      ;;
    *)
      tag="$source"
      version="$today"
      ;;
  esac
  local digest
  digest="$(docker buildx imagetools inspect "$image:$tag" --format '{{.Manifest.Digest}}' 2>/dev/null)"
  [[ "$digest" == sha256:* ]] || { fail "$app: $image:$tag was not found in its registry"; return; }

  local compose="$app/docker-compose.yml" wanted="image: $image:$tag@$digest"
  if grep -qF "$wanted" "$compose"; then
    echo "$app: $image is up to date ($tag)"
    return
  fi
  sed -i -E "s|^( *)image: ${image}:.*|\1${wanted}|" "$compose"
  grep -qF "$wanted" "$compose" || { fail "$app: no 'image: $image' line in $compose"; return; }
  sed -i -E "s|^version: .*|version: \"${version}\"|" "$app/umbrel-app.yml"
  echo "$app: $image -> $tag ($digest), version $version"
}

while IFS='|' read -r app image source; do
  [[ -z "${app// }" || "$app" == \#* ]] && continue
  track "$app" "$image" "$source"
done < .github/tracked-apps.txt

exit "$failed"
