<?php

declare(strict_types=1);

namespace Utatane\ValidatorWeb;

final class ValidationSlot
{
    /** @var resource */
    private $handle;

    /** @param resource $handle */
    private function __construct($handle)
    {
        $this->handle = $handle;
    }

    public static function acquire(int $concurrency, int $waitSeconds = 0): ?self
    {
        $prefix = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
        $deadline = microtime(true) + max(0, $waitSeconds);

        do {
            for ($index = 0; $index < $concurrency; ++$index) {
                $handle = @fopen($prefix . 'utatane-validator-slot-' . $index . '.lock', 'c');
                if ($handle !== false && flock($handle, LOCK_EX | LOCK_NB)) {
                    return new self($handle);
                }
                if ($handle !== false) {
                    fclose($handle);
                }
            }
            if (microtime(true) >= $deadline) {
                break;
            }
            usleep(100_000);
        } while (true);

        return null;
    }

    public function __destruct()
    {
        flock($this->handle, LOCK_UN);
        fclose($this->handle);
    }
}
