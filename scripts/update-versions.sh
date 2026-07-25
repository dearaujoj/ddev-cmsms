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
MIN_VERSIONS=5  # sanity floor: fewer than this means the Forge markup likely drifted

page=$(curl -fsSL --max-time 60 "$FORGE_URL")

# Anchors whose link text is cmsms-<ver>-install.zip (excludes
# -install.expanded.zip, -patch.zip, -checksum.dat). Tolerant of extra
# attributes on the <a> tag and of whitespace between the tag and its text,
# so minor markup drift doesn't silently drop matches.
#
# `|| true`: under `set -e`, a zero-match grep would otherwise abort the
# script right here (before the emptiness check below ever runs).
anchors=$(printf '%s' "$page" \
  | grep -oE '<a[^>]*href="[^"]+"[^>]*>[[:space:]]*cmsms-[0-9][0-9.]*-install\.zip[[:space:]]*</a>' \
  || true)

if [ -z "$anchors" ]; then
  echo "no install.zip links found at $FORGE_URL" >&2
  exit 1
fi

entries=""
latest=""
count=0
while IFS= read -r a; do
  href=$(printf '%s' "$a" | sed -E 's/^<a[^>]*href="([^"]+)".*/\1/')
  ver=$(printf '%s' "$a" \
    | grep -oE 'cmsms-[0-9][0-9.]*-install\.zip' \
    | sed -E 's/^cmsms-//; s/-install\.zip$//')
  case "$href" in
    http://*|https://*) url="$href" ;;
    /*) url="${BASE}${href}" ;;
    *) url="${BASE}/${href}" ;;
  esac
  entries="${entries}${ver}"$'\t'"${url}"$'\n'
  latest=$(printf '%s\n%s\n' "$latest" "$ver" | grep -v '^$' | sort -V | tail -1)
  count=$((count + 1))
done <<< "$anchors"

# Sanity guard: catches partial markup drift that still yields >0 but
# implausibly few matches (e.g. the tolerant regex above stops matching most
# rows but not all), which would otherwise pass the emptiness check silently.
if [ "$count" -lt "$MIN_VERSIONS" ]; then
  echo "only found $count version(s) at $FORGE_URL (expected >= $MIN_VERSIONS) - Forge markup may have changed" >&2
  exit 1
fi

# Single jq call to assemble the versions map (rather than one jq invocation
# per matched anchor), then one more to assemble the final document.
json=$(printf '%s' "$entries" | jq -R -s '
  split("\n")
  | map(select(length > 0) | split("\t") | {key: .[0], value: {url: .[1]}})
  | from_entries
')

jq -n --arg d "$latest" --argjson vs "$json" '{_comment: "#ddev-generated", default: $d, versions: $vs}'
