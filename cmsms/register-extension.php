<?php
#ddev-generated
/**
 * Registers a linked extension inside an installed CMSMS site.
 * Usage: php register-extension.php <docroot> module|theme <Name>
 *  - module: ModuleOperations::InstallModule() (skips if already installed)
 *  - theme:  sets the admin user's 'admintheme' preference
 */
[$self, $destdir, $type, $name] = $argv + [null, null, null, null];
if (!$destdir || !$type || !$name) { fwrite(STDERR, "usage: register-extension.php <docroot> module|theme <Name>\n"); exit(2); }
$destdir = rtrim($destdir, '/');

global $CMS_INSTALL_PAGE, $DONT_LOAD_DB, $DONT_LOAD_SMARTY;
$CMS_INSTALL_PAGE = 1;   // relaxed bootstrap, same pattern as the phar installer's step 9
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

// ModuleOperations::_load_module() special-cases $CMS_INSTALL_PAGE: for a
// module that isn't already installed, it only proceeds if the module is a
// system module or queued for install, otherwise it discards the loaded
// instance and get_module_instance() returns null (InstallModule() then
// fails with "the module has not been instantiated"). We only needed
// CMS_INSTALL_PAGE to skip include.php's eager LoadModules() call before the
// DB was connected (see lib/include.php); clear it now so get_module_instance()
// loads our extension normally for the explicit InstallModule() call below.
unset($GLOBALS['CMS_INSTALL_PAGE']);

try {
    if ($type === 'module') {
        $installed = $db->GetOne('SELECT version FROM ' . CMS_DB_PREFIX . 'modules WHERE module_name = ?', [$name]);
        if ($installed) { echo "[register] module $name already installed (v$installed)\n"; exit(0); }
        $modops = \ModuleOperations::get_instance();
        $res = $modops->InstallModule($name);
        if (is_array($res) && empty($res[0])) {
            fwrite(STDERR, '[register] InstallModule failed: ' . ($res[1] ?? 'unknown error') . "\n");
            exit(1);
        }
        echo "[register] module $name installed\n";
    } elseif ($type === 'theme') {
        $adminUser = getenv('CMSMS_ADMIN_USER') ?: 'admin';
        $uid = (int)$db->GetOne('SELECT user_id FROM ' . CMS_DB_PREFIX . 'users WHERE username = ?', [$adminUser]);
        if ($uid < 1) { fwrite(STDERR, "[register] admin user '$adminUser' not found\n"); exit(1); }
        cms_userprefs::set_for_user($uid, 'admintheme', $name);
        echo "[register] admin theme set to $name for user $adminUser\n";
    } else {
        fwrite(STDERR, "[register] unknown type '$type'\n");
        exit(2);
    }
} catch (\Throwable $t) {
    fwrite(STDERR, '[register] FAILED: ' . $t->getMessage() . "\n");
    exit(1);
}
