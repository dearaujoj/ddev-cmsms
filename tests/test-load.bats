#!/usr/bin/env bats

setup() {
  set -eu -o pipefail
  export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
  # bats libraries live under the brew prefix (macOS: /opt/homebrew, CI: linuxbrew)
  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-support
  bats_load_library bats-assert
  bats_load_library bats-file
  export LOADPROJ=test-ddev-cmsms-load
  export LOADDIR=~/tmp/${LOADPROJ}
  export DDEV_NONINTERACTIVE=true
}

# Host-side only — this project is configured but NEVER started.
@test "load derives the canonical version from the inner phar name" {
  ddev delete -Oy ${LOADPROJ} >/dev/null 2>&1 || true
  rm -rf ${LOADDIR} && mkdir -p ${LOADDIR}
  cd ${LOADDIR}
  mkdir -p .cmsms/public
  ddev config --project-name=${LOADPROJ} --project-type=php --docroot=.cmsms/public
  ddev add-on get ${DIR}
  # synthetic installer zip: outer name is deliberately WRONG/uninformative
  echo '<?php /* stub phar */' > cmsms-9.9.9-install.php
  zip -q renamed-download.zip cmsms-9.9.9-install.php
  rm cmsms-9.9.9-install.php
  run ddev cmsms load renamed-download.zip
  assert_success
  assert_output --partial "9.9.9"
  assert_file_exists .ddev/cmsms/cache/cmsms-9.9.9-install.zip
  rm renamed-download.zip
}

@test "load rejects a nonexistent path" {
  cd ${LOADDIR}
  run ddev cmsms load ./does-not-exist.zip
  assert_failure
  assert_output --partial "not found"
}

@test "load rejects a zip without exactly one installer phar" {
  cd ${LOADDIR}
  echo "just text" > nothing.txt
  zip -q no-phar.zip nothing.txt
  run ddev cmsms load no-phar.zip
  assert_failure
  assert_output --partial "exactly one cmsms-<version>-install.php"
  rm -f no-phar.zip nothing.txt
}

@test "load rejects a nested installer phar entry" {
  cd ${LOADDIR}
  mkdir -p sub
  echo '<?php /* stub phar */' > sub/cmsms-9.9.6-install.php
  zip -q nested.zip sub/cmsms-9.9.6-install.php
  rm -rf sub
  run ddev cmsms load nested.zip
  assert_failure
  assert_output --partial "zip root"
  rm -f nested.zip
}

@test "load --use rewrites CMSMS_VERSION in an existing config" {
  cd ${LOADDIR}
  ddev cmsms setup --type module --name LoadTest --version 2.2.22 --yes >/dev/null 2>&1 || true
  # setup auto-scaffolds on --yes; the module files are irrelevant here
  echo '<?php /* stub phar */' > cmsms-9.9.8-install.php
  zip -q v998.zip cmsms-9.9.8-install.php
  rm cmsms-9.9.8-install.php
  run ddev cmsms load v998.zip --use
  assert_success
  run grep -q "CMSMS_VERSION=9.9.8" .ddev/config.cmsms-project.yaml
  assert_success
  rm -f v998.zip
}

@test "load --use fails when the CMSMS_VERSION line was re-indented" {
  cd ${LOADDIR}
  # cmd_setup writes "  - CMSMS_VERSION=..." (2-space list indent); simulate
  # a hand-edited config re-indented to 4 spaces, which the sed anchor
  # `^  - CMSMS_VERSION=` can no longer match.
  sed -i.bak 's/^  - CMSMS_VERSION=/    - CMSMS_VERSION=/' .ddev/config.cmsms-project.yaml
  rm -f .ddev/config.cmsms-project.yaml.bak
  echo '<?php /* stub phar */' > cmsms-9.9.5-install.php
  zip -q v995.zip cmsms-9.9.5-install.php
  rm cmsms-9.9.5-install.php
  run ddev cmsms load v995.zip --use
  assert_failure
  assert_output --partial "could not find a CMSMS_VERSION= line to update"
  rm -f v995.zip
  # restore the standard indent so it doesn't leak into other tests
  sed -i.bak 's/^    - CMSMS_VERSION=/  - CMSMS_VERSION=/' .ddev/config.cmsms-project.yaml
  rm -f .ddev/config.cmsms-project.yaml.bak
}

@test "load clears a stale expanded cache dir when reloading the same version" {
  cd ${LOADDIR}
  echo '<?php /* stub phar */' > cmsms-9.9.7-install.php
  zip -q v997.zip cmsms-9.9.7-install.php
  rm cmsms-9.9.7-install.php
  run ddev cmsms load v997.zip
  assert_success
  # simulate a leftover expansion from a previous fetch, which stage_fetch
  # would otherwise short-circuit on and never re-expand the reloaded zip
  mkdir -p .ddev/cmsms/cache/cmsms-9.9.7
  touch .ddev/cmsms/cache/cmsms-9.9.7/marker
  run ddev cmsms load v997.zip
  assert_success
  assert_dir_not_exists .ddev/cmsms/cache/cmsms-9.9.7
  rm -f v997.zip
}

@test "load test project cleanup" {
  ddev delete -Oy ${LOADPROJ} >/dev/null 2>&1 || true
  rm -rf ${LOADDIR}
}
