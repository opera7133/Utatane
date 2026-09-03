# 開発ガイド

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

kagariとLuaはXcodeのビルドフェーズで自動同梱します。依存ソースのバージョン・SHA-256は`tools/native-shiori/kagari-dependencies.json`で固定し、`.generated-native-shiori/`にキャッシュします。ソース・ビルドスクリプト・CPU・Xcode/SDKが変わると再ビルドします。独自のXcodeビルドスクリプトがネットワークとキャッシュを利用するため、ターゲットのUser Script Sandboxingは無効です（ゴースト実行のサンドボックス設定ではありません）。

## 検証

```sh
mise run lint
mise run test
mise run build
mise run check
```

SwiftPMやClangがキャッシュへ書けないと言い出したら、書ける場所を指定します。

```sh
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/utatane-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/utatane-clang-module-cache \
mise run check
```

## リリース・パッケージング

ユニバーサルバイナリ（arm64 / x86_64）のビルド、Windows互換ホストおよびMCPサーバーの組み込み、ZIPアーカイブの作成をまとめて実行します。

```sh
mise run release
# または
mise run package
```

生成物は `dist/Utatane-macOS.zip` に出力されます。

Releaseビルド後に`mise run test-kagari`で、同梱されたkagariとLuaの構成・ライセンスと、移動後の実ロードを検証できます。

タグから配布する手順とSparkle用appcastについては[リリース手順](Release.md)を参照してください。

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
packages/shiori/           SHIORIメッセージとイベント変換
packages/makoto/           MAKOTOトランスレータと人格応答への変換処理
packages/plugin/           プラグイン検出、要求・イベント配送、dylib接続
packages/native-saori/     ネイティブSHIORI共通のSAORIレジストリ
packages/yaya-native/      YAYA本体とSwiftブリッジ、AYA互換の読み込み
packages/satori-native/    SATORI本体とSwiftブリッジ
packages/kawari-native/    KAWARI本体とSwiftブリッジ
packages/misaka-native/    MISAKA辞書のSwift実装
packages/akari-native/     灯のイベント資源、AZR、AMBのSwift実装
packages/ese-shiori-native/ ese-shiori 3.03辞書の復号とSwift実装
packages/first-native/     利用者所有のfirst.dllを読む専用人格
packages/posix-shiori/     macOS外部SHIORIのdylibローダー、SHIOLINK外部プロセス接続
packages/windows-shiori/   Wine互換ホストとWindows DLLの通信
packages/mcp-server/       Utatane操作用のstdio MCPサーバー
packages/kagari-native/    kagariの上流ソース（Xcodeビルド時にdylibを同梱、SwiftPMターゲットではない）
```

`packages/`は[Package.swift](../packages/Package.swift)を持つ単一のSwift Packageです。機能ごとのディレクトリをTargetとして登録し、依存方向と公開Productをこのファイルで管理します。パーサーや本体処理は各モジュールへ置き、SwiftUIアプリ固有の結線は`apps/Utatane`、再利用するmacOS表示・再生処理は`platform-macos`へ分けます。YAYA、SATORI、KAWARIの上流コードとC/C++ブリッジも、それぞれの`*-native`ディレクトリ内で管理します。

周辺のビルド・調査用コードは次の場所にあります。

```text
Scripts/                   生成、検証、互換ホスト、リリース用スクリプト
tools/native-shiori/       外部macOS SHIORIのローカルビルド補助
tools/windows-dll-host/    汎用Windows DLLホストのソース
tools/materia-shiori-host/ FIRST解析用ホストのソース
Localizations/             文字列カタログの生成元JSON
Internal-Docs/             調査記録、TODO、実装上の補足
```

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

同梱対象でない実ゴーストや配布素材はコミットしないでください。利用条件を確認して、手元だけで使います。ネイティブSHIORIとSAORIは[Native-SHIORI.md](Native-SHIORI.md)に分けました。

ゴースト・SHIORI・SAORIの制作者がUtatane対応を確認する手順は、[制作者向けUtatane対応ガイド](Content-Authoring.md)を参照してください。

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
