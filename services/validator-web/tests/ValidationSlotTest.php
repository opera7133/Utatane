<?php

declare(strict_types=1);

use Utatane\ValidatorWeb\ValidationSlot;

require_once dirname(__DIR__) . '/src/ValidationSlot.php';

$first = ValidationSlot::acquire(1);
if ($first === null) {
    throw new RuntimeException('Could not acquire the initial validation slot.');
}

$startedAt = microtime(true);
$blocked = ValidationSlot::acquire(1, 1);
$elapsed = microtime(true) - $startedAt;
if ($blocked !== null) {
    throw new RuntimeException('Acquired a validation slot while it was locked.');
}
if ($elapsed < 0.9 || $elapsed > 2.0) {
    throw new RuntimeException('Validation slot wait did not respect its deadline.');
}

unset($first);
$released = ValidationSlot::acquire(1);
if ($released === null) {
    throw new RuntimeException('Could not acquire a released validation slot.');
}

echo "ValidationSlotTest passed\n";
