# Utatane implementation plan

この計画は、既存ゴーストの素材を使って最小ランタイムを先に完成させ、その後に互換機能と発展機能を追加する順序を示す。Windows DLLの直接実行は対象外とする。

## 設計方針

- まず「ゴースト読込 → イベント → SakuraScript → Shell / バルーン表示」を縦に動かす。
- ファイル形式の解析とmacOS表示を分離する。
- 人格エンジンは `PersonalityEngine` の実装として差し替える。
- 既存コンテンツは `Content/Local` に置き、ライセンスを確認できたものだけを `Bundled` や `Fixtures` に移す。
- 空のモジュールを先に量産せず、機能の実装開始時にSwiftPMターゲットを追加する。

## Milestone 1: Shellの最小表示

- [x] `Content/Local/Ghosts`からゴーストを検出する
- [x] `ghost/master/descript.txt`から名前を読む
- [x] デフォルトShellを検出する
- [x] PNGとPNAを合成して透過AppKitウィンドウに表示する
- [x] `surfaces.txt`の単一surfaceブロックを読む
- [x] 矩形collisionを解析してクリック位置を判定する
- [x] `animation*.interval`と`animation*.pattern*`をモデル化する
- [x] overlayアニメーションを実際に再生する
- [x] surface alias、範囲・除外指定、append定義に対応する
- [x] 複数キャラクターのsurfaceをscope別のウィンドウで管理する
- [x] バルーンをscope別に表示し、ドラッグで位置を変更できるようにする
- [x] キャラクターとバルーンのウィンドウ位置を保存・復元する

完了条件は、実在するShellのsurface、PNA透過、当たり判定、基本アニメーションを表示できること。

## Milestone 2: バルーンとSakuraScript

- [x] バルーンの`descript.txt`と画像を読み込む
- [x] キャラクターごとのバルーン画像を切り替える（Sakura / Kero）
- [x] SakuraScriptをトークンへ分解する
- [x] 話者切り替え、surface切り替え、改行、ウェイト、終了を実装する
- [x] 実行中スクリプトのキャンセル、早送り、クリック待ちを実装する
- [x] 選択肢とアンカーをクリック可能にする
- [x] 話者ごとのバルーンを会話終了まで保持し、終了後のクリックでまとめて閉じる

最初に対応するコマンドは、実際に使用するゴーストの辞書を調査して決める。

## Milestone 3: 最小人格エンジンとセッション

- [x] 変換済みセリフデータを読む`PersonalityEngine`を作る
- [x] `OnBoot`、ランダムトーク、クリックイベントを実装する
- [x] ゴーストの起動・終了・切り替えを管理する
- [x] 変数をゴースト別のApplication SupportへJSON保存する
- [x] Satori辞書から条件なしトークを抽出する開発用変換ツールを作る

この段階ではSatoriの条件式、ジャンプ、変数展開、SAORI呼び出しを完全再現しない。開発用CLIは未対応の制御構文を含む項目を除外し、`Content/Local/Converted/<ghost>.json`へ静的な起動トーク、通常トーク、終了トーク、選択肢遷移先を出力する。

現在の変換済みセリフ形式は `apps/Utatane/Resources/default-dialogue.json`。`boot`、`close`、`randomTalk`、領域名別の`mouseClick`、イベントID別の`choices`を持ち、選択肢の引数は`{{argument0}}`のようなプレースホルダーへ展開する。将来の変換ツールはこの形式を出力し、YAYA / SHIORI実装は同じ`PersonalityEngine`を直接実装する。

## Milestone 4: SSP相当の基礎機能

- [ ] 右クリックメニュー
- [ ] ゴースト、Shell、バルーンのインストールと切り替え
- [ ] NARの展開と安全なパス検証
- [ ] ネットワーク更新
- [ ] RSS / ヘッドライン取得
- [ ] SSTPサーバー
- [ ] 複数ゴーストとcommunicateイベント

外部入力とアーカイブは、パストラバーサルや意図しない実行ファイルを前提に検証する。

## Milestone 5: 互換エンジン

- [ ] SHIORIリクエスト・レスポンスのデータモデル
- [ ] 外部プロセス型SHIORIアダプター
- [ ] YAYA / Satoriの必要機能を調査して再実装範囲を決める
- [ ] YAYAまたはSatori互換エンジンを段階的に実装する
- [ ] Swiftで再実装したSAORIを読み込む仕組み

Windows DLLや同梱EXEは実行しない。未対応機能は診断情報として表示し、黙って誤動作させない。

## Milestone 6: 発展機能

- [ ] Spineなどの差し替え可能なキャラクターレンダラー
- [ ] MCPサーバーを独立した実行ターゲットとして追加する
- [ ] AI人格エンジンを`PersonalityEngine`アダプターとして追加する
- [ ] デバッグ用CLIとコンテンツ検証ツール

MCP、AI、CLIが独立したビルド・配布単位になった時点で、moonなどのタスクグラフ導入を再検討する。

## 継続的に行うこと

- 解析済みファイル形式ごとに小さなFixtureとテストを追加する
- 実在コンテンツでは目視確認し、Fixtureでは再現テストを行う
- 読み飛ばした設定や未対応構文を診断として収集する
- コンテンツのライセンス、改変可否、再配布可否を記録する
- macOSの複数画面、Spaces、フルスクリーン、スリープ復帰を確認する
