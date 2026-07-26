#!/usr/bin/env bats

setup() {
  set -eu -o pipefail
  export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME=test-ddev-cmsms
  export TESTDIR=~/tmp/${PROJNAME}
  export DDEV_NONINTERACTIVE=true
  export CMSMS_TEST_VERSION=${CMSMS_TEST_VERSION:-2.2.22}
  # bats libraries live under the brew prefix (macOS: /opt/homebrew, CI: linuxbrew)
  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-support
  bats_load_library bats-assert
  bats_load_library bats-file
}

# Expensive bootstrap runs once in the first test; later tests reuse the project.
@test "install add-on into a fresh module project" {
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1 || true
  rm -rf ${TESTDIR} && mkdir -p ${TESTDIR}
  cp -r ${DIR}/tests/testdata/SkeletonTest/. ${TESTDIR}/
  cd ${TESTDIR}
  mkdir -p .cmsms/public
  ddev config --project-name=${PROJNAME} --project-type=php --docroot=.cmsms/public
  run ddev add-on get ${DIR}
  assert_success
  [ -z "${CMSMS_TEST_PHP:-}" ] || ddev config --php-version=${CMSMS_TEST_PHP}
  ddev cmsms setup --type module --name SkeletonTest --version ${CMSMS_TEST_VERSION} --yes
  assert_file_exists .ddev/commands/web/cmsms-install
  assert_file_exists .ddev/commands/host/cmsms
  assert_file_exists .ddev/config.cmsms.yaml
  run grep -q "^\.cmsms/" .gitignore
  assert_success
}

@test "stub cmsms-install all exits 0 so ddev start is safe" {
  cd ${TESTDIR}
  ddev start -y
  # web command files register as `ddev <name>` (they are NOT on the container PATH)
  run ddev cmsms-install all
  assert_success
}

@test "fetch stage downloads and unpacks the installer phar into the cache" {
  cd ${TESTDIR}
  # setup already ran in the bootstrap test; re-fetching is an idempotent no-op
  run ddev cmsms-install fetch
  assert_success
  run ddev exec test -s /mnt/ddev_config/cmsms/cache/cmsms-${CMSMS_TEST_VERSION}/installer.php
  assert_success
}

@test "fetch uses a loaded local zip and bypasses versions.json" {
  cd ${TESTDIR}
  # build a synthetic cmsms-9.9.9 zip from the real cached installer payload
  ddev exec "cd /tmp && cp /mnt/ddev_config/cmsms/cache/cmsms-${CMSMS_TEST_VERSION}/installer.php cmsms-9.9.9-install.php && zip -q local999.zip cmsms-9.9.9-install.php"
  ddev exec cp /tmp/local999.zip /var/www/html/local999.zip
  run ddev cmsms load local999.zip
  assert_success
  assert_file_exists .ddev/cmsms/cache/cmsms-9.9.9-install.zip
  # 9.9.9 is NOT in versions.json — fetch must succeed via the drop-in
  run ddev exec "CMSMS_VERSION=9.9.9 bash /mnt/ddev_config/commands/web/cmsms-install fetch"
  assert_success
  assert_output --partial "using local installer zip"
  run ddev exec test -s /mnt/ddev_config/cmsms/cache/cmsms-9.9.9/installer.php
  assert_success
  # the drop-in itself must survive
  assert_file_exists .ddev/cmsms/cache/cmsms-9.9.9-install.zip
  # file:// escape hatch: same zip via CMSMS_INSTALLER_URL, with the drop-in
  # cleared first — otherwise it would shadow the URL (same canonical name)
  ddev exec "rm -rf /mnt/ddev_config/cmsms/cache/cmsms-9.9.9 && cp /var/www/html/local999.zip /tmp/local999.zip"
  rm -f ${TESTDIR}/.ddev/cmsms/cache/cmsms-9.9.9-install.zip
  run ddev exec "CMSMS_VERSION=9.9.9 CMSMS_INSTALLER_URL=file:///tmp/local999.zip bash /mnt/ddev_config/commands/web/cmsms-install fetch"
  assert_success
  run ddev exec test -s /mnt/ddev_config/cmsms/cache/cmsms-9.9.9/installer.php
  assert_success
  # cleanup: drop-in, expanded cache dir, scratch files
  rm -f ${TESTDIR}/local999.zip ${TESTDIR}/.ddev/cmsms/cache/cmsms-9.9.9-install.zip
  ddev exec "rm -rf /mnt/ddev_config/cmsms/cache/cmsms-9.9.9 /tmp/local999.zip /tmp/cmsms-9.9.9-install.php"
}

@test "files stage extracts the core and writes config.php" {
  cd ${TESTDIR}
  run ddev cmsms-install files
  assert_success
  run ddev exec test -f /var/www/html/.cmsms/public/lib/include.php
  assert_success
  run ddev exec test -f /var/www/html/.cmsms/installer/app/install/schema.php
  assert_success
  run ddev exec test -f /var/www/html/.cmsms/installer/.extract-complete
  assert_success
  run ddev exec php -l /var/www/html/.cmsms/public/config.php
  assert_success
}

@test "db stage installs schema, admin user, and serves the frontend" {
  cd ${TESTDIR}
  run ddev cmsms-install db
  assert_success
  run bash -c "ddev mysql -N -e 'SELECT version FROM cms_version'"
  assert_success
  run bash -c "ddev mysql -N -e \"SELECT COUNT(*) FROM cms_users WHERE username='admin'\""
  assert_output "1"
  run bash -c "curl -sfL -o /dev/null -w '%{http_code}' https://${PROJNAME}.ddev.site/"
  assert_output "200"
  run bash -c "curl -sfL https://${PROJNAME}.ddev.site/admin/login.php"
  assert_success
}

@test "link stage symlinks the module and installs it in the DB" {
  cd ${TESTDIR}
  # setup does not exist until Task 7, so pass the env inline via the script path
  run ddev exec "CMSMS_EXT_TYPE=module CMSMS_EXT_NAME=SkeletonTest bash /mnt/ddev_config/commands/web/cmsms-install link"
  assert_success
  run ddev exec test -L /var/www/html/.cmsms/public/modules/SkeletonTest/SkeletonTest.module.php
  assert_success
  run ddev exec test -e /var/www/html/.cmsms/public/modules/SkeletonTest/.cmsms
  assert_failure   # exclusion list prevents the symlink cycle
  run bash -c "ddev mysql -N -e \"SELECT COUNT(*) FROM cms_modules WHERE module_name='SkeletonTest'\""
  assert_output "1"
  run bash -c "curl -sfL -o /dev/null -w '%{http_code}' https://${PROJNAME}.ddev.site/"
  assert_output "200"
}

@test "non-interactive setup writes the project config" {
  cd ${TESTDIR}
  run ddev cmsms setup --type module --name SkeletonTest --version ${CMSMS_TEST_VERSION} --yes
  assert_success
  assert_file_exists .ddev/config.cmsms-project.yaml
  run grep -q "CMSMS_EXT_NAME=SkeletonTest" .ddev/config.cmsms-project.yaml
  assert_success
}

@test "status reports core version and extension state" {
  cd ${TESTDIR}
  ddev restart -y >/dev/null   # pick up the new env vars
  run ddev cmsms status
  assert_success
  assert_output --partial "${CMSMS_TEST_VERSION}"
  assert_output --partial "SkeletonTest"
  assert_output --partial "installed"
}

@test "package builds a valid module XML into dist/" {
  cd ${TESTDIR}
  run ddev cmsms package
  assert_success
  assert_file_exists dist/SkeletonTest-1.0.0.xml
  run ddev exec php -r 'exit(simplexml_load_file("/var/www/html/dist/SkeletonTest-1.0.0.xml") === false ? 1 : 0);'
  assert_success
}

@test "reinstall wipes and reinstalls to a working site" {
  cd ${TESTDIR}
  run ddev cmsms reinstall --yes
  assert_success
  run bash -c "curl -sfL -o /dev/null -w '%{http_code}' https://${PROJNAME}.ddev.site/"
  assert_output "200"
  run bash -c "ddev mysql -N -e \"SELECT COUNT(*) FROM cms_modules WHERE module_name='SkeletonTest'\""
  assert_output "1"
}

@test "theme scaffold copies OneEleven under the new name" {
  cd ${TESTDIR}
  run ddev cmsms scaffold --type theme --name FreshTheme --yes
  assert_success
  assert_file_exists FreshTheme/FreshThemeTheme.php
  run grep -q "class FreshThemeTheme" FreshTheme/FreshThemeTheme.php
  assert_success
  run grep -rq "OneEleven" FreshTheme/FreshThemeTheme.php
  assert_failure
  # the sed rewrite is the step that could break syntax — lint the renamed
  # file inside the container (host php isn't guaranteed to exist)
  run ddev exec php -l /var/www/html/FreshTheme/FreshThemeTheme.php
  assert_success
  rm -rf ${TESTDIR}/FreshTheme   # keep the shared module project clean
}
