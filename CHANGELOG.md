# Changelog

## [0.1.4] - 2026-08-28

### 追加

- キャラクターのドラッグ中は半透明にし、ポインター付近に座標と移動量を表示。ドラッグ終了やEscapeなどで元の不透明度へ戻す

### 修正

- リアルタイム音声対話の画面、接続状態・エラー表示、設定やメニューなどに残っていた未翻訳の文言を、日本語・英語・中国語（簡体字／繁体字）・韓国語に対応
- 言語変更後の「今すぐ再起動」で非同期の終了処理が進まなくなる問題を修正。ゴーストの終了処理と保存が完了してから同じ場所のアプリを起動し直し、二重操作を防止。再起動の準備に失敗した場合はエラーを表示
- 同梱ゴースト「りあ」がお出かけから戻る際、帰宅の台詞と再表示が行われず不在のままになる問題を修正。会話できない間は帰宅処理を保留し、お出かけ中の服装更新で早く再表示される問題も修正
- 初回起動イベントから「りあ」の起動メッセージを表示するよう修正
- `.nar`のファイル形式宣言と既定アプリ候補の登録を修正し、Finderから開いたNARをインストール処理へ渡すよう変更。既存の関連付けは強制変更しない
- サーフェスを動かしたときにバルーンも同じ量だけ追従するよう修正。バルーンだけを動かした場合はサーフェスの位置を変えず、手動調整した相対位置も維持

### 開発・検証

- 未翻訳の静的UI文字列の検査と、音声画面の5言語テストを追加。初回起動、帰宅、バルーン追従、ドラッグ表示、再起動の終了待ちを回帰テストで検証

## [0.1.3] - 2026-08-28

### 変更

- デバッグ表示がオフのときはログ画面を生成しないようにし、非表示中の画面更新によるCPU・メモリ負荷を軽減
- ログ履歴を最大2,000件の固定長バッファへ変更し、ログごとの履歴全件コピーと画面更新用タスクの生成を廃止。表示中のみ100ms間隔で変更をまとめて反映し、非表示中もイベント・ログの記録は継続
- 開発ガイドのパッケージ構成と実行処理・ログ管理の説明を更新。紹介ページの同梱キャラクターに関する表現を調整

### 修正

- デバッグ画面を閉じたり表示を切り替えたりすると、`OnSecondChange`などの周期処理が停止する問題を修正。実行タスクをアプリ側で管理し、再表示時の二重起動を防止
- ウィンドウの非表示でセリフ再生・SSTP・ネットワーク監視を停止しないようにし、アプリ終了時に停止するよう変更

## [0.1.2] - 2026-08-28

### 追加

- SHIOLINKに対応。MiyoJSなどの外部SHIORIをmacOSのプロセスとして起動し、標準入出力で接続できるようにした（Node.js等のランタイムと栞は別途用意が必要）
- AYA（文）の`aya5.txt`／`aya.txt`を検出し、内蔵YAYAで実行する経路を追加。設定名に対応した状態保存と、`OnAITalk`に台詞がない場合の`OnAiTalk`へのフォールバックに対応
- kagari（Lua）のmacOSネイティブ接続とビルド手順を追加。現時点では利用者ビルドの外部ライブラリを使用し、ゴースト固有のLua C拡張やSAORIは同梱しない

### 変更

- ゴースト終了時にSHIORIの終了処理を明示的に呼び、外部プロセスやネイティブ栞を解放するようにした
- ゴースト互換表とWebサイトの対応SHIORI表記を更新。別デザインの紹介ページと、不具合・ゴースト互換性の報告用Issueテンプレートを追加

## [0.1.1] - 2026-08-28

### 修正

- ゴースト再読込時に、直前のサーフェス・着せ替え・非表示状態を保持するようにした
- 起動準備中のサーフェス表示を抑制し、非表示のキャラクターがアニメーション開始だけで再表示される問題を修正
- bindアニメーションの初期画像が再生中のフレームに重なり、まばたきで目が二重に見える問題を修正
- HTTPのゴースト・バルーン更新先がmacOSの通信制限で拒否される問題に対応。HTTPSの証明書検証とアプリ更新のSparkle署名検証は維持
- 更新一覧の取得失敗時に、元の通信エラーをログへ残すよう改善

### 変更

- 同梱ゴースト「りあ」のまばたきを`rarely`へ変更し、頻度を抑えた
- GitHub Actionsから新規作成するReleaseをpre-releaseではなく通常Releaseに変更

## [0.1.0] - 2026-08-28

### 追加

- SakuraScriptの`\\_l[x,y]`（バルーン内カーソル移動）に対応。絶対・相対座標と、px・em・lh・%の単位指定をサポート
- `\![execute,http-get,...]`の`--async`・`--sync`の動作を明確化。`--async`はSakuraScriptを継続して完了イベントを後から通知し、`--sync`は完了まで再生を停止する

### 変更

- バルーンアンカークリック時に`OnAnchorSelectEx`を優先し、スクリプトがなければ`OnAnchorSelect`へフォールバックする経路を実装した
- `\__q`（範囲選択肢）の終端で暗黙の改行を挿入しないようにし、空白で区切った複数リンクを同一行へ配置できるようにした
- surfaces.txtでインラインコメント（`//`以降）を除去するようにした
- シェルのサーフェス画像として`.apng`拡張子のファイルを認識するようにした（表示は先頭フレームのPNG相当）

### 修正

- NARのZIPエントリ名にWindowsバックスラッシュ区切りが含まれる場合に、展開後のファイルツリーを安全に正規化してインストールできるようにした
- SATORIの`OnAnchorSelectEx`で拡張引数を正しく処理できていなかった問題を修正
- textcopy2 SAORIのテストでシステムのクリップボードを汚染していた問題を修正

## [0.1.0-alpha.15] - 2026-08-27

### 追加

- SNTP時刻同期イベントに対応。SakuraScriptの`\7`・`\![executesntp]`でHTTP Dateによる時刻取得を開始し、`OnSNTPBegin`・`OnSNTPCompareEx`/`OnSNTPCompare`・`OnSNTPCorrectEx`/`OnSNTPCorrect`・`OnSNTPFailure`をゴーストへ送信するようにした。`\6`で補正要求を送信できるようにした
- `SNTPEventCoordinator`・`SNTPClient`を新設し、HTTP `HEAD`リクエストで取得したサーバ時刻とローカル時刻の差分を計算できるようにした
- デバッグウィンドウに「開発ツール」ペインを追加。当たり判定の表示切り替え・バルーンテスト表示・SakuraScript直接入力・サーフェステスト（スコープとサーフェスIDの選択・アニメーション再生・コリジョン確認）・SERIKO Inspectorを含む
- `GhostSession`でSHIORIのリクエスト・レスポンス・エラーをデバッグウィンドウへ出力するようにした
- 公式配布サイト（`website/`）のHTMLと画像を追加し、`main`へのプッシュで自動デプロイするGitHub Actionsワークフローを整備

### 変更

- 同梱ゴースト「りあ」に数日をかけて段階的に進む生活エピソード（課題・読書・プレイリスト）のトークと、外出先から帰宅した際の短いトークを追加
- 同梱ゴースト「りあ」に短期記憶（3日間有効）を実装し、直近の外出を後の会話で想起するようにした

## [0.1.0-alpha.14] - 2026-08-26

### 追加

- プラグインシステムを実装。`PluginCatalog`・`PluginRuntime`・`PluginMessage`を新設し、ネイティブSHIORI型（YAYA・SATORI・KAWARI・美坂・灯）・macOS dylib・Windows DLLをプラグインとして認識・読み込みできるようにした
- SakuraScriptの`\![raiseplugin,...]`・`\![notifyplugin,...]`でプラグインを呼び出し、ゴーストへ結果を返せるようにした。プラグイン呼び出し失敗時は`OnRaisePluginFailure`・`OnNotifyPluginFailure`をゴーストへ送信
- プラグインの`OnSecondChange`を毎秒配送するようにした
- macOS dylib（`loadu`/`load`・`unload`・`request` ABI）を`DynamicLibraryModuleSession`で直接ロードし、SHIORIおよびSAORIとして呼び出せるようにした
- Wine経由の Windows DLL を汎用ホストプロセスとして`WindowsDLLModuleProcessSession`で管理し、SHIORI・SAORIとして呼び出せるようにした
- `NativeSaoriRegistry`に外部モジュールファクトリを追加し、dylib・DLLをSAORIとしても利用できるようにした
- `ExternalModuleRuntime`でdylib/DLL SHIORIをPersonalityEngineとして接続できるようにした
- カレンダー機能を追加。スケジュールの作成・編集・繰り返し（毎週・毎月・毎年）・iCalendarファイルからの取り込みに対応したウィンドウ（`CalendarWindowController`）を追加
- カレンダーのスキン（HTMLベース）に対応。`CalendarSkin`・`CalendarSkinLoader`でスキンディレクトリを読み込み、カレンダーウィンドウに適用できるようにした
- スケジュール開始5分前に`OnSchedule5MinutesToGo`をゴーストへ送信するようにした
- スケジュールのSHIORIイベント（`OnScheduleRead`・`OnSchedulesenseBegin`/`Complete`/`Failure`・`OnSchedulepostBegin`/`Complete`）をゴーストへ送信するようにした
- NARの`install.txt`でプラグイン・カレンダースキン・カレンダープラグイン種別のコンテンツをインストールできるようにした
- SSTPの`GetPluginNameList`で認識済みプラグイン名を返すようにした
- 灯（Akari）のプラグインライフサイクル（`load`・`loadPlugin`・`_create_thread`によるバックグラウンドワーカー・グローバル変数の完了時反映）と`_customrequest`によるプラグイン要求処理に対応
- 操作メニューに「カレンダー」（⌘⇧K）と「Surfaceを再表示」（⌘⇧R）を追加

### 変更

- KAWARIレガシー変換（`kawari.ini`）でダブルクリックエントリーとサーフェス復元スクリプトを抽出し、互換性を向上
- KAWARIレガシー変換で`translateLegacyIfSyntax`によるIF構文の翻訳を追加

### 修正

- 美坂（Misaka）の文字コード処理とサーフェス定義解析の互換性を改善
- 灯（Akari）のAZR実行と変数処理の不具合を修正
- SATORIのPOSIX文字コード処理を修正
- `OnRestoreSurface`イベントが正しく処理されない問題を修正
- surfaces.txtのサーフェス範囲解析を修正
- SakuraScriptパーサーで`\q`の直後に数値スロットが付く旧形式を正しく扱えるようにした
- バルーンのテキストリンクヒット判定を修正
- SurfaceWindowControllerのテスト対象コードを修正

## [0.1.0-alpha.13] - 2026-08-26

### 追加

- 美坂（Misaka）をSHIORIとして使うゴーストのネイティブ実行に対応
- 灯（Akari）をSHIORIとして使うゴーストのネイティブ実行に対応。イベント辞書・単語・条件・ジャンプ・変数・`.azr`スクリプト・配列・辞書・ JSON・Base64・正規表現・ファイル操作・`.amb`アーカイブの読み込みに対応
- 共通ネイティブSAORIレジストリ`UtataneNativeSaori`を分離パッケージとして分離。`saori_cpuid`・`kenonoke`・`textcopy2`に加え、`mciaudior`・`wmove`のネイティブSAORI互換を追加
- 各SHIORIから共通レジストリへアクセスするNativeSaoriWindowAdapterを追加
- OpenAI Realtime API・互換APIへ接続してゴーストとリアルタイム音声会話を行う実験的機能を追加（Realtime API対応ブラウザウィンドウ、SDPネゴシエーション、トランスクリプト取得、ゴーストへの表情連動）
- ゴーストの`realtime.json`でRealtime会話時の表情サーフェスを指定できるマニフェスト第1版を追加
- アプリ内ヘルプ（HTML）をmacOSのヘルプメニューから開けるようにし、ゴーストの`\![open,help]`から専用ヘルプがない場合はUtataneヘルプへフォールバックするようにした
- 右クリックメニューの順序をネットワーク・機能・設定・コンテンツ切り替え・情報・終了のSSP準拠の順序へ整理
- `x-ukagaka-link`スキームをInfo.plistに登録
- 日本語・英語・簡体中文・繁体中文・韓国語の局在化リソースをJSON形式で管理し、生成スクリプトでXcodeカタログへ反映するワークフローを整備
- 設定画面でアプリの表示言語を切り替えられるようにした

### 変更

- KAWARIが共通SAORIレジストリを受け入れるようにした
- 同梱ゴースト「りあ」のチーク空配列の連結前に要素数を確認し、空要素が混じり込む問題を修正

## [0.1.0-alpha.12] - 2026-08-25

### 追加

- バッテリー残量・充電状態・電源種別を取得する`BatteryMonitor`を追加。`OnBatteryNotify`・`OnBatteryLow`・`OnBatteryCritical`・`OnBatteryChargingStart/Stop`をゴーストへ通知
- ネットワーク接続状態とインターフェース一覧を監視する`NetworkStatusMonitor`を追加。`OnNetworkStatusChange`でゴーストへ通知
- フルスクリーンアプリの検出機能を追加。別アプリがフルスクリーン展開中はゴーストとバルーンを非表示にし、`OnFullScreenAppMinimize/Restore`を送信
- ゴーストどうしの重なりと画面外へのはみ出し状態を検出する`WindowLayoutSnapshot`を追加
- SakuraScriptからファイル・フォルダー・カラーのシステムダイアログを開く`systemDialog`命令と`closeSystemDialog`を追加
- surfaces.txtの`cursor`ブロックでコリジョン領域ごとにカーソル形状を設定できるようにした
- surfaces.txtの`tooltips`ブロックでコリジョン領域ごとにツールチップを設定できるようにした
- `OnGhostChanging`のReferenceに切り替えモード、ゴースト名、パスを含む詳細情報を渡せるようにした
- HTTPリクエストがタイムアウトした際に`OnNetworkHeavy`をゴーストへ送信するようにした
- Windows DLLホストのCライブラリリンクを廃止し、`SOURCE_DATE_EPOCH`またはGitコミット時刻をバイナリのtimestampに利用して再現性を確保するようにした

### 変更

- SakuraScriptアニメーションの`move`パターンでベースフレームを平行移動できるようにした
- サーフェスのコンポジッティング演算に`blend-multiply`・`blend-screen`・`blend-overlay`・`blend-add`・`replace`、およびそれぞれの`-fast`変形を追加
- サーフェスウィンドウとバルーンウィンドウの非表示状態を統一し、フルスクリーン時の表示制御を改善

## [0.1.0-alpha.11] - 2026-08-25

### 追加

- SSTP互換状況の文書を追加。Socket SSTP・SSTP over HTTP・各メソッドとEXECUTE commandの対応範囲を整理
- SSTPレスポンスに任意ヘッダーと追加データを付与できるようにし、UKADOC仕様どおり空行に続けてデータを返せるようにした
- SakuraScriptにオンラインモード、ユーザー割り込み禁止モード、誘導・受動インタラクションモード、コリジョン表示モード、同期オブジェクトの命令を追加
- SakuraScriptでキャラクターを絶対座標へ移動する`setPosition`と`resetPosition`を追加
- SakuraScriptの再生をキューイングする`enqueue`メソッドを追加し、`Option: nobreak`で実行中の再生完了後へ続けられるようにした
- surfaces.txtのdescriptブロックで`maxwidth`・`collision-sort`・`animation-sort`を読み取るようにした
- surfaces.txtのサーフェス定義で`name`・`balloonoffset`・`point`・`icon`などのフィールドを読み取るようにした
- NARのinstall.txtで`type,package`を扱い、パッケージ内の複数コンテンツをまとめてインストールできるようにした
- NARのinstall.txtで`accept`フィールドを読み取り、指定外のゴーストへのインストールを拒否するようにした
- NARを圧縮する際に`.narignore`・`.narinclude`と`developer_options.txt`の`nonar`オプションを反映してファイルを除外するようにした
- `descript.txt`を参照してゴースト・シェル・バルーンのREADMEファイルを解決する`ReadmeResolver`を追加
- 同梱ゴースト「りあ」にスリープ・復帰イベントへの応答と、脚のダブルクリック時の着せ替え会話の条件を修正

### 変更

- SakuraScriptのバルーン位置計算にサーフェスの`balloonoffset`を反映するようにした
- SSTPのバージョン検証を強化し、`Charset`ヘッダーの有無も確認するようにした
- 未知のSSTPメソッドに501を返すようにした

## [0.1.0-alpha.10] - 2026-08-24

### 追加

- SHIORIイベントの発行範囲を拡充。時刻、スリープ、表示状態、画面構成、システム負荷、キーボード、ゲームパッド、マウス、ドラッグ＆ドロップ、サーフェス変更、サウンド再生などをゴーストへ通知できるようにした
- SakuraScriptから使える入力ボックス、教示ボックス、コミュニケートボックスと、ゴースト・シェル・バルーン選択ダイアログを追加
- バルーンの`descript.txt`にあるフォント名、太字、斜体、下線、打ち消し線、縁取り、影の設定を表示へ反映
- ネットワーク更新の`updates2.dau`でsize、date、charsetの拡張フィールドを扱い、ダウンロードサイズも検証するようにした
- ネットワーク更新後に`delete.txt`で指定されたファイルを安全に削除できるようにした
- UKADOCに対するSHIORIイベントとテキストファイルの互換状況を文書化
- 同梱ゴースト「りあ」に眼鏡の着せ替えと対応する会話を追加

### 変更

- 同時に複数表示されていた入力・選択ダイアログを、要求を順番に処理する単一のウインドウへ整理
- 更新定義の生成形式をCRLFへ揃え、size、更新日時、charsetを出力するようにした
- SakuraScript互換状況の文書名を、他のUKADOC互換表と区別できる名前へ変更

## [0.1.0-alpha.9] - 2026-08-23

### 追加

- KAWARIを使うゴーストをネイティブ実行する経路を追加
- アプリと設定画面の日本語・英語ローカライズ用リソースを追加
- 同梱ゴースト「りあ」の日常、趣味、技術系の会話とシステムイベントへの応答を追加

### 修正

- KAWARIの辞書読み込み、リクエスト処理、文字コード処理の互換性を改善
- ランダムトークの発生条件を修正
- リリース時のVirusTotal結果の取り扱いを修正

## [0.1.0-alpha.8] - 2026-08-23

### 追加

- OpenAI、Anthropic、Gemini、OpenAI互換APIを選択できる実験的なAI人格機能を追加
- AI人格用の設定、APIキーのKeychain保存、同梱実験ゴーストからの利用経路を追加
- Materiaの「さくら」で使われるFIRSTを解析し、対応範囲をWineなしで実行するネイティブ経路を追加
- アプリ内でログやSHIORI通信を確認できるデバッグウインドウを追加

### 修正

- コンテンツ更新定義とデバッグウインドウの動作を修正

## [0.1.0-alpha.7] - 2026-08-22

### 追加

- ゴーストからUtataneとmacOSの状態を参照できるProperty Systemを追加
- SakuraScriptによるアーカイブ操作、更新定義生成、ウインドウ位置や表示状態の操作を拡充
- WebSocket経由のSakuraScript・SHIORI連携を拡充

### 修正

- バルーン内のマーカー位置を修正
- NARのインストール、SAORI呼び出し、SakuraScriptのアクション処理を改善

## [0.1.0-alpha.6] - 2026-08-22

### 追加

- SakuraScriptの対応命令を大幅に拡充。ウインドウ、バルーン、文字表示、選択肢、サーフェス、音声、外部通信などの命令を追加
- WebSocketセッションとネットワーク診断の基盤を追加
- `surfacetable.txt`の読み込みに対応
- UKADOCに基づくSakuraScript互換状況の文書を追加

### 修正

- SakuraScriptの`source.length`、パーサー、ウインドウ配置、シェル定義の処理を修正

## [0.1.0-alpha.5] - 2026-08-21

### 追加

- ゴーストとバルーンを配布元から更新するためのコンテンツマニフェスト生成・配信経路を追加
- シェルの着せ替え定義とbind操作への対応を拡充
- 同梱ゴースト「りあ」に冬服用の追加サーフェスと会話を追加

### 変更

- 同梱コンテンツの初回配置と更新URLの扱いを改善し、利用者が変更した内容を上書きしにくい構成へ変更

## [0.1.0-alpha.4] - 2026-08-21

### 追加

- SakuraScriptのバルーン制御、文字装飾、選択肢、サーフェス操作、待機、音声再生などに対応
- バルーンの定義読み込みとテキスト表示を拡充

### 変更

- 同梱ゴーストの会話とマウス操作を、新しいSakuraScript対応へ合わせて更新

## [0.1.0-alpha.3] - 2026-08-21

### 追加

- 同梱ゴースト「りあ」と専用バルーンを追加し、初回起動から利用できるようにした
- ゴーストと単体バルーンの手動・自動ネットワーク更新に対応
- SparkleによるUtatane本体の更新と、タグから配布物を作るリリース処理を追加
- 現在地の天気を取得し、ゴーストへ渡す機能を追加
- PNGの透過・合成処理と`overlay-fast`の互換性を改善

### 修正

- 同梱YAYAの状態ファイルが上書きされる問題を修正

## [0.1.0-alpha.2] - 2026-08-20

### 追加

- KAWARIと、外部ビルドしたAosoraモジュールの読み込みに対応
- `config.txt`形式のHEADLINE/2.0センサーをネイティブ実行し、Windows DLLをWine経由で呼ぶ実験的な経路を追加
- MateriaのFIRSTを専用ホストとWine経由で動かす開発用経路を追加
- エラー表示、進行状況ウインドウ、外観・表示倍率・起動方法などの設定を拡充
- Native SHIORIと互換状況の開発文書を追加

### 修正

- 読み込めないゴーストがあっても、ほかのゴーストを起動できるようにした
- Aosora、ネットワーク更新、SSTP、バルーン配置などの互換性を改善

## [0.1.0-alpha.1] - 2026-08-19

### 追加

- macOS上でゴースト、シェル、バルーンを表示・操作するUtataneの最初の公開版
- NARのインストール、展開済みSSPフォルダからの取り込み、複数ゴーストの起動に対応
- YAYAとSATORIを使うゴーストのネイティブ実行に対応
- SSTP over HTTP、RSS / Atom、ネットワーク更新の基礎機能を追加
- シェル・バルーンの倍率、ウインドウ位置、画面端補正などの設定を追加
- 起動中のゴーストを操作するstdio形式のMCPサーバーを同梱

[0.1.4]: https://github.com/opera7133/Utatane/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/opera7133/Utatane/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/opera7133/Utatane/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/opera7133/Utatane/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.15...v0.1.0
[0.1.0-alpha.15]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.14...v0.1.0-alpha.15
[0.1.0-alpha.14]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.13...v0.1.0-alpha.14
[0.1.0-alpha.13]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.12...v0.1.0-alpha.13
[0.1.0-alpha.12]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.11...v0.1.0-alpha.12
[0.1.0-alpha.11]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.10...v0.1.0-alpha.11
[0.1.0-alpha.10]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.9...v0.1.0-alpha.10
[0.1.0-alpha.9]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.8...v0.1.0-alpha.9
[0.1.0-alpha.8]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.7...v0.1.0-alpha.8
[0.1.0-alpha.7]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.6...v0.1.0-alpha.7
[0.1.0-alpha.6]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.5...v0.1.0-alpha.6
[0.1.0-alpha.5]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.4...v0.1.0-alpha.5
[0.1.0-alpha.4]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.3...v0.1.0-alpha.4
[0.1.0-alpha.3]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.2...v0.1.0-alpha.3
[0.1.0-alpha.2]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.1...v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/opera7133/Utatane/releases/tag/v0.1.0-alpha.1
