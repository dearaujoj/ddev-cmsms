<?php
#ddev-generated
// Usage: php extract.php <installer.php> <installer_dir> <docroot>
// Extracts the self-extracting CMSMS installer phar, then unpacks the
// core-files tarball (data/data.tar.gz) into the docroot.
[$self, $installer, $installerDir, $docroot] = $argv + [null, null, null, null];
if (!$installer || !$installerDir || !$docroot) {
    fwrite(STDERR, "usage: extract.php <installer.php> <installer_dir> <docroot>\n");
    exit(2);
}

@mkdir($installerDir, 0777, true);
$pharCopy = "$installerDir/installer.phar";
if (!copy($installer, $pharCopy)) { fwrite(STDERR, "cannot copy $installer\n"); exit(1); }

echo "[extract] unpacking installer phar\n";
$phar = new Phar($pharCopy);
$phar->extractTo($installerDir, null, true);
unset($phar);
unlink($pharCopy);

$tarball = "$installerDir/data/data.tar.gz";
if (!is_file($tarball)) { fwrite(STDERR, "no data/data.tar.gz inside installer\n"); exit(1); }

echo "[extract] unpacking core files into $docroot\n";
@mkdir($docroot, 0777, true);
$data = new PharData($tarball);
$data->extractTo($docroot, null, true);

// Only mark extraction complete once both the installer app and the core
// files have been fully unpacked, so a mid-extraction failure (process
// killed, disk full, etc.) never leaves a stale marker behind.
touch("$installerDir/.extract-complete");
echo "[extract] done\n";
