<?php
if (!defined('CMS_VERSION')) exit;

class SkeletonTest extends CMSModule
{
    public function GetName() { return 'SkeletonTest'; }
    public function GetFriendlyName() { return 'Skeleton Test Module'; }
    public function GetVersion() { return '1.0.0'; }
    public function GetAuthor() { return 'ddev-cmsms tests'; }
    public function MinimumCMSVersion() { return '2.2.0'; }
    public function IsPluginModule() { return true; }
    public function HasAdmin() { return false; }

    public function DoAction($name, $id, $params, $returnid = -1)
    {
        if ($name == 'default') { echo 'SkeletonTest works'; return; }
        parent::DoAction($name, $id, $params, $returnid);
    }
}
