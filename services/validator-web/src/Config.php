<?php

declare(strict_types=1);

namespace Utatane\ValidatorWeb;

final readonly class Config
{
    public function __construct(
        public string $validatorBinary,
        public int $maximumUploadBytes,
        public int $validatorTimeoutSeconds,
        public int $maximumOutputBytes,
        public int $concurrency,
    ) {
    }

    public static function fromEnvironment(string $projectRoot): self
    {
        return new self(
            validatorBinary: self::environmentString(
                'UTATANE_VALIDATE_BINARY',
                $projectRoot . '/bin/utatane-validate'
            ),
            maximumUploadBytes: self::environmentInt('UTATANE_VALIDATE_MAX_BYTES', 50 * 1024 * 1024),
            validatorTimeoutSeconds: self::environmentInt('UTATANE_VALIDATE_TIMEOUT_SECONDS', 15),
            maximumOutputBytes: self::environmentInt('UTATANE_VALIDATE_MAX_OUTPUT_BYTES', 2 * 1024 * 1024),
            concurrency: self::environmentInt('UTATANE_VALIDATE_CONCURRENCY', 2),
        );
    }

    private static function environmentString(string $name, string $default): string
    {
        $value = getenv($name);
        return is_string($value) && $value !== '' ? $value : $default;
    }

    private static function environmentInt(string $name, int $default): int
    {
        $value = getenv($name);
        if (!is_string($value) || filter_var($value, FILTER_VALIDATE_INT) === false) {
            return $default;
        }
        return max(1, (int) $value);
    }
}
