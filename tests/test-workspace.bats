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
