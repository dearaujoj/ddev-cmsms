#!/usr/bin/env bash
# Regenerates cmsms/versions.json from the CMSMS Forge file listing.
# Usage: scripts/update-versions.sh > cmsms/versions.json
#
# The Forge listing page (https://dev.cmsmadesimple.org/project/files/6) renders
# each release as an <a href="/frs/download/<id>">cmsms-<ver>-install.zip</a>
# anchor: the version/filename lives in the link TEXT, not the href, and the
# href is a stable relative download-redirect URL (not the final asset URL).
# `curl -L` follows that redirect (currently to S3) at fetch time, so we keep
# the redirect URL rather than resolving it ourselves.
set -eu -o pipefail

FORGE_URL="https://dev.cmsmadesimple.org/project/files/6"
BASE="https://dev.cmsmadesimple.org"

page=$(curl -fsSL "$FORGE_URL")

# Anchors whose link text is exactly cmsms-<ver>-install.zip (excludes
# -install.expanded.zip, -patch.zip, -checksum.dat).
anchors=$(printf '%s' "$page" \
  | grep -oE '<a href="[^"]+">cmsms-[0-9][0-9.]*-install\.zip</a>')

[ -n "$anchors" ] || { echo "no install.zip links found at $FORGE_URL" >&2; exit 1; }

json='{}'
latest=""
while IFS= read -r a; do
  href=$(printf '%s' "$a" | sed -E 's/^<a href="([^"]+)">.*/\1/')
  ver=$(printf '%s' "$a" | sed -E 's/.*>cmsms-([0-9][0-9.]*)-install\.zip<\/a>/\1/')
  case "$href" in
    http://*|https://*) url="$href" ;;
    /*) url="${BASE}${href}" ;;
    *) url="${BASE}/${href}" ;;
  esac
  json=$(printf '%s' "$json" | jq --arg v "$ver" --arg u "$url" '.[$v] = {url: $u}')
  latest=$(printf '%s\n%s\n' "$latest" "$ver" | grep -v '^$' | sort -V | tail -1)
done <<< "$anchors"

jq -n --arg d "$latest" --argjson vs "$json" '{default: $d, versions: $vs}'
