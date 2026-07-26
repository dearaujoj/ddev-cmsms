<?php
#ddev-generated
if (!defined('CMS_VERSION')) exit;

class __NAME__ extends CMSModule
{
    public function GetName() { return '__NAME__'; }
    public function GetFriendlyName() { return $this->Lang('friendlyname'); }
    public function GetVersion() { return '0.0.1'; }
    public function GetAuthor() { return ''; }
    public function MinimumCMSVersion() { return '2.2.0'; }

    // Allows using {__NAME__} as a tag in page templates (runs action.default.php).
    public function IsPluginModule() { return true; }

    // Shows an admin panel under Extensions (runs action.defaultadmin.php).
    public function HasAdmin() { return true; }
    public function GetAdminSection() { return 'extensions'; }
    public function VisibleToAdminUser() { return $this->CheckPermission('Modify Modules'); }
}
