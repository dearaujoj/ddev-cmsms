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
  export SCAFPROJ=test-ddev-cmsms-scaffold
  export SCAFDIR=~/tmp/${SCAFPROJ}
  export DDEV_NONINTERACTIVE=true
}

# Host-side generation only — this project is configured but NEVER started.
@test "scaffold generates a module starter in an empty repo" {
  ddev delete -Oy ${SCAFPROJ} >/dev/null 2>&1 || true
  rm -rf ${SCAFDIR} && mkdir -p ${SCAFDIR}
  cd ${SCAFDIR}
  mkdir -p .cmsms/public
  ddev config --project-name=${SCAFPROJ} --project-type=php --docroot=.cmsms/public
  ddev add-on get ${DIR}
  run ddev cmsms scaffold --type module --name Fresh --yes
  assert_success
  assert_file_exists Fresh.module.php
  assert_file_exists action.default.php
  assert_file_exists action.defaultadmin.php
  assert_file_exists templates/default.tpl
  assert_file_exists lang/en_US.php
  run grep -q "class Fresh extends CMSModule" Fresh.module.php
  assert_success
  # marker must be stripped from generated user files
  run grep -r "ddev-generated" Fresh.module.php action.default.php action.defaultadmin.php templates/default.tpl lang/en_US.php
  assert_failure
  if command -v php >/dev/null 2>&1; then
    run php -l Fresh.module.php; assert_success
    run php -l action.default.php; assert_success
    run php -l action.defaultadmin.php; assert_success
    run php -l lang/en_US.php; assert_success
  fi
}

@test "scaffold generates a lowercase plugin file" {
  cd ${SCAFDIR}
  run ddev cmsms scaffold --type plugin --name MyHelper --yes
  assert_success
  assert_file_exists function.myhelper.php
  run grep -q "smarty_function_myhelper" function.myhelper.php
  assert_success
  if command -v php >/dev/null 2>&1; then
    run php -l function.myhelper.php; assert_success
  fi
}

@test "scaffold refuses to overwrite an existing target" {
  cd ${SCAFDIR}
  run ddev cmsms scaffold --type module --name Fresh --yes
  assert_failure
  assert_output --partial "refusing to overwrite"
}

@test "scaffold refuses to overwrite non-name-bearing files from a prior module" {
  cd ${SCAFDIR}
  # action.default.php, action.defaultadmin.php, templates/default.tpl, and
  # lang/en_US.php don't embed the module name, so scaffolding a second
  # module (Other) into the same dir must still be refused because those
  # files already exist from the Fresh module scaffolded earlier.
  run ddev cmsms scaffold --type module --name Other --yes
  assert_failure
  assert_output --partial "refusing to overwrite"
}
