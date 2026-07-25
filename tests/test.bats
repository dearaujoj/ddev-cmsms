#!/usr/bin/env bats

setup() {
  set -eu -o pipefail
  export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME=test-ddev-cmsms
  export TESTDIR=~/tmp/${PROJNAME}
  export DDEV_NONINTERACTIVE=true
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
  # no setup yet: the stage falls back to versions.json default (2.2.22)
  run ddev cmsms-install fetch
  assert_success
  run ddev exec test -s /mnt/ddev_config/cmsms/cache/cmsms-2.2.22/installer.php
  assert_success
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
  run ddev cmsms setup --type module --name SkeletonTest --version 2.2.22 --yes
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
  assert_output --partial "2.2.22"
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
