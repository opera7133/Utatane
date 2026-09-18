<?php

declare(strict_types=1);

use Utatane\ValidatorWeb\Config;
use Utatane\ValidatorWeb\Http;
use Utatane\ValidatorWeb\ValidationSlot;
use Utatane\ValidatorWeb\ValidatorProcess;

$projectRoot = dirname(__DIR__);
require_once $projectRoot . '/src/bootstrap.php';

$requestId = bin2hex(random_bytes(8));
Http::applySecurityHeaders($requestId);
$config = Config::fromEnvironment($projectRoot);
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

if ($method === 'GET' && $path === '/') {
    header('Content-Type: text/html; charset=utf-8');
    require $projectRoot . '/views/home.php';
    exit;
}

if ($method === 'GET' && $path === '/licenses') {
    header('Content-Type: text/html; charset=utf-8');
    require $projectRoot . '/views/licenses.php';
    exit;
}

if ($method === 'GET' && $path === '/api/v1/health') {
    Http::json([
        'ok' => true,
        'maximumUploadBytes' => $config->maximumUploadBytes,
        'requestId' => $requestId,
    ]);
}

if ($method !== 'POST' || $path !== '/api/v1/validate') {
    Http::error($requestId, 'route.not-found', 'Endpoint not found.', 404);
}

$contentType = $_SERVER['CONTENT_TYPE'] ?? '';
if (!str_starts_with(strtolower($contentType), 'multipart/form-data')) {
    Http::error($requestId, 'request.content-type', 'multipart/form-data で送信してください。', 415);
}

$contentLength = filter_var($_SERVER['CONTENT_LENGTH'] ?? null, FILTER_VALIDATE_INT);
if (is_int($contentLength) && $contentLength > $config->maximumUploadBytes + 1024 * 1024) {
    Http::error($requestId, 'upload.too-large', 'ファイルサイズは50 MBまでです。', 413);
}

$upload = $_FILES['file'] ?? null;
if (!is_array($upload) || !isset($upload['error'], $upload['tmp_name'], $upload['size'])) {
    Http::error($requestId, 'upload.missing', 'file フィールドにNARファイルを指定してください。', 400);
}
if ((int) $upload['error'] !== UPLOAD_ERR_OK) {
    $status = (int) $upload['error'] === UPLOAD_ERR_INI_SIZE || (int) $upload['error'] === UPLOAD_ERR_FORM_SIZE
        ? 413
        : 400;
    Http::error($requestId, 'upload.failed', 'アップロードを受け取れませんでした。', $status);
}

$temporaryPath = (string) $upload['tmp_name'];
if (!is_uploaded_file($temporaryPath)) {
    Http::error($requestId, 'upload.invalid', 'アップロードされたファイルを確認できません。', 400);
}
$actualSize = filesize($temporaryPath);
if ($actualSize === false) {
    Http::error($requestId, 'upload.invalid', 'アップロードされたファイルサイズを確認できません。', 400);
}
$uploadSize = (int) $actualSize;
if ($uploadSize <= 0) {
    Http::error($requestId, 'upload.empty', '空のファイルは検査できません。', 400);
}
if ($uploadSize > $config->maximumUploadBytes) {
    Http::error($requestId, 'upload.too-large', 'ファイルサイズは50 MBまでです。', 413);
}

$input = fopen($temporaryPath, 'rb');
$signature = $input !== false ? fread($input, 4) : false;
if ($input !== false) {
    fclose($input);
}
if (!is_string($signature) || !in_array($signature, ["PK\x03\x04", "PK\x05\x06", "PK\x07\x08"], true)) {
    Http::error($requestId, 'upload.not-zip', 'NARまたはZIP形式のファイルを指定してください。', 400);
}

$slot = ValidationSlot::acquire($config->concurrency, $config->queueWaitSeconds);
if ($slot === null) {
    header('Retry-After: 5');
    Http::error($requestId, 'service.busy', '現在ほかのファイルを検査中です。少し待って再試行してください。', 429);
}

try {
    $result = (new ValidatorProcess($config))->run($temporaryPath);
} catch (Throwable $error) {
    error_log('[utatane-validator][' . $requestId . '] ' . $error->getMessage());
    Http::error($requestId, 'validator.failed', '検査プログラムを実行できませんでした。', 500);
}
if ($result->timedOut) {
    Http::error($requestId, 'validator.timeout', '検査が制限時間を超えました。', 504);
}
if (!in_array($result->exitCode, [0, 1], true)) {
    error_log('[utatane-validator][' . $requestId . '] unexpected exit=' . $result->exitCode
        . '; stderr=' . substr($result->stderr, 0, 2048));
    Http::error($requestId, 'validator.failed', '検査プログラムが異常終了しました。', 500);
}

try {
    $report = json_decode($result->stdout, true, 128, JSON_THROW_ON_ERROR);
} catch (JsonException $error) {
    error_log('[utatane-validator][' . $requestId . '] invalid JSON; exit=' . $result->exitCode
        . '; stderr=' . substr($result->stderr, 0, 2048));
    Http::error($requestId, 'validator.invalid-response', '検査結果を読み取れませんでした。', 500);
}
if (!is_array($report) || !isset($report['diagnostics'])) {
    Http::error($requestId, 'validator.invalid-response', '検査結果の形式が正しくありません。', 500);
}
$report['rootPath'] = 'uploaded.nar';

Http::json([
    'ok' => true,
    'report' => $report,
    'requestId' => $requestId,
]);
