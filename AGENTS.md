# AGENTS.md

このファイルは、Utataneを変更するAIエージェント向けの作業案内です。
利用者向けの説明は`README.md`と`Docs/`、人間の開発参加者向けの手順は
`Docs/Development/Development.md`を参照してください。

## 最初に確認すること

- 既存の作業ツリーを`git status --short`で確認し、利用者の変更を上書き、削除、
  または無断でコミットしないでください。
- 変更対象に近い実装とテストを先に読み、モジュール間の依存方向を保ってください。
- 仕様の根拠が必要な互換対応では、UKADOCなどの一次資料と現在の実装を確認し、
  実装済み、テスト済み、実機確認済みを区別してください。
- 利用者に見える変更は`CHANGELOG.md`の`Unreleased`へ追記してください。
- コミットする場合はConventional Commits形式を使ってください。

## リポジトリの構成

```text
apps/Utatane/              SwiftUIアプリと各パッケージの結線
packages/                  単一のSwift Package（UtataneKit）
packages/core/             共有データ型、イベント、プロパティ、ログ
packages/runtime/          ゴーストセッションと人格エンジン
packages/sakura-script/    SakuraScriptの解析と再生モデル
packages/shell/            Shell、surfaces.txt、SERIKO
packages/balloon/          Balloon設定
packages/platform-macos/   AppKit描画、入力、SakuraScript再生
packages/shiori/           SHIORI電文、外部ローダー、ネイティブ実装
packages/shiori/native/    YAYA、里々、華和梨などのネイティブ実装
packages/shiori/external/  macOS用SHIORIとWindows DLLホストへの接続
packages/plugin/           プラグイン検出、イベント配送、dylib接続
packages/native-saori/     ネイティブSAORIレジストリ
Content/Bundled/           配布アプリへ同梱する確認済みコンテンツ
Content/Local/             手元だけで使うgit管理外コンテンツ
Docs/                      公開ドキュメントの原稿
Internal-Docs/             調査記録、計画、保守用の内部資料
website/                   Astro製の公式サイトとWebドキュメント
Scripts/                   生成、検証、互換ホスト、リリース用スクリプト
```

詳しいモジュール一覧と依存関係は`packages/Package.swift`、開発用の全体説明は
`Docs/Development/Development.md`を参照してください。

## 生成物と編集元

- `Utatane.xcodeproj`は`project.yml`から生成します。プロジェクトファイルを直接編集せず、
  `project.yml`を変更して`mise run generate`を実行してください。
- `apps/Utatane/Resources/Localizable.xcstrings`は`Localizations/*.json`から生成します。
  翻訳はJSONを編集し、`mise run localization-generate`を実行してください。
- `apps/Utatane/Resources/UtataneHelp.html`は`Docs/`から生成します。HTMLを直接編集せず、
  原稿と`Docs/navigation.json`を変更して`cd website && bun run help`を実行してください。
- 外部依存を含む生成ディレクトリ、ビルド成果物、`Content/Local/`をコミットしないでください。

## 実装上の境界

- 共有モデルやOS非依存の処理は`packages/`の該当モジュールへ置き、アプリ固有の状態や
  SwiftUIによる結線は`apps/Utatane/`へ置いてください。
- AppKit、AVFoundationなどmacOS固有の処理は原則として`packages/platform-macos/`へ置きます。
- SHIORIの共通電文は`packages/shiori/Sources/`、各人格の実装は
  `packages/shiori/native/<name>/`、外部バイナリとの接続は`packages/shiori/external/`で
  管理してください。
- `Content/Bundled/`へ素材を追加する前に、再配布条件を確認してください。実ゴーストや
  配布素材をテストfixtureとしてコピーせず、必要なら`Content/Local/`または環境変数を使います。
- 互換性表を更新するときは、実装とテストの裏付けを確認してください。部分対応や手動確認前の
  項目を完全対応として記載しないでください。

## 検証

通常の最終確認は次のコマンドです。

```sh
mise run check
```

これはSwiftFormat、Swiftテスト、UKADOC対応表、ローカライズ、Debugビルドを確認します。
SwiftPMがキャッシュへ書き込めない環境では、次のように実行します。

```sh
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/utatane-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/utatane-clang-module-cache \
mise run check
```

作業中は対象テストを絞って構いませんが、完了前には変更範囲に応じて全体確認も行ってください。
フィルタしたテストは終了コードだけでなく、対象テストが実際に1件以上実行されたことも確認します。
固定時間の`Task.sleep`へ依存するテストは避け、非同期完了には条件待ちを使ってください。

ドキュメントやWebサイトを変更した場合は、追加で次を実行します。

```sh
cd website
bun run help
bun run check
bun run build
bun run test
```

画面表示、マウス操作、音声、外部SHIORIなどは、ビルドや単体テストの成功だけでは実機確認に
なりません。未確認の範囲は作業結果に明記してください。

## ドキュメントの置き場所

- `Docs/Guide/`: アプリの利用方法
- `Docs/Support/`: トラブル対処と互換性
- `Docs/Creators/`: ゴースト、SHIORI、シェル、プラグイン制作者向け
- `Docs/Reference/`: 命令、イベント、設定ファイルなどの対応表
- `Docs/Development/`: Utataneをビルド、改変、フォークする人向け
- `Internal-Docs/`: 現在の開発計画、調査記録、リリース手順など保守用

公開ページを追加または移動するときは`Docs/navigation.json`、原稿内リンク、
`Docs/README.md`も確認してください。
