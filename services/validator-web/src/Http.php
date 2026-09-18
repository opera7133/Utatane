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
}
