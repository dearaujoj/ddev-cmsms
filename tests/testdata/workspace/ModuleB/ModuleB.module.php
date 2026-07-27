<?php
if (!defined('CMS_VERSION')) exit;

class ModuleB extends CMSModule
{
    public function GetName() { return 'ModuleB'; }
    public function GetFriendlyName() { return 'Workspace Module B'; }
    public function GetVersion() { return '1.0.0'; }
    public function GetAuthor() { return 'ddev-cmsms tests'; }
    public function MinimumCMSVersion() { return '2.2.0'; }
    public function IsPluginModule() { return true; }
    public function HasAdmin() { return false; }

    // Declaration order matters: ModuleA must be installed before ModuleB —
    // CMSMS refuses to install a module whose dependencies are absent.
    public function GetDependencies() { return ['ModuleA' => '1.0.0']; }
}
