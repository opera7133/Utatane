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
| `UTATANE_VALIDATE_RUNTIME_DIRECTORY` | `var` |
| `UTATANE_VALIDATE_MAX_BYTES` | 52428800 |
| `UTATANE_VALIDATE_TIMEOUT_SECONDS` | 15 |
| `UTATANE_VALIDATE_MAX_OUTPUT_BYTES` | 2097152 |
| `UTATANE_VALIDATE_MAX_MEMORY_BYTES` | 805306368 |
| `UTATANE_VALIDATE_CONCURRENCY` | 4 |
| `UTATANE_VALIDATE_QUEUE_WAIT_SECONDS` | 10 |

アップロード容量はPHP全体の設定ではなく、アプリ内で50 MBに制限しています。さらに`.htaccess`の`LimitRequestBody`を51 MiBに設定し、PHPがmultipart bodyを処理する前にも制限します。LiteSpeedでこの設定が反映されていることを公開後の413応答で確認してください。Cloudflare側にも同等以下のリクエスト上限を設定します。

展開後は合計200 MiB、1ファイル64 MiB、検査対象のテキストは1ファイル8 MiB・合計32 MiB、5000エントリ、10000ディレクトリ、32階層までに制限します。作業ファイルと同時実行ロックはドキュメントルート外の`var/`へ0700で作成し、処理後に削除します。異常終了で残った作業領域は1時間後のリクエストで回収します。

Linuxに`/usr/bin/prlimit`または`/bin/prlimit`がある場合、子プロセスには既定で768 MiBのアドレス空間、17秒のCPU時間、256 MiBの出力ファイル、64ファイル記述子の上限も適用します。サーバーで`command -v prlimit`を確認してください。

同時実行枠が埋まっている場合、アップロード済みファイルを再送せずに済むよう最大10秒だけ空きを待ちます。それでも空かなければ`Retry-After: 5`付きのHTTP 429を返し、Web画面は最大2回まで再試行します。本格的な永続キューやFIFOは持ちません。

## Cloudflare

オリジンサーバーへ到達する前に濫用を抑えるため、`/api/v1/validate`にはCloudflareのRate limiting ruleも設定します。無料プランを基準に、URI Pathが`/api/v1/validate`と等しいリクエストをIPごとに数え、10秒間に3回を超えたら10秒間Blockする設定を初期値とします。プラン上選べる場合はHostを`utatane-validate.wmsci.com`、Methodを`POST`に限定します。

通常利用の傾向が分かってから、Security Analytics / Eventsを見て閾値を調整します。Cloudflareのカウンター反映には遅延があり、指定件数を厳密にオリジン手前で止める仕組みではないため、PHP側の同時実行制限も残します。

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
