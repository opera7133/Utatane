<?php

declare(strict_types=1);

namespace Utatane\ValidatorWeb;

use RuntimeException;

final readonly class ValidatorProcessResult
{
    public function __construct(
        public int $exitCode,
        public string $stdout,
        public string $stderr,
        public bool $timedOut,
    ) {
    }
}

final class ValidatorProcess
{
    public function __construct(private readonly Config $config)
    {
    }

    public function run(string $archivePath): ValidatorProcessResult
    {
        if (!is_file($this->config->validatorBinary) || !is_executable($this->config->validatorBinary)) {
            throw new RuntimeException('Validator binary is unavailable.');
        }

        $descriptors = [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ];
        $process = proc_open(
            [$this->config->validatorBinary, '--json', '--archive', $archivePath],
            $descriptors,
            $pipes,
            null,
            null,
            ['bypass_shell' => true]
        );
        if (!is_resource($process)) {
            throw new RuntimeException('Validator process could not be started.');
        }

        fclose($pipes[0]);
        stream_set_blocking($pipes[1], false);
        stream_set_blocking($pipes[2], false);
        $deadline = microtime(true) + $this->config->validatorTimeoutSeconds;
        $stdout = '';
        $stderr = '';
        $timedOut = false;
        $exitCode = -1;

        try {
            while (true) {
                $stdout .= stream_get_contents($pipes[1]) ?: '';
                $stderr .= stream_get_contents($pipes[2]) ?: '';
                if (strlen($stdout) > $this->config->maximumOutputBytes || strlen($stderr) > 64 * 1024) {
                    proc_terminate($process, 9);
                    throw new RuntimeException('Validator output exceeded its limit.');
                }

                $status = proc_get_status($process);
                if (!$status['running']) {
                    $exitCode = (int) $status['exitcode'];
                    break;
                }
                if (microtime(true) >= $deadline) {
                    $timedOut = true;
                    proc_terminate($process);
                    usleep(100_000);
                    $status = proc_get_status($process);
                    if ($status['running']) {
                        proc_terminate($process, 9);
                    }
                    break;
                }
                usleep(10_000);
            }
            $stdout .= stream_get_contents($pipes[1]) ?: '';
            $stderr .= stream_get_contents($pipes[2]) ?: '';
        } finally {
            fclose($pipes[1]);
            fclose($pipes[2]);
            $closedExitCode = proc_close($process);
            if ($exitCode < 0 && $closedExitCode >= 0) {
                $exitCode = $closedExitCode;
            }
        }

        return new ValidatorProcessResult($exitCode, $stdout, $stderr, $timedOut);
    }
}
