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
  export CMSMS_TEST_VERSION=${CMSMS_TEST_VERSION:-2.2.22}
  # one extra full install is enough on the default core; other matrix legs
  # already prove per-version compatibility through the main suite
  [ "$CMSMS_TEST_VERSION" = "2.2.22" ] || skip "workspace e2e runs on the default core only"
  export WSPROJ=test-ddev-cmsms-ws
  export WSDIR=~/tmp/${WSPROJ}
  export DDEV_NONINTERACTIVE=true
}

# Expensive bootstrap runs once here; later tests reuse the project.
# The config is written BY HAND on purpose: this file tests the container
# pipeline in isolation from `ddev cmsms setup` (which learns workspaces in a
# later task).
@test "workspace bootstrap: ordered modules + plugin install into one site" {
  ddev delete -Oy ${WSPROJ} >/dev/null 2>&1 || true
  rm -rf ${WSDIR} && mkdir -p ${WSDIR}
  cp -r ${DIR}/tests/testdata/workspace/. ${WSDIR}/
  cd ${WSDIR}
  mkdir -p .cmsms/public
  ddev config --project-name=${WSPROJ} --project-type=php --docroot=.cmsms/public
  ddev add-on get ${DIR}
  cat > .ddev/config.cmsms-project.yaml <<EOF
web_environment:
  - CMSMS_EXTENSIONS=module:ModuleA module:ModuleB plugin:MyTags
  - CMSMS_VERSION=${CMSMS_TEST_VERSION}
EOF
  ddev start -y
  # both modules registered (ModuleB installs only if ModuleA came first)
  run bash -c "ddev mysql -N -e \"SELECT COUNT(*) FROM cms_modules WHERE module_name IN ('ModuleA','ModuleB')\""
  assert_output "2"
  # whole-dir symlinks for subdir modules
  run ddev exec test -L /var/www/html/.cmsms/public/modules/ModuleA
  assert_success
  run ddev exec test -L /var/www/html/.cmsms/public/modules/ModuleB
  assert_success
  # plugin file linked from its subdir
  run ddev exec test -L /var/www/html/.cmsms/public/plugins/function.mytag.php
  assert_success
  run bash -c "curl -sfL -o /dev/null -w '%{http_code}' https://${WSPROJ}.ddev.site/"
  assert_output "200"
}

@test "an invalid or missing entry warns and skips, exit stays 0" {
  cd ${WSDIR}
  run ddev exec "CMSMS_EXTENSIONS='module:ModuleA module:Ghost bogus' bash /mnt/ddev_config/commands/web/cmsms-install link"
  assert_success
  assert_output --partial "skipped"
  assert_output --partial "1 linked, 2 skipped"
}

@test "setup --extensions writes the workspace config" {
  cd ${WSDIR}
  run ddev cmsms setup --extensions "module:ModuleA module:ModuleB plugin:MyTags" --version ${CMSMS_TEST_VERSION} --yes
  assert_success
  run grep -q "^  - CMSMS_EXTENSIONS=module:ModuleA module:ModuleB plugin:MyTags$" .ddev/config.cmsms-project.yaml
  assert_success
  run grep -q "CMSMS_EXT_TYPE" .ddev/config.cmsms-project.yaml
  assert_failure   # never both modes
}

@test "setup --extensions rejects bad entries and mixing with --type" {
  cd ${WSDIR}
  run ddev cmsms setup --extensions "module:Bad-Name" --yes
  assert_failure
  assert_output --partial "invalid extension entry"
  run ddev cmsms setup --extensions "module:ModuleA" --type module --yes
  assert_failure
  assert_output --partial "mutually exclusive"
}

@test "setup --yes auto-detects workspace subdirs" {
  export DETDIR=~/tmp/test-ddev-cmsms-ws-detect
  ddev delete -Oy test-ddev-cmsms-ws-detect >/dev/null 2>&1 || true
  rm -rf ${DETDIR} && mkdir -p ${DETDIR}
  cp -r ${DIR}/tests/testdata/workspace/. ${DETDIR}/
  cd ${DETDIR}
  mkdir -p .cmsms/public
  ddev config --project-name=test-ddev-cmsms-ws-detect --project-type=php --docroot=.cmsms/public
  ddev add-on get ${DIR}
  run ddev cmsms setup --yes
  assert_success
  run grep -q "CMSMS_EXTENSIONS=module:ModuleA module:ModuleB plugin:MyTags" .ddev/config.cmsms-project.yaml
  assert_success
  ddev delete -Oy test-ddev-cmsms-ws-detect >/dev/null 2>&1 || true
  rm -rf ${DETDIR}
}

@test "status lists workspace entries with link and registration state" {
  cd ${WSDIR}
  run ddev cmsms status
  assert_success
  assert_output --partial "module:ModuleA"
  assert_output --partial "module:ModuleB"
  assert_output --partial "plugin:MyTags"
  assert_output --partial "registered"
}

@test "add appends an entry and scaffolds the missing subdir" {
  cd ${WSDIR}
  run ddev cmsms add module ModuleC --yes
  assert_success
  run grep -q "CMSMS_EXTENSIONS=module:ModuleA module:ModuleB plugin:MyTags module:ModuleC" .ddev/config.cmsms-project.yaml
  assert_success
  assert_file_exists ModuleC/ModuleC.module.php
  # cleanup: restore the config and remove the scaffolded dir so later tests
  # (and re-runs) see the canonical three-entry workspace
  sed -i.bak 's/ module:ModuleC//' .ddev/config.cmsms-project.yaml && rm -f .ddev/config.cmsms-project.yaml.bak
  rm -rf ModuleC
}

@test "add re-adding the first entry reports already-listed and leaves config unchanged" {
  cd ${WSDIR}
  run ddev cmsms add module ModuleA --yes
  assert_success
  assert_output --partial "already listed"
  run grep -q "^  - CMSMS_EXTENSIONS=module:ModuleA module:ModuleB plugin:MyTags$" .ddev/config.cmsms-project.yaml
  assert_success
}

@test "add refuses on a single-extension config" {
  export ADDDIR=~/tmp/test-ddev-cmsms-ws-add
  ddev delete -Oy test-ddev-cmsms-ws-add >/dev/null 2>&1 || true
  rm -rf ${ADDDIR} && mkdir -p ${ADDDIR}
  cd ${ADDDIR}
  mkdir -p .cmsms/public
  ddev config --project-name=test-ddev-cmsms-ws-add --project-type=php --docroot=.cmsms/public
  ddev add-on get ${DIR}
  ddev cmsms setup --type module --name Solo --yes >/dev/null
  run ddev cmsms add module Extra --yes
  assert_failure
  assert_output --partial "single-extension mode"
  ddev delete -Oy test-ddev-cmsms-ws-add >/dev/null 2>&1 || true
  rm -rf ${ADDDIR}
}

@test "package <Name> builds one workspace module's XML" {
  cd ${WSDIR}
  run ddev cmsms package ModuleA
  assert_success
  assert_file_exists dist/ModuleA-1.0.0.xml
  run ddev cmsms package
  assert_failure
  assert_output --partial "pass the module name"
  run ddev cmsms package MyTags
  assert_failure
  assert_output --partial "not a module entry"
}
