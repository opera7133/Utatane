# リリース手順

Utataneのリリースは`v`で始まるgit tagを基準にします。通常版を小刻みに公開し、alpha・beta・rcの段階を毎回必須にはしません。通常Releaseは安定性を保証する区分ではなく、ローリングリリースに近い頻度で互換性を更新します。たとえば`v0.1.5`をpushすると、GitHub Actionsは次の値で配布版を作ります。タグ以外のビルドは`project.yml`の`MARKETING_VERSION`を使います。

- 表示バージョン（`CFBundleShortVersionString`）: `0.1.5`
- 更新比較用ビルド番号（`CFBundleVersion`）: GitHub Actionsのrun number

```sh
git tag v0.1.5
git push origin v0.1.5
```

## Sparkle署名鍵

現在のworkflowは新規Releaseを通常Releaseとして作成します。既存Releaseのpre-release指定は自動変更しません。プレビュー配布を再開する場合はCIとappcastの配信方針を別途変更してください。

Apple Developer ID署名・公証はリリース条件にしません。未公証であることを配布時に明記し、Sparkle更新署名は維持します。

公開鍵は`project.yml`の`SUPublicEDKey`にあります。秘密鍵はリポジトリへ追加せず、macOSのログインキーチェーンで管理します。

CIを初めて設定するときは、Sparkleの`generate_keys`で秘密鍵をファイルへ書き出し、その内容をGitHub Actionsの`SPARKLE_PRIVATE_KEY` Secretへ登録します。書き出したファイルはパスワードと同等なので、安全な場所で扱い、登録後は平文のまま残さないでください。

```sh
generate_keys --account dev.utatane.app -x /安全な一時保存先/sparkle-private-key
gh secret set SPARKLE_PRIVATE_KEY < /安全な一時保存先/sparkle-private-key
```

## appcastの公開

タグのworkflowは次を生成します。

- GitHub Releaseの`Utatane-macOS.zip`
- GitHub ReleaseとActions artifactの`appcast.xml`

生成された`appcast.xml`を次のURLで配信します。

```text
https://dl.wmsci.com/utatane/appcast.xml
```

appcastにはGitHub Release上のZIP URLと、そのZIPを検証するSparkleのEd25519署名が入っています。タグのworkflowは、GitHub Releaseの作成後にFTPSでappcastを自動配置します。同じ処理で、同梱しているりあゴーストとバルーンもネットワーク更新用に公開します。

```text
https://dl.wmsci.com/utatane/content/ria/updates2.dau
https://dl.wmsci.com/utatane/content/balloon-ria/updates2.dau
```

CIは配布ツリーから`.DS_Store`とYAYAの`*_variable.cfg`を除外し、各ファイルのMD5を記録した`updates2.dau`を生成します。FTPSでは実体ファイルを先に同期し、更新途中の定義をクライアントが読まないように`updates2.dau`を最後に配置します。

既にインストール済みの同梱版りあには、起動時に`homeurl`だけを補います。利用者が変更した辞書や画像などは、この移行では上書きしません。現状の更新処理はマニフェストから消えたローカルファイルを削除しないため、ファイルの削除や改名が必要な更新では別途移行処理が必要です。

FTPS接続には次のGitHub Actions Secretsを使用します。コアサーバーのExplicit FTPS（ポート21）へ接続するため、`DEPLOY_HOST`には`ftp://`を付けずにサーバー名だけを設定します。`DEPLOY_PATH`は配布ルートの絶対パスです。

- `DEPLOY_HOST`
- `DEPLOY_USERNAME`
- `DEPLOY_PASSWORD`
- `DEPLOY_PATH`（例: `/public_html/utatane`）

配布サイトは`website/`のAstro + Starlightプロジェクトと`Docs/`の原稿から生成します。`main`へサイト、Docs、生成スクリプト、検査、デプロイworkflowの変更をpushすると、`Deploy website` workflowが5言語の紹介ページ、ドキュメント、同梱ヘルプ、リリース取得、内部リンク、公開メタデータを検査してからビルド結果をアップロードします。上記4つに加えて、リポジトリへ次のGitHub Actions Secretを設定します。

- `WEBSITE_DEPLOY_PATH`（例: `/public_html`）

Web公開処理ではアプリのビルドを行いません。Explicit FTPSのreverse mirrorで生成済みの`website/dist/`を同期します。原稿やnode_modulesは送信しません。削除オプションは使わないため、公開ルートにだけ存在する更新フィードやコンテンツ配信などの既存ファイルは削除しません。標準では`utatane/`に5言語の紹介ページ、`utatane/docs/`にドキュメントを配置し、サイトマップ、robots.txt、llms.txtも生成します。旧`utatane.html`や`utatane-modern.html`などの転送規則はサーバー側で管理します。[編集・ビルド・将来のURL移行](Documentation.md)も参照してください。

以前の設定が`/public_html/utatane/appcast.xml`なら、ファイル名を外した`/public_html/utatane`へ変更してください。公開先では次の構成になります。

```text
utatane/
├── appcast.xml
└── content/
    ├── ria/
    │   ├── updates2.dau
    │   ├── ghost/
    │   └── shell/
    └── balloon-ria/
        ├── updates2.dau
        └── ...
```
