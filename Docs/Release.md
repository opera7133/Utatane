# リリース手順

Utataneのリリースは`v`で始まるgit tagを基準にします。たとえば`v0.1.0-alpha.3`をpushすると、GitHub Actionsは次の値で配布版を作ります。

- 表示バージョン（`CFBundleShortVersionString`）: `0.1.0-alpha.3`
- 更新比較用ビルド番号（`CFBundleVersion`）: GitHub Actionsのrun number

```sh
git tag v0.1.0-alpha.3
git push origin v0.1.0-alpha.3
```

## Sparkle署名鍵

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

appcastにはGitHub Release上のZIP URLと、そのZIPを検証するSparkleのEd25519署名が入っています。タグのworkflowは、GitHub Releaseの作成後にFTPSでappcastを自動配置します。

FTPS接続には次のGitHub Actions Secretsを使用します。コアサーバーのExplicit FTPS（ポート21）へ接続するため、`DEPLOY_HOST`には`ftp://`を付けずにサーバー名だけを設定します。`DEPLOY_PATH`はファイル名を含む絶対パスです。

- `DEPLOY_HOST`
- `DEPLOY_USERNAME`
- `DEPLOY_PASSWORD`
- `DEPLOY_PATH`（例: `/public_html/utatane/appcast.xml`）
