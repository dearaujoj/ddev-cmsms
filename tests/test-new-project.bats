#!/usr/bin/env bats
# Tests for scripts/cmsms-new-project.sh (interactive wizard).
# The wizard reads every answer from stdin, so tests drive it with printf.

setup() {
  set -eu -o pipefail
  export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
  # bats libraries live under the brew prefix (macOS: /opt/homebrew, CI: linuxbrew)
  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-support
  bats_load_library bats-assert
  bats_load_library bats-file
  export WIZARD="$DIR/scripts/cmsms-new-project.sh"
  export PARENT="$(mktemp -d)"
  export DDEV_NONINTERACTIVE=true
}

teardown() {
  rm -rf "$PARENT"
}

# --- fast validation paths (no ddev project is ever created) -----------------

@test "wizard rejects an empty project name" {
  run bash -c "printf '\n' | '$WIZARD'"
  assert_failure
  assert_output --partial "project name is required"
}

@test "wizard rejects an invalid project name" {
  run bash -c "printf 'bad name!\n' | '$WIZARD'"
  assert_failure
  assert_output --partial "invalid project name"
}

@test "wizard rejects underscores in the project name (DDEV names are DNS-style)" {
  run bash -c "printf 'my_proj\n' | '$WIZARD'"
  assert_failure
  assert_output --partial "invalid project name"
}

@test "wizard rejects a nonexistent parent directory" {
  run bash -c "printf 'WizProj\n/nonexistent/nowhere\n' | '$WIZARD'"
  assert_failure
  assert_output --partial "does not exist"
}

@test "wizard refuses an existing project directory" {
  mkdir -p "$PARENT/WizProj"
  run bash -c "printf 'WizProj\n$PARENT\n' | '$WIZARD'"
  assert_failure
  assert_output --partial "directory already exists"
}

@test "wizard rejects an invalid extension type choice" {
  run bash -c "printf 'WizProj\n$PARENT\n9\n' | '$WIZARD'"
  assert_failure
  assert_output --partial "invalid type choice"
}

@test "wizard requires at least one extension for a workspace" {
  run bash -c "printf 'WizProj\n$PARENT\n4\n\n' | '$WIZARD'"
  assert_failure
  assert_output --partial "workspace needs at least one extension"
}

@test "cancelling at the summary exits 0 and creates nothing" {
  # answers: name, location, type(module), ext name(default), cmsms(default),
  # php(default), sample content(n), final confirm(n)
  run bash -c "printf 'WizProj\n$PARENT\n1\n\n\n\nn\nn\n' | '$WIZARD'"
  assert_success
  assert_output --partial "Cancelled."
  assert_dir_not_exists "$PARENT/WizProj"
}

# --- full flow (one real project; default core only, like test-workspace) ----

@test "wizard creates a working module project with sample content" {
  export CMSMS_TEST_VERSION=${CMSMS_TEST_VERSION:-2.2.22}
  [ "$CMSMS_TEST_VERSION" = "2.2.22" ] || skip "wizard e2e runs on the default core only"
  PROJNAME=test-ddev-cmsms-wiz
  ddev delete -Oy $PROJNAME >/dev/null 2>&1 || true

  # install the add-on from the working tree, not the released GitHub repo
  export CMSMS_ADDON_REPO="$DIR"

  # answers: name, location, type(module), ext name(WizMod), cmsms version,
  # php(default), sample content(y), final confirm(y)
  run bash -c "printf '$PROJNAME\n$PARENT\n1\nWizMod\n$CMSMS_TEST_VERSION\n\ny\ny\n' | '$WIZARD'"
  assert_success
  assert_output --partial "Done!"

  cd "$PARENT/$PROJNAME"
  # setup wrote the project config with the wizard's answers
  run grep -q "CMSMS_EXT_TYPE=module" .ddev/config.cmsms-project.yaml
  assert_success
  run grep -q "CMSMS_EXT_NAME=WizMod" .ddev/config.cmsms-project.yaml
  assert_success
  run grep -q "CMSMS_SAMPLE_CONTENT=1" .ddev/config.cmsms-project.yaml
  assert_success
  # setup auto-scaffolded the module starter in the empty directory
  assert_file_exists WizMod.module.php
  # the site is installed and serving (sample content = the extra.php branch)
  run bash -c "curl -sfL -o /dev/null -w '%{http_code}' https://${PROJNAME}.ddev.site/"
  assert_output "200"
  run bash -c "ddev mysql -N -e \"SELECT COUNT(*) FROM cms_modules WHERE module_name='WizMod'\""
  assert_output "1"

  ddev delete -Oy $PROJNAME >/dev/null 2>&1 || true
}
