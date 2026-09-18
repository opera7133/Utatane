<?php

declare(strict_types=1);

namespace Utatane\ValidatorWeb;

final class Http
{
    public static function applySecurityHeaders(string $requestId): void
    {
        header_remove('X-Powered-By');
        header('Cache-Control: no-store');
        header("Content-Security-Policy: default-src 'none'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
        header('Referrer-Policy: no-referrer');
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('X-Request-Id: ' . $requestId);
    }

    /** @param array<string, mixed> $body */
    public static function json(array $body, int $status = 200): never
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR), "\n";
        exit;
    }

    public static function error(string $requestId, string $code, string $message, int $status): never
    {
        self::json([
            'ok' => false,
            'error' => [
                'code' => $code,
                'message' => $message,
            ],
            'requestId' => $requestId,
        ], $status);
    }

    /** @param array<string, mixed> $report @return array<string, mixed> */
    public static function sanitizeValidationReport(array $report, string $uploadTemporaryPath): array
    {
        $report['rootPath'] = 'uploaded.nar';
        if (!isset($report['diagnostics']) || !is_array($report['diagnostics'])) {
            return $report;
        }
        foreach ($report['diagnostics'] as &$diagnostic) {
            if (!is_array($diagnostic)) {
                continue;
            }
            foreach (['message', 'path'] as $field) {
                if (!isset($diagnostic[$field]) || !is_string($diagnostic[$field])) {
                    continue;
                }
                $diagnostic[$field] = str_replace(
                    $uploadTemporaryPath,
                    'uploaded.nar',
                    $diagnostic[$field]
                );
                $diagnostic[$field] = preg_replace(
                    '~(?:/private)?/tmp/utatane-validate-[A-F0-9-]+/?~i',
                    '',
                    $diagnostic[$field]
                ) ?? $diagnostic[$field];
            }
        }
        unset($diagnostic);
        return $report;
    }
}
