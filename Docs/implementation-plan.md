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
- [x] 実際に文字が出たscopeだけバルーンを表示し、長文を自動追従・手動スクロール可能にする

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

- [x] キャラクターの右クリックメニュー
- [x] インストール済みゴースト、Shell、バルーンの列挙と切り替え
- [x] ゴーストごとのShell・バルーン選択を保存・復元する
- [x] ゴースト、Shell、バルーンのNARインストール
- [x] ゴーストのドラッグ時に画面下部へ密着させ、画面外へ出さない
- [x] NARの展開と安全なパス検証
- [x] Ghostの`descript.txt`から各scopeのdefault surfaceを読み、scope 2以降も起動時に表示する
- [x] 終了する時（切り替える時）のメッセージを出す（アプリを終了する前に、該当のメッセージがあったらメッセージをだしてしばらくしてから終了する。切り替えるときは、同様にメッセージを出してしばらくしてから切り替える）
- [ ] 頭撫で、髪さらさらなどのアクションに対応（Localに置いてあるゴーストのうち、twinは少なくとも対応してるはず）
- [ ] ゴーストにNARファイルをドラッグアンドドロップでインストール（また、キャラにインストール時の対応するメッセージがあれば表示）
- [ ] ネットワーク更新
- [ ] RSS / ヘッドライン取得
- [ ] SSTPサーバー
- [ ] 複数ゴーストとcommunicateイベント

外部入力とアーカイブは、パストラバーサルや意図しない実行ファイルを前提に検証する。
右クリックメニューはmacOS標準の`NSMenu`を使う。Shellの`menu.background.bitmap.filename`などを使ったSSP風のスキン描画は、独自メニュー実装が必要になるため当面の対象外とする。
NARは圧縮サイズ、ファイル数、展開後サイズに上限を設け、絶対パス、親ディレクトリ参照、バックスラッシュを含むパス、シンボリックリンク、既存コンテンツへの上書きを拒否する。ゴーストNARに`balloon.source.directory`が指定されている場合は同梱バルーンも同時にインストールする。

## Milestone 5: 互換エンジン

- [x] SHIORI/3.0リクエスト・レスポンスとイベント参照値のデータモデル
- [x] Ghostイベントを`OnBoot`、`OnClose`、`OnGhostChanging`などへ変換するSHIORIアダプター
- [x] YAYAの設定ファイルと辞書includeを読み込む
- [x] YAYA辞書のコメント、行継続、ヒアドキュメント、演算子を位置情報付きで字句解析する
- [x] リテラル、識別子、関数呼び出し、添字、単項・二項演算を式ASTへ解析する
- [x] YAYAの関数定義と`if`、`elseif`、`else`、`return`を文ASTへ解析する
- [x] YAYAの`random`、`sequential`、`nonoverlap`、`array`選択と`case / when / others`を解析・評価する
- [x] YAYAの`for`、`foreach`、`while`、`break`、`continue`を文ASTへ解析・評価する
- [x] YAYAの`parallel`と文字列内の`%(...)`埋め込み式を評価する
- [x] YAYAの参照引数、添字先への代入とユーザー関数からの書き戻しを評価する
- [x] YAYAの`switch`、波括弧を省略した`when / others / if`を解析・評価する
- [x] `#define / #globaldefine`を辞書順に展開する前処理と全辞書互換性監査を実装する
- [x] 全ASTの関数呼び出しから未実装システム関数を参照数付きで一括監査する
- [x] 設定、時計、永続変数、制限付きファイル情報を`YayaRuntimeEnvironment`へ分離する
- [x] 制限付きテキストストリーム操作と半角・全角変換を実装する
- [x] Emilyの全辞書を結合して`load`から`OnBoot`のSakuraScript返却まで互換テスト化する
- [x] 本家YAYAをmacOS/Apple Silicon向けに移植し、Swiftから複数VMの`load / request / unload`を呼べるようにする
- [x] ネイティブYAYAへEmilyのSHIORI `OnBoot`を送り、200応答とSakuraScriptを受け取る統合テストを追加する
- [x] YAYA設定を持つゴーストではネイティブYAYAを`PersonalityEngine`として選択する
- [x] 起動、終了、切り替え、ランダムトーク、scope付きクリック、選択肢をSHIORIへ変換する
- [x] 手動ランダムトークを`OnAITalk`として送り、`OnSecondChange`の定期通知と区別する
- [x] リテラル、配列、変数、関数、基本演算、条件分岐の最小評価器を実装する
- [ ] YAYAのシステム関数、SHIORI関数、永続変数を必要なものから実装する
- [ ] Emilyの`OnBoot`、ランダムトーク、マウス反応、`OnClose`を順に互換テスト化する
- [x] Windows DLLを使わない`YayaPersonalityEngine`を`PersonalityEngine`として接続する
- [ ] Windows DLL向けの外部プロセス型SHIORIアダプターを必要に応じて追加する
- [ ] Swiftで再実装したSAORIを読み込む仕組み

Windows DLLや同梱EXEは実行しない。未対応機能は診断情報として表示し、黙って誤動作させない。

YAYAは完全なSwift再実装を本番経路にせず、本家公開ソースのPOSIX実装をmacOS向けに移植した`UtataneYayaNative`を優先する。`Content/Local/Ghosts/emily4/ghost/master`を実物の互換性テスト入力にし、Swift製`UtataneYaya`は辞書監査、AST調査、差分検出用として残す。

取り込み元は`References/Local/YAYA`の`500`ブランチ、commit `f64a42d`（tag `Tc573-6`、BSD-3-Clause）。`packages/yaya-native`にUTF-8化したforkとライセンスを保持する。変更範囲は現代のClang/libc++対応、Darwinのマクロ衝突、固定幅整数、POSIXリクエストバッファの所有権、Swift向けの小さなC ABIに限定する。Windows限定のFMOとDLLロードは無効のままにする。

Swift製`UtataneYaya`は元実装の`parser0.cpp`、`parser1.cpp`、VMを境界として「設定と入力解決 → 字句・構文解析 → 検査 → 評価」を分離する。`include`、`includeEX`、`dic`、`dicif`、基本的な`dicdir`と辞書文字コードを解決する。`dicdir`のloading-orderファイルはまだ未対応で、検出時は診断を返す。

辞書読込は宣言された文字コードを使い、UTF-8 BOMは除去する。Emilyの`yaya_config.txt`のようにUTF-8指定と実体が一致しない入力は、不正バイトを置換して警告を残し、ASCII部分の解析を継続する。Emilyの現在の全辞書は字句エラーなしで走査でき、実際の`OnFirstBoot`と`OnBoot`は関数・文ASTまで解析できることをローカル確認する。式パーサーは元実装の`formulatag`と優先順位を基準にする。

最小評価器はFixtureの`OnBoot`を実行し、グローバル変数の更新とSakuraScript文字列の返却まで確認する。関数とブロックの`random`、`sequential`、`nonoverlap`、`array`選択、`--`で分割された領域の結合、`case / when / others`を評価できる。組み込み関数は従来の`STRLEN`、`TOINT`、`ARRAYSIZE`、`ISVAR`、`ISFUNC`、`RAND`、`EVAL`に加えて、文字列の検索・置換・分割、型変換、配列検索、正規表現の検索・完全一致・置換・分割・キャプチャ取得、`STRFORM`の整数書式、設定、時計、関数一覧、永続変数などに対応した。引数なしのシステム関数を`GETTIME[0]`のように値として参照するYAYA記法も評価する。選択乱数はテストから差し替え可能にし、`sequential`と`nonoverlap`の状態は評価器ごとに保持する。

Emilyのマウス方向判定、`OnBoot_* : array`、`aya_word.dic`のループと`parallel`を縮小したFixtureで互換動作を確認している。`for`、`foreach`、`while`は暴走辞書を止める反復上限を持ち、テスト時に変更できる。実物の`aya_word.dic`は辞書全体を文ASTまで解析できることもローカル確認した。

参照引数`&`、添字先への単純代入・複合代入と、ユーザー関数の`_argv`更新を呼び出し元へ書き戻す処理に対応した。Emilyの`E.Swap(&_array[...], ...)`と、参照配列をさらに別の関数へ渡すケースをFixtureで確認している。

YAYAの`switch`は0始まりの候補番号選択として評価する。`case`内の前置文と、波括弧を省略して単一文を続ける`when / others / if`にも対応した。`#define`は辞書内、`#globaldefine`は設定に記載された後続辞書へテキスト展開する。

互換性監査は設定に含まれる辞書をすべて処理し、最初のエラーで停止せずファイル単位で問題を集約する。さらに全ASTを走査して、ユーザー定義関数にも実装済みシステム関数にも解決できない静的な関数呼び出しを集計する。ランダム分岐の実行結果に左右されず、辞書内の全候補を一度に確認できる。`utatane-yaya-audit`でEmilyを監査した現在の結果は33辞書中33辞書が文ASTまで解析成功、構文問題0件。未実装システム関数は初回の61種類・554呼び出しから7種類・16呼び出しまで減った。残りは`SETDELIM`、`LETTONAME`、`RE_REPLACEEX`、FMO、DLL関連。全辞書を結合して`load`後に`OnBoot`を評価し、3キャラクター用のSakuraScript起動トークが返るところまでローカル互換テストにした。

`YayaRuntimeEnvironment`は評価器から設定、時計、稼働時間、変数保存、ファイル操作を分離する。`YayaNativeRuntimeEnvironment`は設定ファイルの値と`coreinfo.*`、テキストストリーム、削除、改名、列挙、属性取得を提供し、変数をJSONで保存する。任意パスは親参照とシンボリックリンクを解決してmasterディレクトリ外なら拒否し、アプリが指定した変数保存先だけを別の信頼済みパスとして許可する。WineやWindows DLLはこの標準環境へ含めず、`LOADLIB / REQUESTLIB / UNLOADLIB`は未対応として明示する。将来必要な場合も別プロセス型の任意アダプターに限定する。

実物の実行で判明したYAYA互換差として、未定義変数と範囲外添字は`void`、配列の数値変換は0、値を積んだ後の引数なし`return`はそれまでの選択結果、`EVAL`は関数名専用ではなくYAYA式の評価として扱う。これらは縮小FixtureとEmilyの`load → OnBoot`で確認する。

`Content/Local/Ghosts/emily4`はYAYA利用、scope 2のdefault surface 200、char2以降のShell配置設定を含む実例として使う。scope 2以降の起動時表示とSakuraScriptの話者切り替えには対応済み。専用バルーン画像がなければKero側、Sakura側の順にフォールバックする。アプリはYAYA設定ファイルを検出してネイティブ人格を選び、Emily本来の`OnBoot`応答をSakuraScriptプレイヤーへ渡す。YAYAのロードに失敗した場合だけ変換済みセリフへフォールバックする。

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
