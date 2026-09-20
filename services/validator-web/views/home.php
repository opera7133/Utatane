<?php

declare(strict_types=1);

/** @var \Utatane\ValidatorWeb\Config $config */
$maximumMegabytes = (int) floor($config->maximumUploadBytes / 1024 / 1024);
?>
<!doctype html>
<html lang="ja">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="NARファイルをアップロードして、Utataneで利用できるか確認します。">
    <meta name="robots" content="index,follow">
    <title>Utatane NAR検査</title>
    <link rel="canonical" href="https://utatane-validate.wmsci.com/">
    <link rel="icon" href="/assets/utatane-icon.png" type="image/png" sizes="512x512">
    <link rel="apple-touch-icon" href="/assets/utatane-icon.png">
    <meta property="og:type" content="website">
    <meta property="og:locale" content="ja_JP">
    <meta property="og:site_name" content="Utatane NAR検査">
    <meta property="og:title" content="Utatane NAR検査">
    <meta property="og:description" content="NARファイルをアップロードして、ゴーストの構成、SHIORI、Utataneでの対応状況を確認できます。">
    <meta property="og:url" content="https://utatane-validate.wmsci.com/">
    <meta property="og:image" content="https://utatane-validate.wmsci.com/assets/utatane-icon.png">
    <meta property="og:image:width" content="512">
    <meta property="og:image:height" content="512">
    <meta property="og:image:alt" content="Utataneのアプリアイコン">
    <meta name="twitter:card" content="summary">
    <meta name="twitter:title" content="Utatane NAR検査">
    <meta name="twitter:description" content="NARファイルから、ゴーストの構成とUtataneでの対応状況を確認します。">
    <meta name="twitter:image" content="https://utatane-validate.wmsci.com/assets/utatane-icon.png">
    <meta name="twitter:image:alt" content="Utataneのアプリアイコン">
    <link rel="stylesheet" href="/assets/app.css">
    <script src="/assets/app.js" defer></script>
</head>
<body data-maximum-bytes="<?= htmlspecialchars((string) $config->maximumUploadBytes, ENT_QUOTES) ?>">
<header class="navbar">
    <div class="container navbar-content">
        <a class="navbar-brand" href="/">Utatane NAR検査</a>
        <a href="https://dl.wmsci.com/utatane/" rel="external">by Utatane</a>
    </div>
</header>

<main class="container">
    <section class="intro" aria-labelledby="page-title">
        <h1 id="page-title">NARファイルを検査</h1>
        <p>ゴーストの構成とSHIORIを調べ、Utataneでの対応状況を表示します。</p>
    </section>

    <section class="card" aria-labelledby="checker-title">
        <div class="card-header">
            <h2 id="checker-title">ファイルを選択</h2>
            <span>最大 <?= $maximumMegabytes ?> MB</span>
        </div>

        <form id="validation-form" enctype="multipart/form-data" novalidate>
            <label class="drop-zone" id="drop-zone" for="nar-file">
                <input id="nar-file" name="file" type="file" accept=".nar,.zip,application/zip" required>
                <strong>NARファイルをここにドロップ</strong>
                <span>またはクリックして選択</span>
            </label>
            <div class="selected-file" id="selected-file" hidden>
                <div>
                    <strong id="file-name"></strong>
                    <span id="file-size"></span>
                </div>
                <button class="button-primary" id="submit-button" type="submit">検査する</button>
            </div>
        </form>

        <div class="alert alert-info" id="progress" role="status" aria-live="polite" hidden>
            <span class="spinner" aria-hidden="true"></span>
            <span id="progress-message">NARファイルを検査しています。</span>
        </div>
        <div class="alert alert-error" id="request-error" role="alert" hidden></div>
    </section>

    <section class="card results" id="results" aria-labelledby="results-title" hidden>
        <div class="card-header">
            <h2 id="results-title">検査結果</h2>
            <span class="result-state" id="result-state"></span>
        </div>

        <dl class="result-summary">
            <div><dt>ゴースト</dt><dd id="ghost-name">—</dd></div>
            <div>
                <dt>SHIORI</dt>
                <dd><span id="shiori-name">—</span> <span class="support-badge" id="support-badge">判定不能</span></dd>
            </div>
        </dl>
        <dl class="shiori-details" id="shiori-details"></dl>
        <p class="summary-text" id="summary-text"></p>
        <p class="result-note">※ 検査結果は、必ずしもUtataneで問題なく動作することを保証するものではありません。</p>

        <details class="diagnostics-block" open>
            <summary>検査内容 <span id="diagnostic-count"></span></summary>
            <div id="diagnostics"></div>
        </details>
        <div class="result-actions">
            <button class="button-secondary" id="download-report" type="button" hidden>検査結果をJSONで保存</button>
        </div>
        <p class="request-id" id="request-id"></p>
    </section>

    <p class="file-note">アップロードされたファイルは検査後に自動で削除されます。</p>

    <section class="api-docs" aria-labelledby="api-title">
        <h2 id="api-title">API</h2>
        <p>NARファイルをプログラムから検査できます。認証は不要です。</p>

        <h3><code>POST /api/v1/validate</code></h3>
        <p><code>multipart/form-data</code>の<code>file</code>フィールドに、50 MB以下のNARファイルを指定します。</p>
        <pre><code>curl -F file=@ghost.nar \
  https://utatane-validate.wmsci.com/api/v1/validate</code></pre>

        <p>成功時は、ゴースト名、SHIORIの判定、Utataneでの対応状況、検査結果をJSONで返します。</p>
        <pre><code>{
  "ok": true,
  "report": {
    "ghostName": "ゴースト名",
    "shioriAssessment": {
      "displayName": "YAYA",
      "supportStatus": "supported"
    },
    "diagnostics": []
  },
  "requestId": "..."
}</code></pre>

        <h3><code>GET /api/v1/health</code></h3>
        <p>サービスの稼働状態と、現在の最大アップロードサイズを返します。</p>
        <p>混雑時は短時間だけ空きを待ち、処理できない場合は<code>429 Too Many Requests</code>と<code>Retry-After</code>を返します。</p>
    </section>
</main>

<footer class="site-footer">
    <div class="container footer-content">
        <span>wmsci.com</span>
        <nav aria-label="関連リンク">
            <a href="/licenses">ライセンス</a>
            <a href="https://github.com/opera7133/Utatane" rel="external">ソースコード</a>
        </nav>
    </div>
</footer>
</body>
</html>
