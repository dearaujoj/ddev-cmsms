<?php
#ddev-generated
// File-based Smarty plugin. Use in any template as {__name__} or {__name__ name="World"}.
function smarty_function___name__($params, $template)
{
    $name = isset($params['name']) ? $params['name'] : '__NAME__';
    return "Hello, {$name}!";
}
