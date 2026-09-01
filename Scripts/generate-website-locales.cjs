// Generate crawlable static locale pages from website/utatane/index.html.
// Run: node Scripts/generate-website-locales.cjs [--check]
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.join(__dirname, '..');
const sourcePath = path.join(root, 'website/utatane/index.html');
const source = fs.readFileSync(sourcePath, 'utf8');
const check = process.argv.includes('--check');
const origin = 'https://dl.wmsci.com';

const locales = {
  ja: {
    directory: '', htmlLang: 'ja', ogLocale: 'ja_JP',
    title: 'Utatane — macOSで伺かを',
    description: 'Utatane — macOSで伺かを楽しむための本体アプリ。',
  },
  en: {
    directory: 'en', htmlLang: 'en', ogLocale: 'en_US',
    title: 'Utatane — Ukagaka for macOS',
    description: 'Utatane is a native macOS baseware for enjoying Ukagaka ghosts, dialogue, shells, balloons, and animations.',
  },
  'zh-Hans': {
    directory: 'zh-hans', htmlLang: 'zh-Hans', ogLocale: 'zh_CN',
    title: 'Utatane — 在 macOS 上使用伺か',
    description: 'Utatane 是面向 macOS 的伺か本体应用，可体验人格对话、外壳、对话框与动画。',
  },
  'zh-Hant': {
    directory: 'zh-hant', htmlLang: 'zh-Hant', ogLocale: 'zh_TW',
    title: 'Utatane — 在 macOS 上使用伺か',
    description: 'Utatane 是面向 macOS 的伺か本體應用程式，可體驗人格對話、外殼、對話框與動畫。',
  },
  ko: {
    directory: 'ko', htmlLang: 'ko', ogLocale: 'ko_KR',
    title: 'Utatane — macOS에서 우카가카를',
    description: 'Utatane는 macOS에서 우카가카 고스트의 대화, 셸, 말풍선, 애니메이션을 즐길 수 있는 베이스웨어예요.',
  },
};

function render(code, locale) {
  const localePath = locale.directory ? `${locale.directory}/` : '';
  const localeURL = `${origin}/utatane/${localePath}`;
  let html = source
    .replace('<html lang="ja">', `<html lang="${locale.htmlLang}">`)
    .replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${locale.description}">`)
    .replace(/<title>[^<]*<\/title>/, `<title>${locale.title}</title>`)
    .replace(/<link rel="canonical" href="[^"]*">/, `<link rel="canonical" href="${localeURL}">`)
    .replace('<meta property="og:locale" content="ja_JP">', `<meta property="og:locale" content="${locale.ogLocale}">`)
    .replace(/<meta property="og:title" content="[^"]*">/, `<meta property="og:title" content="${locale.title}">`)
    .replace(/<meta property="og:description" content="[^"]*">/, `<meta property="og:description" content="${locale.description}">`)
    .replace(/<meta property="og:url" content="[^"]*">/, `<meta property="og:url" content="${localeURL}">`)
    .replace(/"url":"https:\/\/dl\.wmsci\.com\/utatane\/[^"]*"/, `"url":"${localeURL}"`)
    .replace(/<link rel="alternate" hreflang="ja"[^>]*>[\s\S]*?<link rel="alternate" hreflang="x-default"[^>]*>/, alternateLinks());

  let translated = 0;
  const attribute = `data-${code.toLowerCase()}`;
  html = html.replace(/(<([a-z][a-z0-9]*)\b[^>]*\bdata-ja="[^"]*"[^>]*>)([^<]*)(<\/\2>)/gi, (whole, open, tag, text, close) => {
    const match = open.match(new RegExp(`${attribute}="([^"]*)"`, 'i'));
    assert.ok(match, `Missing ${attribute}: ${open}`);
    translated += 1;
    return `${open}${match[1]}${close}`;
  });
  assert.equal(translated, 76, `${code} translated element count`);

  html = html.replace(/<img\b[^>]*\bdata-alt-ja="[^"]*"[^>]*>/gi, whole => {
    const match = whole.match(new RegExp(`data-alt-${code}="([^"]*)"`, 'i'));
    assert.ok(match, `Missing image alt for ${code}`);
    return whole.replace(/\balt="[^"]*"/, `alt="${match[1]}"`);
  });

  html = html
    .replace(/<div class="languages"[\s\S]*?<\/div>/, languageLinks(code))
    .replaceAll('href="./utatane.html"', 'href="./simple.html"');
  if (locale.directory) {
    html = html
      .replaceAll('href="./utatane-modern.css"', 'href="../utatane-modern.css"')
      .replaceAll('src="./utatane-modern.js"', 'src="../utatane-modern.js"')
      .replaceAll('src="./assets/', 'src="../assets/')
      .replaceAll('srcset="./assets/', 'srcset="../assets/')
      .replaceAll('href="./assets/', 'href="../assets/')
      .replaceAll('href="./getting-started/"', 'href="./getting-started/"')
      .replaceAll('href="./simple.html"', 'href="../simple.html"');
  }
  return html;
}

function alternateLinks() {
  return [
    ['ja', `${origin}/utatane/`],
    ['en', `${origin}/utatane/en/`],
    ['zh-Hans', `${origin}/utatane/zh-hans/`],
    ['zh-Hant', `${origin}/utatane/zh-hant/`],
    ['ko', `${origin}/utatane/ko/`],
    ['x-default', `${origin}/utatane/`],
  ].map(([lang, href]) => `<link rel="alternate" hreflang="${lang}" href="${href}">`).join('\n');
}

function languageLinks(current) {
  const links = [
    ['ja', 'ja', '/utatane/', '日本語'],
    ['en', 'en', '/utatane/en/', 'EN'],
    ['zh-Hans', 'zh-Hans', '/utatane/zh-hans/', '简体'],
    ['zh-Hant', 'zh-Hant', '/utatane/zh-hant/', '繁體'],
    ['ko', 'ko', '/utatane/ko/', '한국어'],
  ].map(([code, lang, href, label]) => `<a lang="${lang}" hreflang="${lang}" href="${href}"${code === current ? ' aria-current="page"' : ''}>${label}</a>`).join('\n');
  return `<div class="languages" aria-label="Language / 言語">\n${links}\n</div>`;
}

const guideContent = {
  ja: {
    title: '伺かとUtataneをはじめる — ゴーストの探し方と互換性', description: '伺かゴーストを探せる配布サイトと、SSPなどからUtataneへ移る人向けの互換性・実装方式を案内します。',
    label: 'START HERE', heading: 'ゴーストを探す。仕組みを知る。', lead: '伺かが初めての人と、ほかのベースウェアを使ってきた人へ。インストール手順は概要ページにまとめています。', home: '概要', guide: 'はじめに',
    sections: [
      ['01', '伺かとゴースト', '<p>Utataneは「ベースウェア」と呼ばれる本体です。そこへキャラクター、会話、反応をまとめた「ゴースト」を追加して使います。見た目の差分はシェル、台詞を表示する枠はバルーン、配布ファイルは主にNAR形式です。</p>'],
      ['02', 'ゴーストを探す場所', '<p><a href="http://ghosttown.mikage.jp/cgi-bin/tdb/tdb.cgi?mode=preview_list">GHOST TOWN</a>は長く使われてきたゴーストデータベース、<a href="https://buynowforsale.shillest.net/ghosts/">ゴーストキャプターさくら</a>は画像と更新順から眺められる更新フィードです。最近の更新を追うなら<a href="https://nikolat.github.io/sirefaso/">偽SiReFaSo</a>、登録された配布物をカテゴリから探すなら<a href="https://nikolat.github.io/sosiremi/ghost/">偽SoSiReMi</a>も使えます。</p><p class="note">古いデータベースには公開終了やリンク切れもあります。最終的には作者の配布ページと利用条件を確認してください。SSPのみで動作確認された作品も多く、Utataneでの互換性はゴーストごとに異なります。</p>'],
      ['03', 'NARを追加する', '<p>入手したNARは、Utataneのファイル選択、ドラッグ＆ドロップ、Finderの「このアプリケーションで開く」から追加できます。アプリ自体のダウンロードとmacOSでの初回起動は<a href="/utatane/#install">概要ページのダウンロード欄</a>を見てください。</p>'],
      ['04', 'ほかのベースウェアと比べる', '<div class="guide-table"><table><thead><tr><th>観点</th><th>SSP</th><th>ninix-kagari</th><th>Utatane</th></tr></thead><tbody><tr><th>主な環境</th><td>Windows</td><td>Linux、Windows</td><td>macOS 14以降</td></tr><tr><th>位置付け</th><td>現在の事実上の基準</td><td>ninix-ayaのフォーク。主要SHIORIを同時にビルド可能</td><td>macOS向け。主要機能を実装中で完全互換ではない</td></tr><tr><th>外部モジュール</th><td>Windows DLLを直接利用</td><td>Linuxでは対応SHIORIのビルドが必要。SAORIは主にninix-saori</td><td>内蔵のネイティブ実装を優先。一部は設定済みWine経由</td></tr><tr><th>導入・移行</th><td>Windows向け配布</td><td>LinuxではビルドまたはDebianパッケージ</td><td>Macアプリ。展開したSSPフォルダから取り込み可能</td></tr></tbody></table></div><p><a href="https://github.com/Tatakinov/ninix-kagari">ninix-kagari</a>の対応範囲は環境によって異なります。Utataneについては<a href="https://github.com/opera7133/Utatane/blob/main/Docs/Compatibility.md">確認済みゴーストと残っている機能</a>に、実際に確認した範囲を記録しています。</p>'],
      ['05', '辞書をどう読んでいるか', '<p>最初に<code>descript.txt</code>を読み、指定がなければ<code>alias.txt</code>や特徴的な辞書ファイルも手掛かりにSHIORIを選びます。テキストは宣言された文字コードを優先し、UTF-8、Shift_JIS、EUC-KR、EUC-JP、GB18030、Big5などの候補から復号します。ファイルの途中で文字コードが混ざった古いデータにも行単位の復号で対処します。</p><p>辞書は一種類の共通形式へ雑に変換しているわけではありません。里々、MISAKA、灯、ese-shiori、偽栞などに個別の字句・構文解析と評価器があり、条件分岐、変数、単語群、ジャンプなどを元の実行モデルに合わせて処理します。YAYAと華和梨は移植した本体をmacOS用の薄い接続層から呼び出します。</p>'],
      ['06', 'Windows DLLなしで動かす境界', '<p>画面、イベント配送、SakuraScript解析はSwift側に置き、SHIORIとは<code>PersonalityEngine</code>という共通境界で接続します。既知のSAORIはmacOS APIによる共通実装を優先し、未知のmacOS用モジュールは標準ABIで読み込みます。Windows DLLは直接ロードできないので、必要な場合だけWine上の補助ホストへSHIORI/SAORI電文を渡します。</p><p>配布物は読み取り元として扱い、変数や学習データはApplication Supportのゴースト別領域へ保存します。対応エンジンでも未実装命令、Windows固有API、外部DLL、全分岐の一致までは保証しません。詳しくは<a href="https://github.com/opera7133/Utatane/blob/main/Docs/Native-SHIORI.md">Native SHIORI / SAORI</a>を見てください。</p>'],
    ],
    trouble: 'うまく動かないときは、ゴースト名、Utataneのバージョン、起きたことを添えてGitHub Issuesへ報告してください。互換性は開発中で、すべてのゴーストや機能の動作を保証するものではありません。', issue: '不具合を報告する', back: 'Utataneの概要へ戻る',
  },
  en: {
    title: 'Start with Ukagaka and Utatane — Find ghosts and understand compatibility', description: 'Find Ukagaka ghost distribution sites and learn how Utatane compatibility differs from SSP.',
    label: 'START HERE', heading: 'Find ghosts. Understand the machinery.', lead: 'For people new to Ukagaka and people moving from another baseware. App installation is covered on the overview page.', home: 'Overview', guide: 'Start here',
    sections: [
      ['01', 'Ukagaka and ghosts', '<p>Utatane is the “baseware,” the program that runs Ukagaka content. A “ghost” bundles a character, dialogue, and reactions. Shells change its appearance, balloons display dialogue, and releases commonly use the NAR archive format.</p>'],
      ['02', 'Where to find ghosts', '<p><a href="http://ghosttown.mikage.jp/cgi-bin/tdb/tdb.cgi?mode=preview_list">GHOST TOWN</a> is a long-running database. <a href="https://buynowforsale.shillest.net/ghosts/">Ghost Captor Sakura</a> presents an image-rich update feed. Use <a href="https://nikolat.github.io/sirefaso/">Nise SiReFaSo</a> to follow recent updates and <a href="https://nikolat.github.io/sosiremi/ghost/">Nise SoSiReMi</a> to browse registered downloads. The <a href="https://ukagakadreamteam.com/wiki/guide/beginner_guide">Ukagaka Dream Team beginner guide</a> is an English-language introduction.</p><p class="note">Older databases contain discontinued or broken links. Follow through to the creator’s page and read its terms. Many releases are tested only with SSP, so Utatane compatibility varies by ghost.</p>'],
      ['03', 'Install a NAR', '<p>Add a downloaded NAR with Utatane’s file picker, drag and drop, or Finder’s Open With command. See the <a href="/utatane/en/#install">overview download section</a> for installing and opening the app itself.</p>'],
      ['04', 'Comparing baseware', '<div class="guide-table"><table><thead><tr><th>Area</th><th>SSP</th><th>ninix-kagari</th><th>Utatane</th></tr></thead><tbody><tr><th>Primary OS</th><td>Windows</td><td>Linux and Windows</td><td>macOS 14 or later</td></tr><tr><th>Position</th><td>The current de facto reference</td><td>A ninix-aya fork; major SHIORI can be built with it</td><td>Built for macOS; major features in progress, not fully compatible</td></tr><tr><th>Modules</th><td>Loads Windows DLLs directly</td><td>Linux needs compatible SHIORI builds; SAORI is mainly ninix-saori</td><td>Native implementations first; some modules can use configured Wine</td></tr><tr><th>Setup</th><td>Windows distribution</td><td>Build on Linux or use the Debian package</td><td>Mac app; can import an extracted SSP folder</td></tr></tbody></table></div><p>Support varies by environment; see the <a href="https://github.com/Tatakinov/ninix-kagari">ninix-kagari project</a>. For Utatane, see <a href="https://github.com/opera7133/Utatane/blob/main/Docs/Compatibility.md">tested ghosts and remaining gaps</a>.</p>'],
      ['05', 'How compatibility works on macOS', '<p>Utatane identifies the dialogue engine (SHIORI) from files such as <code>descript.txt</code>, then connects YAYA, SATORI, KAWARI, MISAKA, and other known engines to Swift or macOS-native implementations. Known SAORI modules also have shared native implementations. Unsupported Windows DLLs run only when Wine and the helper host are configured.</p><p>State is kept outside the distributed ghost in Application Support. Even a supported engine does not guarantee every branch or Windows-specific dependency. Read <a href="https://github.com/opera7133/Utatane/blob/main/Docs/Native-SHIORI.md">Native SHIORI / SAORI</a> for the technical details.</p>'],
    ],
    trouble: 'If something does not work, report the ghost name, your Utatane version, and what happened on GitHub Issues. Compatibility is still in development, so not every ghost or feature is guaranteed to work.', issue: 'Report an issue', back: 'Back to the Utatane overview',
  },
  'zh-Hans': {
    title: '开始使用伺か与 Utatane — 寻找人格与兼容性说明', description: '了解在哪里寻找伺か人格，以及 Utatane 与 SSP 的兼容性和实现方式。',
    label: '从这里开始', heading: '寻找人格，了解运行原理。', lead: '面向第一次接触伺か，以及从其他本体迁移的用户。应用安装步骤已列在概览页面。', home: '概览', guide: '入门',
    sections: [
      ['01', '伺か与人格', '<p>Utatane 是运行伺か内容的“本体（baseware）”。“人格（ghost）”包含角色、对话和互动；外壳（shell）改变外观，对话框（balloon）显示文字，发布文件通常采用 NAR 格式。</p>'],
      ['02', '寻找人格的入口', '<p><a href="http://ghosttown.mikage.jp/cgi-bin/tdb/tdb.cgi?mode=preview_list">GHOST TOWN</a> 是历史悠久的人格数据库；<a href="https://buynowforsale.shillest.net/ghosts/">Ghost Captor Sakura</a> 可按图片和更新时间浏览。<a href="https://nikolat.github.io/sirefaso/">偽SiReFaSo</a>适合追踪近期更新，<a href="https://nikolat.github.io/sosiremi/ghost/">偽SoSiReMi</a>可按分类查找已登记的发布内容。</p><p class="note">旧数据库中可能有停止发布或失效的链接。请进入作者页面并确认使用条款。许多作品只在 SSP 上测试，因此 Utatane 兼容性因人格而异。</p>'],
      ['03', '安装 NAR', '<p>可以通过 Utatane 的文件选择、拖放或 Finder 的“打开方式”添加 NAR。应用本身的下载与首次启动方法请看<a href="/utatane/zh-hans/#install">概览页面的下载部分</a>。</p>'],
      ['04', '比较不同本体', '<div class="guide-table"><table><thead><tr><th>项目</th><th>SSP</th><th>ninix-kagari</th><th>Utatane</th></tr></thead><tbody><tr><th>主要系统</th><td>Windows</td><td>Linux、Windows</td><td>macOS 14 或更高版本</td></tr><tr><th>定位</th><td>目前事实上的基准</td><td>ninix-aya 的分支，可一并构建主要 SHIORI</td><td>面向 macOS；主要功能仍在实现，并非完全兼容</td></tr><tr><th>外部模块</th><td>直接加载 Windows DLL</td><td>Linux 需要构建兼容 SHIORI；SAORI 主要为 ninix-saori</td><td>优先使用原生实现；一部分可通过已配置的 Wine 运行</td></tr><tr><th>安装</th><td>Windows 发布版</td><td>在 Linux 构建或使用 Debian 软件包</td><td>Mac 应用；可从解压后的 SSP 文件夹导入</td></tr></tbody></table></div><p>不同环境的支持范围有所不同，请参阅 <a href="https://github.com/Tatakinov/ninix-kagari">ninix-kagari 项目</a>。Utatane 的<a href="https://github.com/opera7133/Utatane/blob/main/Docs/Compatibility.md">已测试人格与剩余问题</a>记录了实际确认范围。</p>'],
      ['05', '如何在 macOS 上实现兼容', '<p>Utatane 从 <code>descript.txt</code> 等文件识别对话引擎（SHIORI），再将 YAYA、里々、華和梨、MISAKA 等已知引擎连接到 Swift 或 macOS 原生实现。常见 SAORI 也有共享的原生实现；不支持的 Windows DLL 只有在配置 Wine 与辅助宿主后才会运行。</p><p>状态数据与发布文件分离，保存在 Application Support。即使引擎受支持，也不保证所有分支或 Windows 专用依赖都能工作。技术细节请看 <a href="https://github.com/opera7133/Utatane/blob/main/Docs/Native-SHIORI.md">Native SHIORI / SAORI</a>。</p>'],
    ],
    trouble: '如果遇到问题，请在 GitHub Issues 中提供人格名称、Utatane 版本和问题描述。兼容性仍在开发中，并不保证所有人格和功能都能运行。', issue: '报告问题', back: '返回 Utatane 概览',
  },
  'zh-Hant': {
    title: '開始使用伺か與 Utatane — 尋找人格與相容性說明', description: '瞭解在哪裡尋找伺か人格，以及 Utatane 與 SSP 的相容性和實作方式。',
    label: '從這裡開始', heading: '尋找人格，瞭解運作原理。', lead: '寫給第一次接觸伺か，以及從其他本體移轉的使用者。應用程式安裝步驟已列在概要頁面。', home: '概要', guide: '入門',
    sections: [
      ['01', '伺か與人格', '<p>Utatane 是執行伺か內容的「本體（baseware）」。「人格（ghost）」包含角色、對話與互動；外殼（shell）改變外觀，對話框（balloon）顯示文字，發行檔案通常採用 NAR 格式。</p>'],
      ['02', '尋找人格的入口', '<p><a href="http://ghosttown.mikage.jp/cgi-bin/tdb/tdb.cgi?mode=preview_list">GHOST TOWN</a> 是歷史悠久的人格資料庫；<a href="https://buynowforsale.shillest.net/ghosts/">Ghost Captor Sakura</a> 可依圖片與更新時間瀏覽。<a href="https://nikolat.github.io/sirefaso/">偽SiReFaSo</a>適合追蹤近期更新，<a href="https://nikolat.github.io/sosiremi/ghost/">偽SoSiReMi</a>可依分類尋找已登記的發布內容。</p><p class="note">舊資料庫中可能有停止發布或失效的連結。請前往作者頁面並確認使用條款。許多作品只在 SSP 上測試，因此 Utatane 相容性因人格而異。</p>'],
      ['03', '安裝 NAR', '<p>可以透過 Utatane 的檔案選擇、拖放或 Finder 的「打開方式」加入 NAR。應用程式本身的下載與首次啟動方式請看<a href="/utatane/zh-hant/#install">概要頁面的下載部分</a>。</p>'],
      ['04', '比較不同本體', '<div class="guide-table"><table><thead><tr><th>項目</th><th>SSP</th><th>ninix-kagari</th><th>Utatane</th></tr></thead><tbody><tr><th>主要系統</th><td>Windows</td><td>Linux、Windows</td><td>macOS 14 或更新版本</td></tr><tr><th>定位</th><td>目前事實上的基準</td><td>ninix-aya 的分支，可一併建置主要 SHIORI</td><td>面向 macOS；主要功能仍在實作，並非完全相容</td></tr><tr><th>外部模組</th><td>直接載入 Windows DLL</td><td>Linux 需要建置相容 SHIORI；SAORI 主要為 ninix-saori</td><td>優先使用原生實作；一部分可透過已設定的 Wine 執行</td></tr><tr><th>安裝</th><td>Windows 發行版</td><td>在 Linux 建置或使用 Debian 套件</td><td>Mac 應用程式；可從解壓縮後的 SSP 檔案夾匯入</td></tr></tbody></table></div><p>不同環境的支援範圍有所不同，請參閱 <a href="https://github.com/Tatakinov/ninix-kagari">ninix-kagari 專案</a>。Utatane 的<a href="https://github.com/opera7133/Utatane/blob/main/Docs/Compatibility.md">已測試人格與剩餘問題</a>記錄了實際確認範圍。</p>'],
      ['05', '如何在 macOS 上實作相容', '<p>Utatane 從 <code>descript.txt</code> 等檔案識別對話引擎（SHIORI），再將 YAYA、里々、華和梨、MISAKA 等已知引擎連接到 Swift 或 macOS 原生實作。常見 SAORI 也有共用的原生實作；不支援的 Windows DLL 只有在設定 Wine 與輔助宿主後才會執行。</p><p>狀態資料與發布檔案分離，儲存在 Application Support。即使引擎受支援，也不保證所有分支或 Windows 專用相依項目都能運作。技術細節請看 <a href="https://github.com/opera7133/Utatane/blob/main/Docs/Native-SHIORI.md">Native SHIORI / SAORI</a>。</p>'],
    ],
    trouble: '如果遇到問題，請在 GitHub Issues 提供人格名稱、Utatane 版本與問題描述。相容性仍在開發中，並不保證所有人格和功能都能執行。', issue: '回報問題', back: '返回 Utatane 概要',
  },
  ko: {
    title: '우카가카와 Utatane 시작하기 — 고스트 찾기와 호환성', description: '우카가카 고스트 배포 사이트와 Utatane와 SSP의 호환성 및 구현 방식을 안내합니다.',
    label: '여기서 시작', heading: '고스트를 찾고, 작동 방식을 알아봐요.', lead: '우카가카를 처음 접하는 사람과 다른 베이스웨어에서 옮겨 오는 사람을 위한 안내예요. 앱 설치는 개요 페이지에 정리되어 있어요.', home: '개요', guide: '입문',
    sections: [
      ['01', '우카가카와 고스트', '<p>Utatane는 우카가카 콘텐츠를 실행하는 “베이스웨어”예요. “고스트”에는 캐릭터, 대화, 반응이 들어 있어요. 셸은 외형을 바꾸고 벌룬은 대사를 표시하며, 배포 파일은 주로 NAR 형식을 사용해요.</p>'],
      ['02', '고스트를 찾는 곳', '<p><a href="http://ghosttown.mikage.jp/cgi-bin/tdb/tdb.cgi?mode=preview_list">GHOST TOWN</a>은 오래된 고스트 데이터베이스이고, <a href="https://buynowforsale.shillest.net/ghosts/">Ghost Captor Sakura</a>는 이미지와 업데이트 순서로 둘러볼 수 있는 피드예요. 최근 업데이트는 <a href="https://nikolat.github.io/sirefaso/">偽SiReFaSo</a>, 등록된 배포물은 <a href="https://nikolat.github.io/sosiremi/ghost/">偽SoSiReMi</a>에서 분류별로 찾을 수 있어요.</p><p class="note">오래된 데이터베이스에는 배포 종료나 끊어진 링크도 있어요. 제작자 페이지와 이용 조건을 확인하세요. SSP에서만 시험한 작품이 많아 Utatane 호환성은 고스트마다 달라요.</p>'],
      ['03', 'NAR 설치', '<p>Utatane의 파일 선택, 드래그 앤 드롭, Finder의 ‘다음으로 열기’로 NAR를 추가할 수 있어요. 앱 다운로드와 첫 실행 방법은 <a href="/utatane/ko/#install">개요 페이지의 다운로드 부분</a>을 확인하세요.</p>'],
      ['04', '베이스웨어 비교', '<div class="guide-table"><table><thead><tr><th>항목</th><th>SSP</th><th>ninix-kagari</th><th>Utatane</th></tr></thead><tbody><tr><th>주요 환경</th><td>Windows</td><td>Linux, Windows</td><td>macOS 14 이상</td></tr><tr><th>위치</th><td>현재 사실상의 기준</td><td>ninix-aya 포크이며 주요 SHIORI를 함께 빌드 가능</td><td>macOS용이며 주요 기능 구현 중, 완전 호환은 아님</td></tr><tr><th>외부 모듈</th><td>Windows DLL 직접 로드</td><td>Linux에서는 호환 SHIORI 빌드가 필요하며 SAORI는 주로 ninix-saori</td><td>네이티브 구현 우선, 일부는 설정한 Wine으로 실행</td></tr><tr><th>설치</th><td>Windows 배포판</td><td>Linux에서 빌드하거나 Debian 패키지 사용</td><td>Mac 앱이며 압축을 푼 SSP 폴더에서 가져오기 가능</td></tr></tbody></table></div><p>환경별 지원 범위는 <a href="https://github.com/Tatakinov/ninix-kagari">ninix-kagari 프로젝트</a>를 확인하세요. Utatane의 <a href="https://github.com/opera7133/Utatane/blob/main/Docs/Compatibility.md">확인한 고스트와 남은 문제</a>에는 실제 확인 범위가 정리되어 있어요.</p>'],
      ['05', 'macOS 호환 방식', '<p>Utatane는 <code>descript.txt</code> 같은 파일에서 대화 엔진(SHIORI)을 판별하고 YAYA, SATORI, KAWARI, MISAKA 등 알려진 엔진을 Swift 또는 macOS 네이티브 구현에 연결해요. 알려진 SAORI에도 공통 네이티브 구현이 있고, 지원하지 않는 Windows DLL은 Wine과 보조 호스트를 설정한 경우에만 실행해요.</p><p>상태 데이터는 배포 파일과 분리해 Application Support에 저장해요. 엔진을 지원하더라도 모든 분기나 Windows 전용 의존성이 작동한다고 보장하지는 않아요. 자세한 내용은 <a href="https://github.com/opera7133/Utatane/blob/main/Docs/Native-SHIORI.md">Native SHIORI / SAORI</a>를 확인하세요.</p>'],
    ],
    trouble: '문제가 생기면 고스트 이름, Utatane 버전, 발생한 일을 GitHub Issues에 알려 주세요. 호환성은 개발 중이며 모든 고스트와 기능의 작동을 보장하지 않아요.', issue: '문제 보고하기', back: 'Utatane 개요로 돌아가기',
  },
};

function guideAlternateLinks() {
  return [
    ['ja', `${origin}/utatane/getting-started/`], ['en', `${origin}/utatane/en/getting-started/`],
    ['zh-Hans', `${origin}/utatane/zh-hans/getting-started/`], ['zh-Hant', `${origin}/utatane/zh-hant/getting-started/`],
    ['ko', `${origin}/utatane/ko/getting-started/`], ['x-default', `${origin}/utatane/getting-started/`],
  ].map(([lang, href]) => `<link rel="alternate" hreflang="${lang}" href="${href}">`).join('\n');
}

function guideLanguageLinks(current) {
  return [
    ['ja', 'ja', '/utatane/getting-started/', '日本語'], ['en', 'en', '/utatane/en/getting-started/', 'EN'],
    ['zh-Hans', 'zh-Hans', '/utatane/zh-hans/getting-started/', '简体'], ['zh-Hant', 'zh-Hant', '/utatane/zh-hant/getting-started/', '繁體'],
    ['ko', 'ko', '/utatane/ko/getting-started/', '한국어'],
  ].map(([code, lang, href, label]) => `<a lang="${lang}" hreflang="${lang}" href="${href}"${code === current ? ' aria-current="page"' : ''}>${label}</a>`).join('\n');
}

function renderGuide(code, locale) {
  const content = guideContent[code];
  const localePath = locale.directory ? `${locale.directory}/` : '';
  const canonical = `${origin}/utatane/${localePath}getting-started/`;
  const home = `/utatane/${localePath}`;
  const depth = locale.directory ? '../..' : '..';
  const tabLabels = {
    ja: ['伺か初心者', '気付けば何年目'], en: ['New to Ukagaka', 'Been here for years'],
    'zh-Hans': ['伺か新手', '多年老用户'], 'zh-Hant': ['伺か新手', '多年老使用者'],
    ko: ['우카가카 입문자', '어느새 수년째'],
  }[code];
  const renderSections = sections => sections.map(([number, heading, body]) => `<section class="guide-section"><p class="number">${number}</p><div><h2>${heading}</h2>${body}</div></section>`).join('\n');
  const beginnerSections = renderSections(content.sections.slice(0, 3));
  const veteranSections = renderSections(content.sections.slice(3));
  return `<!doctype html>
<html lang="${locale.htmlLang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="${content.description}">
<title>${content.title}</title>
<link rel="canonical" href="${canonical}">
${guideAlternateLinks()}
<meta property="og:type" content="article">
<meta property="og:locale" content="${locale.ogLocale}">
<meta property="og:title" content="${content.title}">
<meta property="og:description" content="${content.description}">
<meta property="og:url" content="${canonical}">
<meta property="og:image" content="${origin}/utatane/assets/utatane-icon.png">
<meta name="twitter:card" content="summary">
<link rel="icon" href="${depth}/assets/utatane-icon.png">
<link rel="stylesheet" href="${depth}/utatane-modern.css">
</head>
<body>
<div class="wrap">
<header class="topbar">
<a class="brand" href="${home}"><img src="${depth}/assets/utatane-icon.png" width="30" height="30" alt="">Utatane</a>
<nav aria-label="Navigation"><a href="${home}">${content.home}</a><a href="./" aria-current="page">${content.guide}</a><div class="languages" aria-label="Language / 言語">${guideLanguageLinks(code)}</div></nav>
</header>
<main class="guide-page">
<header class="guide-hero"><p class="eyebrow">${content.label}</p><h1>${content.heading}</h1><p class="lead">${content.lead}</p></header>
<div class="guide-tabs" role="tablist" aria-label="${content.guide}">
<button type="button" role="tab" id="tab-beginner" aria-controls="panel-beginner" aria-selected="true">${tabLabels[0]}</button>
<button type="button" role="tab" id="tab-veteran" aria-controls="panel-veteran" aria-selected="false">${tabLabels[1]}</button>
</div>
<div class="guide-panels">
<div class="guide-sections" id="panel-beginner" role="tabpanel" aria-labelledby="tab-beginner">${beginnerSections}</div>
<div class="guide-sections" id="panel-veteran" role="tabpanel" aria-labelledby="tab-veteran">${veteranSections}</div>
</div>
<aside class="guide-help"><h2>${content.issue}</h2><p>${content.trouble}</p><a href="https://github.com/opera7133/Utatane/issues/new/choose">${content.issue} <span aria-hidden="true">↗</span></a></aside>
</main>
<footer><div class="bottom"><span>© 2026 wamo.</span><a href="${home}">${content.back}</a></div></footer>
</div>
<script>
document.documentElement.classList.add('tabs-enabled');
const tabs=[...document.querySelectorAll('[role="tab"]')];
const selectTab=(tab,updateHash=false)=>{for(const item of tabs){const selected=item===tab;item.setAttribute('aria-selected',String(selected));item.tabIndex=selected?0:-1;document.getElementById(item.getAttribute('aria-controls')).hidden=!selected}if(updateHash)history.replaceState(null,'','#'+tab.id.replace('tab-',''))};
for(const tab of tabs){tab.addEventListener('click',()=>selectTab(tab,true));tab.addEventListener('keydown',event=>{if(!['ArrowLeft','ArrowRight'].includes(event.key))return;event.preventDefault();const next=tabs[(tabs.indexOf(tab)+(event.key==='ArrowRight'?1:-1)+tabs.length)%tabs.length];selectTab(next,true);next.focus()})}
selectTab(location.hash==='#veteran'?tabs[1]:tabs[0]);
</script>
</body>
</html>
`;
}

for (const [code, locale] of Object.entries(locales)) {
  if (code === 'ja') continue;
  const outputPath = path.join(root, 'website/utatane', locale.directory, 'index.html');
  const output = render(code, locale);
  if (check) {
    assert.equal(fs.readFileSync(outputPath, 'utf8'), output, `${path.relative(root, outputPath)} is stale`);
  } else {
    fs.mkdirSync(path.dirname(outputPath), {recursive: true});
    fs.writeFileSync(outputPath, output);
  }
}

for (const [code, locale] of Object.entries(locales)) {
  const outputPath = path.join(root, 'website/utatane', locale.directory, 'getting-started/index.html');
  const output = renderGuide(code, locale);
  if (check) {
    assert.equal(fs.readFileSync(outputPath, 'utf8'), output, `${path.relative(root, outputPath)} is stale`);
  } else {
    fs.mkdirSync(path.dirname(outputPath), {recursive: true});
    fs.writeFileSync(outputPath, output);
  }
}

console.log(check ? 'PASS: localized website files are current' : 'Generated localized website files');
