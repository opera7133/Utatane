<?php

declare(strict_types=1);

$licenses = [
    'Utatane' => file_get_contents(dirname(__DIR__) . '/licenses/Utatane.txt'),
    'ZIP Foundation' => file_get_contents(dirname(__DIR__) . '/licenses/ZIPFoundation.txt'),
];
?>
<!doctype html>
<html lang="ja">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="Utatane NAR検査で使用しているソフトウェアのライセンスです。">
    <meta name="robots" content="noindex,follow">
    <title>ライセンス - Utatane NAR検査</title>
    <link rel="canonical" href="https://utatane-validate.wmsci.com/licenses">
    <link rel="icon" href="/assets/utatane-icon.png" type="image/png" sizes="512x512">
    <link rel="apple-touch-icon" href="/assets/utatane-icon.png">
    <link rel="stylesheet" href="/assets/app.css">
</head>
<body>
<header class="navbar">
    <div class="container navbar-content">
        <a class="navbar-brand" href="/">Utatane NAR検査</a>
    </div>
</header>
<main class="container license-page">
    <h1>ライセンス</h1>
    <p>このサービスで使用しているソフトウェアのライセンスです。</p>
    <?php foreach ($licenses as $name => $text): ?>
        <section>
            <h2><?= htmlspecialchars($name, ENT_QUOTES) ?></h2>
            <pre><?= htmlspecialchars((string) $text, ENT_QUOTES) ?></pre>
        </section>
    <?php endforeach; ?>
</main>
</body>
</html>
