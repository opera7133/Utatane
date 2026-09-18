# Utatane Validator Web

`utatane-validate`を1リクエストにつき1プロセス実行する、共有レンタルサーバー向けの小さなPHP APIです。常駐プロセス、データベース、Node.jsは使いません。

## API

- `GET /api/v1/health`
- `POST /api/v1/validate` (`multipart/form-data`の`file`フィールド)

成功時は`{"ok":true,"report":...}`を返します。ゴーストの内容にエラーがある場合も、検査自体に成功していればHTTP 200です。

```sh
curl -F file=@ghost.nar \
  https://utatane-validate.wmsci.com/api/v1/validate
```

## サーバー構成

1. 配布バンドルをサブドメインのディレクトリへ展開する。
2. サブドメインのドキュメントルートを`public_html/`に設定する。
3. x86_64 Linux版`bin/utatane-validate`に実行権限を付ける。
4. 必要なら環境変数で設定を上書きする。

| 環境変数 | 既定値 |
| --- | ---: |
| `UTATANE_VALIDATE_BINARY` | `bin/utatane-validate` |
| `UTATANE_VALIDATE_MAX_BYTES` | 52428800 |
| `UTATANE_VALIDATE_TIMEOUT_SECONDS` | 15 |
| `UTATANE_VALIDATE_MAX_OUTPUT_BYTES` | 2097152 |
| `UTATANE_VALIDATE_CONCURRENCY` | 2 |

アップロード容量はPHP全体の設定ではなく、アプリ内で50 MBに制限しています。PHPがスクリプト起動前にmultipart bodyを一時保存する点は避けられないため、公開時はCloudflare側にも同等以下のリクエスト上限を設定します。

`/licenses`では、Utataneとバイナリに組み込まれるZIP FoundationのMIT Licenseを表示します。ライセンス本文は配布バンドルにも同梱します。

## 配布バンドル

配布用バイナリは公式の`swift:6.3.1-amazonlinux2`コンテナ内でビルドします。Swiftランタイムは静的リンクされ、現在のバイナリが要求する互換性下限は`GLIBC_2.17`と`GLIBCXX_3.4.18`です。

```sh
docker run --platform linux/amd64 --rm \
  -v "$PWD:/workspace" -w /workspace \
  swift:6.3.1-amazonlinux2 \
  bash Scripts/build-validator-web-bundle.sh
```

GitHub Actionsの`Build validator web`はバンドルをartifactとして保存します。`main`へのpushでは、既存の`DEPLOY_HOST`、`DEPLOY_USERNAME`、`DEPLOY_PASSWORD` secretを使ってFTPS配置まで行います。手動実行では`deploy`を有効にした場合だけ配置します。

## ローカル確認

```sh
find services/validator-web -name '*.php' -print0 | xargs -0 -n1 php -l
UTATANE_VALIDATE_BINARY="$PWD/packages/.build/arm64-apple-macosx/debug/utatane-validate" \
  php -S 127.0.0.1:8080 -t services/validator-web/public
```
