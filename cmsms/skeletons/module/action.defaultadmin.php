<?php
#ddev-generated
if (!defined('CMS_VERSION')) exit;
if (!$this->VisibleToAdminUser()) exit;

// Admin panel: what shows under Extensions > __NAME__.
echo '<h3>' . $this->Lang('friendlyname') . '</h3>';
echo '<p>' . $this->Lang('hello') . '</p>';
