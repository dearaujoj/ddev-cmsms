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
  ddev delete -Oy ${LOADPROJ} >/dev/null 2>&1 || true
  rm -rf ${LOADDIR}
}
