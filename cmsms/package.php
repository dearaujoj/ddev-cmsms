<?php
#ddev-generated
/**
 * Builds the distributable module XML (same output as ModuleManager export).
 * Usage: php package.php <docroot> <ModuleName> <output_dir>
 */
[$self, $destdir, $name, $outdir] = $argv + [null, null, null, null];
if (!$destdir || !$name || !$outdir) { fwrite(STDERR, "usage: package.php <docroot> <ModuleName> <outdir>\n"); exit(2); }
$destdir = rtrim($destdir, '/');

global $CMS_INSTALL_PAGE, $DONT_LOAD_DB, $DONT_LOAD_SMARTY;
$CMS_INSTALL_PAGE = 1;
$DONT_LOAD_DB = 1;
$DONT_LOAD_SMARTY = 1;

include_once "$destdir/lib/include.php";
require_once "$destdir/lib/smarty/Smarty.class.php";

$spec = new \CMSMS\Database\ConnectionSpec;
$spec->type = 'mysqli'; $spec->host = 'db'; $spec->username = 'db';
$spec->password = 'db'; $spec->dbname = 'db'; $spec->prefix = 'cms_';
if (!defined('CMS_DB_PREFIX')) define('CMS_DB_PREFIX', $spec->prefix);
$db = \CMSMS\Database\Connection::initialize($spec);
$db->SetErrorHandler(function() {});
$db->Execute("SET NAMES 'utf8'");
\CMSMS\Database\compatibility::noop();
\CmsApp::get_instance()->_setDb($db);

// see register-extension.php for why this must be cleared before module operations
unset($GLOBALS['CMS_INSTALL_PAGE']);

$modops = \ModuleOperations::get_instance();
$mod = $modops->get_module_instance($name, '', TRUE);
if (!is_object($mod)) { fwrite(STDERR, "[package] cannot load module $name — is it linked and installed?\n"); exit(1); }

$message = ''; $filecount = 0;
$xml = $mod->CreateXMLPackage($message, $filecount);
if (!$xml) { fwrite(STDERR, "[package] CreateXMLPackage failed: $message\n"); exit(1); }

@mkdir($outdir, 0777, true);
$out = "$outdir/$name-" . $mod->GetVersion() . '.xml';
file_put_contents($out, $xml);
echo "[package] wrote $out ($filecount files; $message)\n";
