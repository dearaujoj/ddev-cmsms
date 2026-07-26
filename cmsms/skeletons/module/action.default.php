<?php
#ddev-generated
if (!defined('CMS_VERSION')) exit;

// Frontend action: runs for {__NAME__} tags in page templates.
// $params holds the tag parameters, e.g. {__NAME__ foo="bar"} => $params['foo'].
$this->smarty->assign('message', $this->Lang('hello'));
echo $this->ProcessTemplate('default.tpl');
