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
