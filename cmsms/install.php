<?php
#ddev-generated
/**
 * Headless CMSMS database installer for ddev-cmsms.
 * Replicates wizard_step8::do_install() + wizard_step9::do_install() from the
 * official phar installer (which refuses CLI) by including the installer's own
 * app/install/*.php scripts with the scope/functions they expect.
 * Usage: php install.php <docroot> <installer_appdir> <sitename>
 */

namespace __appbase {
    // Stub for the installer-app context that base.php/initial.php reach via get_app().
    class ddev_app {
        private $destdir;
        public function __construct($destdir) { $this->destdir = $destdir; }
        public function get_destdir() { return $this->destdir; }
    }
    function get_app() { return $GLOBALS['DDEV_APP']; }
}

namespace {

// Old CMSMS 2.2.x code triggers PHP 8.3 deprecation/notice noise (dynamic
// properties, ${} string interpolation, etc.) that would otherwise spam
// stderr without affecting the install; silence it here so real failures
// stand out.
error_reporting(E_ALL & ~E_DEPRECATED & ~E_NOTICE & ~E_WARNING);

function ilang(...$args) { $key = array_shift($args); return $args ? $key.' '.implode(' ', array_map('strval', $args)) : $key; }
function status_msg($str) { echo "[cmsms-db] $str\n"; }
function verbose_msg($str) { if (getenv('CMSMS_INSTALL_VERBOSE')) echo "    $str\n"; }

$destdir  = rtrim($argv[1] ?? '', '/');
$appdir   = rtrim($argv[2] ?? '', '/');
$sitename = $argv[3] ?? 'CMSMS Dev Site';

if (!is_file("$destdir/lib/include.php")) { fwrite(STDERR, "core not found in '$destdir'\n"); exit(2); }
if (!is_file("$appdir/install/schema.php")) { fwrite(STDERR, "installer app not found in '$appdir'\n"); exit(2); }

$GLOBALS['DDEV_APP'] = new \__appbase\ddev_app($destdir);

// Exact version metadata from the payload being installed.
include dirname($appdir) . '/data/version.php'; // $CMS_VERSION, $CMS_VERSION_NAME, $CMS_SCHEMA_VERSION

global $CMS_INSTALL_PAGE, $DONT_LOAD_DB, $DONT_LOAD_SMARTY, $CMS_PHAR_INSTALLER;
$CMS_INSTALL_PAGE = 1;
$DONT_LOAD_DB = 1;
$DONT_LOAD_SMARTY = 1;
$CMS_PHAR_INSTALLER = 1;

include_once "$destdir/lib/include.php";

// The core's install-mode bootstrap (DONT_LOAD_SMARTY + CMS_PHAR_INSTALLER)
// deliberately skips CmsApp::GetSmarty(), so the Smarty library autoloader is
// never registered. In the real phar installer this is masked: the wizard UI
// itself renders every step through its own bundled Smarty copy, so by the
// time wizard_step8/9 run, Smarty's autoloader is already active as a side
// effect. Our headless driver renders nothing, so install/initial.php's use
// of CmsLayoutTemplateType -> CmsTemplateResource -> Smarty_Resource_Custom
// would otherwise fatal with "Class Smarty_Resource_Custom not found".
// Load the core's own Smarty library directly to register that autoloader.
require_once "$destdir/lib/smarty/Smarty.class.php";

// --- connect to DB (mirrors wizard_step8::db_connect) ---
$spec = new \CMSMS\Database\ConnectionSpec;
$spec->type = 'mysqli';
$spec->host = 'db';
$spec->username = 'db';
$spec->password = 'db';
$spec->dbname = 'db';
$spec->prefix = 'cms_';
if (!defined('CMS_DB_PREFIX')) define('CMS_DB_PREFIX', $spec->prefix);
$db = \CMSMS\Database\Connection::initialize($spec);
$db->SetErrorHandler(function() {});
$db->Execute("SET NAMES 'utf8'");
\CMSMS\Database\compatibility::noop();
\CmsApp::get_instance()->_setDb($db);

// --- scope the install scripts expect ---
if (!defined('CMS_ADODB_DT')) define('CMS_ADODB_DT', 'DT');
$admin_user = null;
$db_prefix = CMS_DB_PREFIX;
$adminaccount = [
    'username'  => getenv('CMSMS_ADMIN_USER') ?: 'admin',
    'password'  => getenv('CMSMS_ADMIN_PASSWORD') ?: 'admin',
    'emailaddr' => 'admin@example.com',
    'saltpw'    => 1,
];

try {
    global $CMS_INSTALL_DROP_TABLES, $CMS_INSTALL_CREATE_TABLES;
    $CMS_INSTALL_DROP_TABLES = 1;
    $CMS_INSTALL_CREATE_TABLES = 1;
    status_msg('installing schema');
    include_once "$appdir/install/schema.php";
    include_once "$appdir/install/createseq.php";

    // password salt must exist before base.php hashes the admin password
    $salt = substr(str_shuffle(md5($destdir . time())), 0, 16);
    cms_siteprefs::set('sitemask', $salt);

    @mkdir("$destdir/tmp/cache", 0777, true);
    @mkdir("$destdir/tmp/templates_c", 0777, true);

    status_msg('creating base data and admin account');
    include_once "$appdir/install/base.php";

    status_msg('installing default content');
    $contentfile = getenv('CMSMS_SAMPLE_CONTENT') ? "$appdir/install/extra.php" : "$appdir/install/initial.php";
    include_once $contentfile;

    cms_siteprefs::set('sitename', $sitename);
    cmsms()->GetContentOperations()->SetAllHierarchyPositions();
    set_site_preference('global_umask', '022');

    // wizard_step9: force-load system modules so each self-installs
    status_msg('installing system modules');
    $modops = cmsms()->GetModuleOperations();
    foreach ($modops->FindAllModules() as $name) {
        if ($modops->IsSystemModule($name)) {
            verbose_msg("loading module $name");
            $mod = $modops->get_module_instance($name, '', TRUE);
            if (!is_object($mod)) fwrite(STDERR, "warning: could not load module $name\n");
        }
    }

    // route CMSMS mail through DDEV's Mailpit (best effort)
    try {
        cms_siteprefs::set('mailprefs', serialize([
            'mailer' => 'smtp', 'host' => 'localhost', 'port' => 1025,
            'from' => 'admin@example.com', 'fromuser' => 'CMSMS Dev',
            'secure' => '', 'smtpauth' => 0, 'username' => '', 'password' => '',
            'timeout' => 60, 'charset' => 'utf-8',
        ]));
    } catch (\Throwable $t) { /* non-fatal */ }

    cmsms()->clear_cached_files();
    status_msg("done — CMSMS $CMS_VERSION installed");
} catch (\Throwable $t) {
    fwrite(STDERR, '[cmsms-db] FAILED: ' . $t->getMessage() . "\n" . $t->getTraceAsString() . "\n");
    exit(1);
}
}
