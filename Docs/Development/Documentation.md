# ドキュメントの編集と公開

## 原稿と出力

- `Docs/` が公開ドキュメントの原稿です。`Guide/` に使い方、`Support/` に困ったときと互換性、`Creators/` に制作、`Reference/` に対応表、`Development/` に本体開発と運用をまとめます。
- `Docs/navigation.json` が公開するページ、URL、目次、同梱対象を定義します。
- `Docs/Index.md` がWeb版の入口です。`Docs/README.md` はリポジトリ内の索引です。
- `website/` はAstro + Starlightのプロジェクトです。原稿から静的サイトを生成します。
- `apps/Utatane/Resources/UtataneHelp.html` は原稿から生成した同梱ヘルプです。直接編集しません。
- `Internal-Docs/` は調査・設計・計画です。Webの入力には含めません。

同梱ヘルプは単一のHTMLにCSSと小さな検索スクリプトを埋め込みます。掲載画像もHTML内へ埋め込み、外部のJavaScript、フォント、APIへの接続は不要です。アプリは従来どおりこのファイルを既定のブラウザで開きます。アプリにAstroやNodeのランタイムを組み込む構成ではありません。

## 準備と確認

ビルドにはNode.js 22.12以降とBunを使います。サーバーでは生成済みの静的ファイルを配信します。

```sh
cd website
bun install --frozen-lockfile
bun run help
bun run check
bun run build
bun run test
bun run preview --host 127.0.0.1
```

Webの開発中は `bun run dev` を使えます。Docsを追加・変更したら開発サーバーを再起動して原稿を取り込みます。検索の確認には本番ビルド後のpreviewを使います。

`bun run check` は5言語の翻訳キー・原稿リンク・Issueの参照先・リリース取得処理と、同梱ヘルプの生成差分を確認します。`bun run test` はビルド済みの言語・公開メタデータ・ページ・内部リンク・アセット・同梱ヘルプのアンカーと、開発サーバー・公開用プレビューのHTML・画像ルートを確認します。ブラウザでの見た目・検索・スタイル切り替えは別途確認します。

## ページを追加する

1. DocsにMarkdownを追加します。先頭を `# ページ名` にします。
2. `navigation.json` の適切な区分に `file`、`slug`、`title` を追加します。利用者向けで同梱するページには `help: true` を指定します。
3. 原稿間のリンクは通常の相対Markdownリンクで書きます。WebではページURLへ、同梱対象間ではHTML内のアンカーへ変換します。
4. ヘルプを再生成して確認します。原稿の変更と生成済みHTMLを一緒にコミットします。

同梱対象でない制作・開発ページへのリンクは、同梱ヘルプではWeb版へ案内します。ソースコードやリポジトリREADMEへのリンクはGitHubへ案内します。

原稿を用途別に移動しても、公開ページの目次・URLは `navigation.json` により維持できます。原稿間の相対リンク、リポジトリREADME、GitHubのIssueテンプレートにある参照先も移動に合わせて更新してください。

## 紹介サイトを編集する

紹介サイトは通常のAstroページとコンポーネントです。言語別HTMLを複製したり、完成したHTMLを読み込んで正規表現で加工したりする処理はありません。

| 場所（`website/` 内） | 内容 |
| --- | --- |
| `src/pages/[...route].astro` | 5言語の概要・ガイドのルート |
| `src/pages/simple.html.astro` | シンプルな案内ページ |
| `src/layouts/MarketingLayout.astro` | HTML、SEO、OGP、構造化データ |
| `src/components/marketing/` | 共通ヘッダー、言語リンク、概要、ガイド、フッター |
| `src/data/{ja,en,zh-Hans,zh-Hant,ko}.json` | 言語ごとのメタデータ・本文・ガイド |
| `src/i18n.mjs` | 翻訳の参照と、言語別URL |
| `src/styles/marketing.css` | 紹介サイトの見た目 |
| `src/scripts/` | リリース取得、タイトルの動き、ガイドのタブ |
| `public/assets/` | アイコンとスクリーンショット |

本文を直すときは各言語のJSONを編集します。項目を追加するときは同じ翻訳キーを5言語に追加し、コンポーネントから `t('キー')` で参照します。ガイドの `sections` は番号・見出し・本文HTMLの配列で、表やリンクを含む既存の内容をそのまま管理します。外部から取得したHTMLを入れる場所ではありません。

紹介サイトは既存のCSSを使い、ドキュメントはStarlightのCSSを使います。TailwindCSSは必須ではありません。`simple.html.astro` はAstroのディレクトリ形式の出力を公開準備時に単一ファイルへ整え、従来の `/simple.html` を維持します。

## スタイル

標準は読みやすい余白とシステムフォントを使います。ページ上部の「スタイル」で、ガラス風のナビゲーション、クラシック98風の枠へ切り替えられます。本文の文字サイズと背景の読みやすさは維持します。ガラス風はCSSの表現で、AppleのネイティブLiquid Glassではありません。

Webのスタイルは `website/src/styles/docs.css`、同梱ヘルプは `help.css` です。画像・フォントの外部読み込みや、動作しない飾りのウィンドウボタンは追加しません。

## 公開先と将来の移行

標準の公開先は `https://dl.wmsci.com/utatane/`、ドキュメントはその `docs/` です。生成結果は `website/dist/` にホストのルートを保った形で出力します。

```sh
# 将来の公開先でビルドする例。DNS・公開設定を変更する処理ではありません。
UTATANE_SITE_ORIGIN=https://utatane.wmsci.com UTATANE_SITE_BASE= bun run build
```

`UTATANE_SITE_ORIGIN` は公開元、`UTATANE_SITE_BASE` は配置パスです。将来は紹介サイトを `/`、ドキュメントを `/docs/` にできます。設定変更だけで本文・アセット・canonical・サイトマップのURLを生成し直します。

移行時は既存の `utatane.html`、`utatane-modern.html` と現在のWebページを対応する新ページへ直接301転送します。更新フィード・ゴースト更新・コンテンツ配信は別のURLとして維持します。サーバーの `.htaccess` はこのリポジトリから自動更新しません。

GitHub ActionsのWeb公開処理はDocsとWebの変更を対象にし、ビルド済みの `website/dist/` をFTPS転送します。本体ビルドをWeb公開の前提にはしません。転送先は既存の `WEBSITE_DEPLOY_PATH` を使い、更新フィードなど既存の別ファイルを削除しません。

## 書き漏れを確認する

メニュー、設定タブ、補助ウィンドウを説明ページへ対応づけた[説明範囲の一覧](Coverage.md)を使います。対応表に項目があることと、実際の操作手順が分かりやすいことは別です。追加した説明は、起動した配布対象のアプリで操作しながら確認してください。

## スクリーンショットを追加する

画像は `website/public/assets/screenshots/` に置き、原稿から相対Markdownリンクで参照します。例えばGuideの原稿では `../../website/public/assets/screenshots/settings-general.png` です。Webでは配置パス付きの画像URLへ、同梱ヘルプでは画像データへ変換します。

`public/` は管理する原本です。開発準備・本番ビルドで削除したり再作成したりしません。設定の画面例はスクロール領域の一部なので、全項目が掲載された画像として説明しません。画像にない項目の手順も本文で案内します。

Astroの `trailingSlash` は `ignore` にし、ディレクトリのページと `/simple.html` の両方を開発時に解決します。公開メタデータと通常ページのリンクは末尾の `/` を付けたURLで生成します。
