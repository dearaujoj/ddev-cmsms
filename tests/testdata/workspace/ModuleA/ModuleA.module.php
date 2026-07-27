<?php
if (!defined('CMS_VERSION')) exit;

class ModuleA extends CMSModule
{
    public function GetName() { return 'ModuleA'; }
    public function GetFriendlyName() { return 'Workspace Module A'; }
    public function GetVersion() { return '1.0.0'; }
    public function GetAuthor() { return 'ddev-cmsms tests'; }
    public function MinimumCMSVersion() { return '2.2.0'; }
    public function IsPluginModule() { return true; }
    public function HasAdmin() { return false; }
}
