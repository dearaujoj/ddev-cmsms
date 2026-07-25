#!/usr/bin/env bats

setup() {
  export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
  bats_load_library bats-support
  bats_load_library bats-assert
}

@test "versions.json has a default that resolves to a live URL" {
  v=$(jq -r '.default' ${DIR}/cmsms/versions.json)
  [ "$v" != "null" ]
  url=$(jq -r --arg v "$v" '.versions[$v].url' ${DIR}/cmsms/versions.json)
  assert [ "$url" != "null" ]
  run curl -fsIL -o /dev/null -w '%{http_code}' "$url"
  assert_output --partial "200"
}

@test "update-versions.sh regenerates a superset of current versions" {
  tmp=$(mktemp -d)
  ${DIR}/scripts/update-versions.sh > ${tmp}/versions.json
  for v in $(jq -r '.versions | keys[]' ${DIR}/cmsms/versions.json); do
    url=$(jq -r --arg v "$v" '.versions[$v].url // "missing"' ${tmp}/versions.json)
    assert [ "$url" != "missing" ]
  done
}
