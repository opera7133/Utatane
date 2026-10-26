# ローカル開発ガイド

Utataneの開発へ参加する人や、自分の環境でビルド・改変したい人向けの案内です。

## 必要な環境

- macOS 14以降
- Xcode 26以降
- [mise](https://mise.jdx.dev/)
- [Zig](https://ziglang.org/)（Windows互換ホストのビルド用）
- Python 3、curl（kagari依存ソースの取得・ビルド用。初回はネットワーク接続が必要）

## セットアップ

```sh
git submodule update --init --recursive
mise install
mise run generate
mise run build
```

`Utatane.xcodeproj`は生成物です。直接直しても次の生成で消えます。ターゲットやビルド設定は`project.yml`を変更して、`mise run generate`してください。

kagariとLuaのビルド処理は[utatane-modules](https://github.com/opera7133/utatane-modules)で管理します。Utataneと同じ親フォルダへチェックアウトし、`git submodule update --init --recursive`と`uv sync --locked`を実行してください。別の配置は`UTATANE_MODULES_ROOT`で指定します。Xcodeからuvが見つからない場合は`UTATANE_UV_EXECUTABLE`に絶対パスを指定します。

移植済みのSHIORI・SAORIは[Utatane Modules](https://github.com/opera7133/utatane-modules)でビルド・配布します。アプリのビルドには含めません。

## 検証

```sh
mise run lint
mise run test
mise run build
mise run check
```

`mise run check`には、公開しているUKADOC対応表の構文名が本番コードから消えていないことを確認する検査も含まれます。新しく対応済みと記載する構文は`Scripts/check-ukadoc-compatibility.py`の一覧にも追加します。

### テストの方針

テスト件数を増やすこと自体は目標にしません。通信形式、互換仕様、保存データ、安全境界と、実際に起きた不具合の回帰確認を優先します。単純なプロパティ代入や、実装と同じ条件分岐をテスト側でも繰り返すだけの確認は追加しません。

パーサー、再生処理、画面制御の複数層を通る機能は、それぞれの責務だけを確認します。同じ結果を各層で重複して固定しないでください。同じ形式の入力を並べる場合は、引数付きテストへまとめます。

非同期処理の完了待ちには、テスト用の`requireEventually`を使います。一定時間の`Task.sleep`だけで完了を決めつけると、負荷の高いCIで不安定になります。アニメーション時間やタイムアウトそのものを検査する場合だけ、経過時間をテスト条件に含めます。

失敗が不定期に起きる場合は、対象テストを絞って繰り返し、実行タスク、グローバルなAppKit状態、時計や一時ファイルの共有を確認します。修正後は対象テストだけで終わらせず、全テストも実行します。

SwiftPMやClangがキャッシュへ書けないと言い出したら、書ける場所を指定します。

```sh
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/utatane-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/utatane-clang-module-cache \
mise run check
```

## 配布用アーカイブをローカルで作る

ユニバーサルバイナリ（arm64 / x86_64）のビルド、Windows互換ホストおよびMCPサーバーの組み込み、ZIPアーカイブの作成をまとめて実行します。

```sh
mise run package
```

生成物は `dist/Utatane-macOS.zip` に出力されます。

kagariとLuaのビルド・配布検証はUtatane Modules側で行います。

### Developer ID署名と公証

直接配布版を公証する場合は、Apple Developer Programの有効なDeveloper ID Application証明書と、
公証用の認証情報が必要です。App Store向けのApp Sandbox設定とは別の作業です。
現在の`mise run package`とGitHub Actionsは仮署名でZIPを作成します。以下は、その後に手元で行う手順です。

```sh
# 使えるDeveloper ID Application証明書の名前とSHA-1を確認
security find-identity -v -p codesigning

# 完成したアプリのコピーを署名。値は自分の証明書のSHA-1へ置き換える
python3 Scripts/sign-app.py /path/to/Utatane.app --identity YOUR_CERTIFICATE_SHA1

# 初回のみ。実行後の入力欄にアプリ用パスワードを入力する
xcrun notarytool store-credentials utatane-notary \
  --apple-id YOUR_APPLE_ACCOUNT --team-id YOUR_TEAM_ID

# 公証に送るZIPを作る
ditto -c -k --keepParent /path/to/Utatane.app /path/to/Utatane-submission.zip
xcrun notarytool submit /path/to/Utatane-submission.zip \
  --keychain-profile utatane-notary --output-format json
```

署名スクリプトは、同梱ライブラリ・ヘルパー・SparkleのXPCサービスを内側から署名します。
本体とSHIORIホストには外部dylibを読み込むためのLibrary Validation例外、本体にはApple Eventsの権限を設定します。
Sparkle Downloaderのサンドボックスと外向き通信の設定を保持し、デバッグ用の`get-task-allow`は除去します。
証明書や認証情報をリポジトリへ追加する必要はありません。

アップロードで返された`id`を使い、状態とログを確認します。初回の公証は長くかかる場合があります。

```sh
xcrun notarytool info SUBMISSION_ID --keychain-profile utatane-notary
xcrun notarytool log SUBMISSION_ID --keychain-profile utatane-notary /path/to/notary-log.json

# Acceptedになり、ログに問題がないことを確認してから実行
xcrun stapler staple /path/to/Utatane.app
xcrun stapler validate /path/to/Utatane.app
codesign --verify --deep --strict /path/to/Utatane.app
spctl --assess --type execute --verbose=2 /path/to/Utatane.app
ditto -c -k --keepParent /path/to/Utatane.app /path/to/Utatane-macOS.zip
```

ZIPには直接チケットを添付できません。アプリへ添付してから最終ZIPを作り、そのZIPに対してSparkleの更新署名を生成します。
再署名・公証したZIPは以前の配布ZIPと内容・ハッシュ・更新署名が変わるため、公開済みのZIPだけを差し替えないでください。
配布前には、署名したSHIORIホストと実際に配布するModulesを組み合わせ、読み込み・保存・再読み込みを確認してください。

[Appleの公証手順](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)も参照してください。

## コード構成

```text
apps/Utatane/              SwiftUIアプリ、状態管理、設定・カレンダー・音声UI、各モジュールの結線
packages/Package.swift     Swift Package「UtataneKit」のProduct・Target・依存定義
packages/core/             共有データ型、ゴーストイベント、プロパティ、ログ保存
packages/runtime/          ゴーストセッション、人格エンジン、会話カタログ、変数保存
packages/ghost-kit/        ゴースト設定とdescript.txtの読み込み
packages/content/          NAR、ZIP、SSPコンテンツの取り込み
packages/sakura-script/    SakuraScriptの解析と再生モデル
packages/shell/            Shell、surfaces.txt、SERIKOの解析
packages/balloon/          Balloon設定の解析
packages/platform-macos/   サーフェス・バルーン描画、SakuraScript再生、デバッグUI、実行タスク管理
packages/network/          更新、RSS、HEADLINE、SSTP、WebSocket、時刻取得・ネットワーク診断
packages/ai/               プロバイダー非依存のAI人格エンジン
packages/realtime/         Realtime APIのSDP接続要求、会話イベント・トランスクリプト処理
packages/shiori/           SHIORIメッセージ、外部ローダー、FIRST専用実装
packages/makoto/           MAKOTOトランスレータと人格応答への変換処理
packages/plugin/           プラグイン検出、要求・イベント配送、dylib接続
packages/native-saori/     SHIORIから外部SAORIへ接続するレジストリ
packages/shiori/native/    FIRST専用の人格実装
packages/shiori/external/  macOS外部SHIORIとWine上のWindows DLLへの接続
packages/mcp-server/       Utatane操作用のstdio MCPサーバー
```

`packages/`は[Package.swift](../../packages/Package.swift)を持つ単一のSwift Packageです。機能ごとのディレクトリをTargetとして登録し、依存方向と公開Productをこのファイルで管理します。パーサーや本体処理は各モジュールへ置き、SwiftUIアプリ固有の結線は`apps/Utatane`、再利用するmacOS表示・再生処理は`platform-macos`へ分けます。SHIORIの共通電文、FIRST専用実装、外部モジュール接続は`packages/shiori`内で管理します。

周辺のビルド・調査用コードは次の場所にあります。

```text
Scripts/                   生成、検証、互換ホスト、リリース用スクリプト
tools/windows-dll-host/    汎用Windows DLLホストのソース
tools/materia-shiori-host/ FIRST解析用ホストのソース
Localizations/             文字列カタログの生成元JSON
Internal-Docs/             調査記録、TODO、実装上の補足
```

## コンテンツの静的検査

ゴーストのディレクトリを指定すると、必須ファイル、Shellの既定surfaceとelement画像、SHIORIの判定、辞書内の未対応SakuraScriptを確認できます。アプリではコンテンツエクスプローラでゴーストを選び、「互換性を検査」から同じ診断を表示できます。

```bash
swift run --package-path packages utatane-validate "/path/to/ghost"
swift run --package-path packages utatane-validate --json "/path/to/ghost"
```

エラーがある場合は終了コード1、警告だけなら0を返します。辞書言語の正規表現やパスを誤検出しないよう、SakuraScript検査は一般的なscope／surface命令を含む行に限定します。静的検査なので、辞書の実行時分岐、外部SHIORI／SAORI、実際の描画までは保証しません。

開発用パレットには、SHIORI Requestの手動送信・ログからの再送、表示中ログのコピー・保存、時計イベントと予定通知を確認する仮想時刻があります。仮想時刻は指定した瞬間から実時間と同じ速さで進み、無効にするとシステム時刻へ戻ります。

開発用パレットの「内蔵SAORI」には、関数の単体テストと、実際のホストから呼ばれた内蔵SAORIのメタデータ記録があります。応答や制限は[SHIORI・SAORIの利用](../Support/Native-SHIORI.md#日時計算と開発用の確認)を参照してください。「更新チェックのみ」と仮想時刻は既存の開発ツールから使えます。仮想時刻が変更するのは時計イベント・予定通知で、SHIORI自身の時計やinternal_timeのnowはOSの時刻のままです。

実ゴーストの辞書を通す検証は、ローカル導入済みのゴーストと、改修版のYAYA 5/6・里々・華和梨のuniversal dylibを指定して実行します。元ファイルを変更せず、一時コピーへ検証用イベントを追加します。配布素材はテストfixtureとしてリポジトリへ追加しません。

```sh
UTATANE_REAL_SAORI_GHOST_ROOT="$PWD/Content/Local/Ghosts" \
UTATANE_INTERNAL_SAORI_TEST_ROOT=/path/to/rebuilt/libraries \
swift test --package-path packages --filter RealGhostInternalSaori
```

ライブラリの名前はlibyaya.dylib・libyaya-6.dylib・libsatori.dylib・libkawari.dylibです。テストはarm64とx86_64を実行するため、Apple SiliconではRosettaも必要です。実際の画面操作は、改修版の本体とModulesを組み合わせて別途確認してください。パレットで日時変換の応答を確認し、実ゴーストの会話・切替・再読み込みと、仮想時刻で時計イベントを進めた後の表示を確認します。仮想時刻は確認後に「実時間に戻す」で解除してください。

## 同梱コンテンツとローカル検証データ

再配布条件を確認済みの同梱コンテンツは`Content/Bundled`で管理します。riaの会話、シェル、専用バルーンを変更するときはこちらだけを編集してください。

```text
Content/Bundled/Ghosts/ria/
Content/Bundled/Balloons/ria/
```

Debugビルドは`Bundled`を優先し、次のgit管理外ディレクトリを重ねて読みます。こちらは手元だけで使うゴースト置き場です。

```text
Content/Local/Ghosts/
Content/Local/Balloons/
Content/Local/Headline/
Content/Local/Plugins/
Content/Local/Skins/        カレンダースキン
```

同梱対象でない実ゴーストや配布素材はコミットしないでください。利用条件を確認して、手元だけで使います。SHIORIとSAORIの実行方式は、[SHIORI・SAORIの対応範囲](../Support/Native-SHIORI.md)で説明しています。

ゴースト・SHIORI・SAORIの制作者がUtatane対応を確認する手順は、[制作者向けUtatane対応ガイド](../Creators/Content-Authoring.md)を参照してください。

firstのネイティブ解析テストは、実物をFixtureへコピーせず環境変数で指定します。未指定なら実物依存部分だけスキップされます。

```sh
UTATANE_FIRST_DLL="$HOME/Library/Application Support/Utatane/Ghosts/first/ghost/master/first.dll" \
swift test --package-path packages --filter UtataneFirstNativeTests
```

## MCPサーバー

配布版では`Utatane.app/Contents/Helpers/utatane-mcp`をMCPクライアントのstdioサーバーとして登録できます。先にUtataneを起動してください。

```sh
swift build --package-path packages -c release --product utatane-mcp
```

利用できるツールは`get_active_ghost_list`・`get_expression_table`・`SakuraScript`に加え、`get_status`・`get_log`・`raise_event`・`reload`・`dump_surface`・`dump_balloon`です。`ghost_id`を省略すると現在のゴーストを対象にします。`raise_event`はイベント名とReference配列、`reload`はghost／shell／balloon／shiori／makotoを指定できます。画像の出力先は対象ゴースト配下に限り、相対パスは`ghost/master`を基準にします。状態取得やログ取得の引数はMCPクライアントが取得する各ツールのスキーマを参照してください。
