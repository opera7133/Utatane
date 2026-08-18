# Utatane

伺か(SSP)のmacOS再実装。

## セットアップ

Xcode 26以降と [mise](https://mise.jdx.dev/) が必要。

```sh
mise install
mise run generate
mise run build
mise run test
```

`Utatane.xcodeproj` は生成物なので Git には含めない。プロジェクト定義は `project.yml` を編集する。

## 構成

```text
apps/Utatane                 macOS アプリと依存の組み立て
packages/core                ゴースト、イベントなどの共通型
packages/balloon             バルーン定義、画像規約、レイアウト値の読み込み
packages/sakura-script       SakuraScript のトークン定義と解析
packages/ghost-kit           ゴースト、Shell、素材の読み込み
packages/shell               surfaces.txt、当たり判定、アニメーション定義
packages/runtime             セッション、ユースケース、人格エンジンの境界
packages/platform-macos      AppKit / SwiftUI による表示と入力
packages/satori-converter    Satori辞書から静的なセリフを抽出する開発用CLI
```

依存方向は次のとおり。`packages/Package.swift` のターゲット依存でこれを強制する。

```text
core <- runtime <- ghost-kit
  ^        ^
  |        |
  +--------+-- platform-macos

sakura-script <- runtime
balloon --------------------> platform-macos

balloon / ghost-kit / runtime / platform-macos <- apps/Utatane
```

まずは、既存ゴーストから利用可能な Shell・バルーン素材と変換済みのセリフデータを読み込み、Utatane 内蔵の最小ランタイムで表示する。既存の Windows DLL を直接実行することは初期スコープに含めない。

開発用コンテンツは `Content/Local` に置く。このディレクトリは Git の対象外で、Debug ビルドでは `Content/Local/Ghosts` からゴースト、`Content/Local/Balloons` からバルーンを検出する。現在はSakuraとKeroのsurfaceとバルーンをscope別のウィンドウで表示し、それぞれのPNA透過、矩形当たり判定、`sometimes`のoverlayアニメーションを処理する。キャラクターとバルーンはドラッグで移動でき、位置は次回起動時に復元される。SakuraScriptの話者・scopeごとのsurface・改行・ウェイト・クリック待ち・選択肢・アンカー・クリア・終了を解釈してバルーンへ逐次表示できる。話者を切り替えても各バルーンは会話終了まで残り、終了後にどちらかをクリックすると両方閉じる。再生中のクリックによる早送りとクリック待ちの再開、リンクのイベントIDと引数の通知、アプリ画面から再生停止もできる。

会話終了から10秒経過するとバルーンを自動的に閉じ、各キャラクターを起動時のsurfaceへ戻す。ゴースト一覧の選択を変えると現在のセッションを停止して選択先を起動する。ゴースト固有の変数は `~/Library/Application Support/Utatane/State/<ghost>/variables.json` に保存する。

セリフは `DialoguePersonalityEngine` が読み、`GhostSession` を通して起動、ランダムトーク、surfaceクリック、選択肢イベントに応答する。Debugビルドでは、ゴーストのディレクトリ名に対応する `Content/Local/Converted/<ghost>.json` があればアプリ内の `default-dialogue.json` より優先する。

Satori辞書のうち、条件式・ジャンプ・変数代入を含まない静的な会話は次のコマンドで開発用JSONへ変換できる。未対応の制御構文を含む項目は除外され、変換件数と除外件数が表示される。

```sh
swift run --package-path packages utatane-satori-convert \
  Content/Local/Ghosts/memory-na/ghost/master \
  Content/Local/Converted/memory-na.json
```

今後の実装順と対応範囲は [実装計画](Docs/implementation-plan.md) を参照。

機能が独立してきたら、`shell`、`balloon`、`sstp`、`network-update`、`headlines`、`shiori`、`yaya`、`saori`、`animation`、`ai`、`mcp` などを SwiftPM ターゲットとして追加する。最初から空のターゲットは作らない。

人格エンジンは `PersonalityEngine`、キャラクター表示は将来レンダラー用プロトコルを境界にして、簡易セリフ再生から YAYA / SHIORI、通常の surface 表示から Spine などへ差し替えられるようにする。

### ツールチェーン

- Xcode / Swift 6: ビルドとアプリ実行
- SwiftPM: レイヤ間の依存管理とテスト
- XcodeGen: マージしにくい `.xcodeproj` を `project.yml` から生成
- SwiftFormat: フォーマットと CI 用の差分チェック
- mise: XcodeGen / SwiftFormat のバージョン固定と共通タスク

moon は現状では使用しない。単一言語・単一アプリで SwiftPM と役割が重なるため。将来、複数の独立したアプリやサーバーを同じリポジトリで管理する段階で再検討する。

## やりたいこと

- 基礎
  - SakuraScriptの読み取り・実行
  - Ghost/Shellの管理・表示
  - バルーンの表示
  - 位置変更
  - マウスのインタラクション
  - 右クリックメニュー
  - ゴースト切り替え
  - ネットワーク更新
  - RSS/ヘッドライン取得
  - SSTPサーバー
- 発展
  - MCPサーバー
  - AI組み込み（すでにそういうことができるゴーストもあるので、本体側でやらなくてもいい）
  - Spine（または類似ソフト）でアニメーション表示
    - マウスのインタラクションに合わせてアニメーションさせたり
    - トリッカルみたいな
  - SAORI/AYAYA対応
    - Windowsバイナリしか無いので移植
    - または仕様から再実装

## 言語

とりあえずmacOS専用で考えたいので全部Swiftで作る。

## ライセンス

YAYAのみBSD-3-Clause
