<?php

declare(strict_types=1);

use Utatane\ValidatorWeb\ValidationSlot;
use Utatane\ValidatorWeb\RuntimeStorage;

require_once dirname(__DIR__) . '/src/RuntimeStorage.php';
require_once dirname(__DIR__) . '/src/ValidationSlot.php';

$runtimeDirectory = sys_get_temp_dir() . '/utatane-validator-slot-test-' . bin2hex(random_bytes(8));
$first = ValidationSlot::acquire($runtimeDirectory, 1);
if ($first === null) {
    throw new RuntimeException('Could not acquire the initial validation slot.');
}

$startedAt = microtime(true);
$blocked = ValidationSlot::acquire($runtimeDirectory, 1, 1);
$elapsed = microtime(true) - $startedAt;
if ($blocked !== null) {
    throw new RuntimeException('Acquired a validation slot while it was locked.');
}
if ($elapsed < 0.9 || $elapsed > 2.0) {
    throw new RuntimeException('Validation slot wait did not respect its deadline.');
}

unset($first);
$released = ValidationSlot::acquire($runtimeDirectory, 1);
if ($released === null) {
    throw new RuntimeException('Could not acquire a released validation slot.');
}

unset($released);
$permissions = fileperms($runtimeDirectory) & 0777;
if ($permissions !== 0700) {
    throw new RuntimeException('Runtime directory permissions are not private.');
}
RuntimeStorage::removeTree($runtimeDirectory);

echo "ValidationSlotTest passed\n";
