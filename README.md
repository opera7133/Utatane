# Utatane

伺か(SSP)のmacOS再実装。

## セットアップ

Xcode 26以降と [mise](https://mise.jdx.dev/) が必要。

```sh
mise install
git submodule update --init --recursive
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
packages/shiori              SHIORI/3.0 のリクエスト・レスポンスモデル
packages/yaya                Swift製YAYA解析器・互換性監査・比較用評価器
packages/yaya-native         macOS向けに移植した本家YAYAとSwiftアダプター
packages/satori-native       macOS向けに移植した本家SATORIとSwiftアダプター
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
shiori <- yaya

balloon / ghost-kit / runtime / platform-macos <- apps/Utatane
```

まずは、既存ゴーストから利用可能な Shell・バルーン素材と変換済みのセリフデータを読み込み、Utatane 内蔵の最小ランタイムで表示する。既存の Windows DLL を直接実行することは初期スコープに含めない。

開発用コンテンツは `Content/Local` に置く。このディレクトリは Git の対象外で、Debug ビルドでは `Content/Local/Ghosts` からゴースト、`Content/Local/Balloons` からバルーンを検出する。Ghostの`descript.txt`にあるSakura、Kero、`char2`以降のdefault surfaceを読み、全scopeを別ウィンドウで表示する。各scopeのPNA透過、矩形当たり判定、`sometimes`のoverlayアニメーションを処理する。キャラクターとバルーンはドラッグで移動でき、位置は次回起動時に復元される。SakuraScriptの話者・scopeごとのsurface・改行・ウェイト・クリック待ち・選択肢・アンカー・クリア・終了を解釈してバルーンへ逐次表示できる。scope 2以降の専用バルーン画像がなければKero側、Sakura側の画像へフォールバックする。話者を切り替えても各バルーンは会話終了まで残り、終了後にどれかをクリックするとすべて閉じる。再生中のクリックによる早送りとクリック待ちの再開、リンクのイベントIDと引数の通知、アプリ画面から再生停止もできる。

会話終了から10秒経過するとバルーンを自動的に閉じ、各キャラクターを起動時のsurfaceへ戻す。ゴースト一覧の選択を変えると`ghostChanging`、アプリ終了時には`close`のトークを最後まで再生し、1秒待ってから切り替えまたは終了する。`ghostChanging`がない変換済みセリフは`close`へフォールバックする。ゴースト固有の変数は `~/Library/Application Support/Utatane/State/<ghost>/variables.json` に保存する。

キャラクターを右クリックすると、インストール済みゴースト、Shell、バルーンの切り替え、ランダムトーク、バルーンを閉じる操作、アプリ終了を選べる。選択したShellとバルーンはゴーストごとに保存される。メニュー表示にはmacOS標準の`NSMenu`を使い、SSPの`menu_background`画像によるスキン表示はまだ行わない。

キャラクターはドラッグ中も使用中の画面の下端へ密着し、左右の画面外へ移動しない。メイン画面または右クリックメニューの「NARをインストール」から、ゴースト、Shell、バルーンを追加できる。同名コンテンツは上書きせず、危険なアーカイブ内パス、シンボリックリンク、過大なアーカイブは拒否する。

セリフは `DialoguePersonalityEngine` が読み、`GhostSession` を通して起動、ランダムトーク、surfaceクリック、選択肢イベントに応答する。Debugビルドでは、ゴーストのディレクトリ名に対応する `Content/Local/Converted/<ghost>.json` があればアプリ内の `default-dialogue.json` より優先する。

Satori辞書のうち、条件式・ジャンプ・変数代入を含まない静的な会話は次のコマンドで開発用JSONへ変換できる。未対応の制御構文を含む項目は除外され、変換件数と除外件数が表示される。

```sh
swift run --package-path packages utatane-satori-convert \
  Content/Local/Ghosts/memory-na/ghost/master \
  Content/Local/Converted/memory-na.json
```

機能が独立してきたら、`sstp`、`network-update`、`headlines`、`saori`、`animation`、`ai`、`mcp` などを SwiftPM ターゲットとして追加する。`shiori`と`yaya`は互換エンジンの着手に合わせて追加済み。最初から空のターゲットは作らない。

人格エンジンは `PersonalityEngine`、キャラクター表示は将来レンダラー用プロトコルを境界にして、簡易セリフ再生から YAYA / SHIORI、通常の surface 表示から Spine などへ差し替えられるようにする。

`UtataneShiori`は`GhostEvent`を`OnBoot`、`OnClose`、`OnGhostChanging`、`OnMouseClick`、`OnSecondChange`、選択肢IDのSHIORI/3.0リクエストへ変換する。`UtataneYayaNative`は本家YAYAの`500`ブランチをmacOS/Apple Silicon向けに移植し、Wineを介さず複数のYAYA VMをSHIORIで呼び出せる。Emilyで実物の辞書をロードし、`OnBoot`の200応答とSakuraScriptを受け取る統合テストまで通している。

アプリは`ghost/master/yaya.txt`または`yaya_config.txt`を検出するとネイティブYAYAを人格エンジンとして選ぶ。ロードに失敗した場合だけ従来の変換済みJSONへフォールバックする。起動、終了、ゴースト切り替え、ランダムトーク、キャラクターごとのマウスクリック、選択肢をSHIORIへ変換し、返された`Value`をそのままSakuraScriptプレイヤーへ渡す。

`UtataneYaya`のSwift製実装は削除せず、設定と辞書の監査、ASTの調査、ネイティブ版との比較に利用する。コメント、行継続、ヒアドキュメントを含む字句解析と、式・関数・条件分岐・選択・ループのAST、および主要なシステム関数を実行する比較用評価器を含む。

設定、時計、稼働時間、永続変数、ファイル操作は`YayaRuntimeEnvironment`越しに取得する。標準のmacOS実装はテキストストリームのopen/read/write/close、削除、改名、列挙、属性取得を提供する。任意のファイルパスはゴーストのmasterディレクトリ以下に制限し、親参照やシンボリックリンクを解決した結果がルート外なら拒否する。アプリが明示した変数保存先だけは別の信頼済みパスとして扱う。評価器はWineやWindows DLLを直接扱わない。`LOADLIB / REQUESTLIB / UNLOADLIB`は未対応能力として監査に残し、将来必要になった場合も任意の外部アダプターとして分離する。

YAYA辞書全体の互換性は、次のCLIでまとめて確認できる。`#define / #globaldefine`を辞書順に展開し、最初の問題で止まらずファイルごとの字句・構文問題を一覧にする。さらに全ASTの関数呼び出しを走査し、ユーザー定義関数と実装済みシステム関数のどちらにも解決できない呼び出しを、参照数の多い順で集計する。

```sh
swift run --package-path packages utatane-yaya-audit \
  Content/Local/Ghosts/emily4/ghost/master
```

Emilyでは33辞書すべてが文ASTまで解析できることを確認済み。システム関数の初回集計は61種類・554呼び出しで、文字列・配列・正規表現・設定・時計・永続変数・ファイル・文字幅変換をまとめて実装した後は7種類・16呼び出し。残りは配列デリミタ、動的な変数名、関数置換型正規表現、FMO、DLL関連になる。未対応関数が残る通常監査は終了コード1を返す。

全辞書を結合して実際の関数を評価する場合は`--entry`を使う。複数指定した順に同じ評価器で実行する。Emilyは`load`後の`OnBoot`がSakuraScript文字列を返すところまで互換テスト済み。

```sh
swift run --package-path packages utatane-yaya-audit \
  Content/Local/Ghosts/emily4/ghost/master \
  --entry load --entry OnBoot
```

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

YAYA公開ソースはBSD-3-Clauseで、macOS移植forkを`packages/yaya-native/Sources/CYayaNative/Vendor/YAYA`のsubmoduleとして固定する。SATORI公開ソースは`packages/satori-native/Sources/CSatoriNative/Vendor`のsubmoduleとして固定する。ローカルのゴースト素材は配布物へ自動では含めない。Windows限定のFMOとDLLロードはmacOS版では提供しない。

submoduleを含めてcloneする場合は`git clone --recurse-submodules`を使う。既存cloneでは`git submodule update --init --recursive`を実行する。
