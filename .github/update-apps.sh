#!/usr/bin/env bash
# Pins every tracked app to the current digest of its image and bumps its
# version when the digest changed, so Umbrel offers the update.
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(date -u +%Y.%-m.%-d)"

while IFS='|' read -r app image tag; do
  [[ -z "${app// }" || "$app" == \#* ]] && continue
  digest="$(docker buildx imagetools inspect "$image:$tag" --format '{{.Manifest.Digest}}')"
  [[ "$digest" == sha256:* ]] || { echo "::error::no digest for $image:$tag"; exit 1; }
  compose="$app/docker-compose.yml"
  new="image: $image:$tag@$digest"
  if grep -qF "$new" "$compose"; then
    echo "$app is up to date"
    continue
  fi
  sed -i -E "s|^( *)image: ${image}:.*|\1${new}|" "$compose"
  sed -i -E "s|^version: .*|version: \"${version}\"|" "$app/umbrel-app.yml"
  echo "$app -> $digest ($version)"
done < .github/tracked-apps.txt
