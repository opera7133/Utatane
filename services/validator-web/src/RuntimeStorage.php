<?php

declare(strict_types=1);

namespace Utatane\ValidatorWeb;

use RuntimeException;

final class RuntimeStorage
{
    public static function directory(string $baseDirectory, string $name): string
    {
        self::ensurePrivateDirectory($baseDirectory);
        $directory = rtrim($baseDirectory, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . $name;
        self::ensurePrivateDirectory($directory);
        return $directory;
    }

    public static function createWorkspace(string $baseDirectory): string
    {
        $workDirectory = self::directory($baseDirectory, 'work');
        self::removeStaleWorkspaces($workDirectory);

        for ($attempt = 0; $attempt < 3; ++$attempt) {
            $workspace = $workDirectory . DIRECTORY_SEPARATOR . 'request-' . bin2hex(random_bytes(16));
            if (@mkdir($workspace, 0700)) {
                return $workspace;
            }
        }
        throw new RuntimeException('Validator workspace could not be created.');
    }

    public static function removeTree(string $path): void
    {
        if (is_link($path) || is_file($path)) {
            @unlink($path);
            return;
        }
        if (!is_dir($path)) {
            return;
        }
        $children = scandir($path);
        if (is_array($children)) {
            foreach ($children as $child) {
                if ($child === '.' || $child === '..') {
                    continue;
                }
                self::removeTree($path . DIRECTORY_SEPARATOR . $child);
            }
        }
        @rmdir($path);
    }

    private static function ensurePrivateDirectory(string $directory): void
    {
        if (is_link($directory)) {
            throw new RuntimeException('Validator runtime directory must not be a symbolic link.');
        }
        if (!is_dir($directory) && !@mkdir($directory, 0700, true) && !is_dir($directory)) {
            throw new RuntimeException('Validator runtime directory could not be created.');
        }
        if (!@chmod($directory, 0700)) {
            throw new RuntimeException('Validator runtime directory permissions could not be restricted.');
        }
    }

    private static function removeStaleWorkspaces(string $workDirectory): void
    {
        $children = scandir($workDirectory);
        if (!is_array($children)) {
            return;
        }
        $cutoff = time() - 3600;
        foreach ($children as $child) {
            if (!str_starts_with($child, 'request-')) {
                continue;
            }
            $path = $workDirectory . DIRECTORY_SEPARATOR . $child;
            $modifiedAt = @filemtime($path);
            if ($modifiedAt !== false && $modifiedAt < $cutoff) {
                self::removeTree($path);
            }
        }
    }
}
