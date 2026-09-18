<?php

declare(strict_types=1);

use Utatane\ValidatorWeb\Http;

require_once dirname(__DIR__) . '/src/Http.php';

$uploadPath = '/tmp/php-upload-123';
$report = Http::sanitizeValidationReport([
    'rootPath' => $uploadPath,
    'diagnostics' => [[
        'message' => '文字コードを判定できない: /tmp/utatane-validate-ABC-123/shell/master/surfaces.txt',
        'path' => $uploadPath,
    ]],
], $uploadPath);

if ($report['rootPath'] !== 'uploaded.nar') {
    throw new RuntimeException('The report root path was not sanitized.');
}
$diagnostic = $report['diagnostics'][0];
if ($diagnostic['path'] !== 'uploaded.nar') {
    throw new RuntimeException('The uploaded temporary path was not sanitized.');
}
if ($diagnostic['message'] !== '文字コードを判定できない: shell/master/surfaces.txt') {
    throw new RuntimeException('The extraction temporary path was not sanitized.');
}

echo "HttpTest passed\n";
