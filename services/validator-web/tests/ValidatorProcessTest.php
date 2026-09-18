<?php

declare(strict_types=1);

use Utatane\ValidatorWeb\Config;
use Utatane\ValidatorWeb\RuntimeStorage;
use Utatane\ValidatorWeb\ValidatorProcess;

require_once dirname(__DIR__) . '/src/Config.php';
require_once dirname(__DIR__) . '/src/RuntimeStorage.php';
require_once dirname(__DIR__) . '/src/ValidatorProcess.php';

$testDirectory = sys_get_temp_dir() . '/utatane-validator-process-test-' . bin2hex(random_bytes(8));
if (!mkdir($testDirectory, 0700)) {
    throw new RuntimeException('Could not create the process test directory.');
}
$validator = $testDirectory . '/validator.sh';
file_put_contents($validator, <<<'SH'
#!/bin/sh
set -eu
test -n "${TMPDIR:-}"
mkdir "$TMPDIR/extracted"
printf '%s\n' '{"diagnostics":[]}'
SH
);
chmod($validator, 0700);

$runtimeDirectory = $testDirectory . '/runtime';
$config = new Config(
    validatorBinary: $validator,
    runtimeDirectory: $runtimeDirectory,
    maximumUploadBytes: 1024,
    validatorTimeoutSeconds: 2,
    maximumOutputBytes: 1024,
    maximumProcessMemoryBytes: 256 * 1024 * 1024,
    concurrency: 1,
    queueWaitSeconds: 0,
);

try {
    $result = (new ValidatorProcess($config))->run(__FILE__);
    if ($result->exitCode !== 0 || trim($result->stdout) !== '{"diagnostics":[]}') {
        throw new RuntimeException('The validator fixture did not run successfully.');
    }
    $workDirectory = $runtimeDirectory . '/work';
    $remaining = array_values(array_diff(scandir($workDirectory) ?: [], ['.', '..']));
    if ($remaining !== []) {
        throw new RuntimeException('The validator workspace was not removed.');
    }
    if ((fileperms($runtimeDirectory) & 0777) !== 0700) {
        throw new RuntimeException('The validator runtime directory is not private.');
    }

    $stale = $workDirectory . '/request-stale';
    mkdir($stale, 0700);
    file_put_contents($stale . '/partial', 'stale');
    touch($stale, time() - 7200);
    $workspace = RuntimeStorage::createWorkspace($runtimeDirectory);
    if (is_dir($stale)) {
        throw new RuntimeException('A stale validator workspace was not removed.');
    }
    RuntimeStorage::removeTree($workspace);

    $slowValidator = $testDirectory . '/slow-validator.sh';
    file_put_contents($slowValidator, <<<'SH'
#!/bin/sh
set -eu
mkdir "$TMPDIR/partial"
while :; do :; done
SH
    );
    chmod($slowValidator, 0700);
    $timeoutConfig = new Config(
        validatorBinary: $slowValidator,
        runtimeDirectory: $runtimeDirectory,
        maximumUploadBytes: 1024,
        validatorTimeoutSeconds: 1,
        maximumOutputBytes: 1024,
        maximumProcessMemoryBytes: 256 * 1024 * 1024,
        concurrency: 1,
        queueWaitSeconds: 0,
    );
    $timeoutResult = (new ValidatorProcess($timeoutConfig))->run(__FILE__);
    if (!$timeoutResult->timedOut) {
        throw new RuntimeException('The slow validator did not time out.');
    }
    $remaining = array_values(array_diff(scandir($workDirectory) ?: [], ['.', '..']));
    if ($remaining !== []) {
        throw new RuntimeException('The timed-out validator workspace was not removed.');
    }
} finally {
    RuntimeStorage::removeTree($testDirectory);
}

echo "ValidatorProcessTest passed\n";
