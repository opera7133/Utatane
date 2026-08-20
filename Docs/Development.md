# 開発ガイド

## 必要な環境

- macOS 14以降
- Xcode 26以降
- [mise](https://mise.jdx.dev/)
- [Zig](https://ziglang.org/)（Windows互換ホストのビルド用）

## セットアップ

```sh
git submodule update --init --recursive
mise install
mise run generate
mise run build
```

`Utatane.xcodeproj`は生成物です。直接直しても次の生成で消えます。ターゲットやビルド設定は`project.yml`を変更して、`mise run generate`してください。

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

## コード構成

```text
apps/Utatane/             SwiftUIアプリと機能の結線
packages/core/            共有データ型とイベント
packages/content/         NARとSSPコンテンツの取り込み
packages/ghost-kit/       ゴーストとdescript.txtの読み込み
packages/runtime/         セッションと人格エンジン
packages/sakura-script/   SakuraScript解析
packages/shell/           Shell、surfaces.txt、SERIKO解析
packages/balloon/         Balloon解析
packages/platform-macos/  AppKitによる表示と入力
packages/network/         更新、RSS、HEADLINE、SSTP
packages/shiori/          SHIORIメッセージとイベント変換
packages/yaya-native/     YAYAネイティブブリッジ
packages/satori-native/   SATORIネイティブブリッジ
packages/kawari-native/   KAWARIネイティブブリッジ
packages/posix-shiori/    Aosora外部モジュールローダー
packages/windows-shiori/  Wine互換ホストとの通信
packages/mcp-server/      stdio MCPサーバー
```

依存方向は`packages/Package.swift`で管理します。パーサーや本体処理は各Packageへ、SwiftUI/AppKit固有の結線だけを`apps/Utatane`と`platform-macos`へ置きます。

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
```

同梱対象でない実ゴーストや配布素材はコミットしないでください。利用条件を確認して、手元だけで使います。ネイティブSHIORIとSAORIは[Native-SHIORI.md](Native-SHIORI.md)に分けました。

## MCPサーバー

配布版では`Utatane.app/Contents/Helpers/utatane-mcp`をMCPクライアントのstdioサーバーとして登録できます。先にUtataneを起動してください。

```sh
swift build --package-path packages -c release --product utatane-mcp
```
