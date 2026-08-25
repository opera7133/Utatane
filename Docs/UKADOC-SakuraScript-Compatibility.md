# UKADOC compatibility matrix

Utatane の実装状況を [UKADOC](https://ssp.shillest.net/ukadoc/manual/) と比較するための内部資料。
2026-08-21 時点のソースコードを基準とし、実機で未確認の項目は「対応」にしない。

## 判定

| 記号 | 意味 |
| --- | --- |
| ✅ | 主要な構文を解析し、実行結果まで確認できる |
| 🟡 | 一部の構文・引数・描画だけ対応 |
| ❌ | 未実装。現在は `unknown` として無視されるか、文字列として扱われる |
| ➖ | macOS では意味が薄い、危険、または別機能として設計判断が必要 |

「パーサーが受理する」だけでは対応扱いにしない。Parser、Player、通常ゴースト、呼び出しゴーストなど必要な経路まで接続されていることを確認する。
macOSで成立しない機能、SSP固有の管理・開発UI、危険性に対して妥当な代替を作れない機能を除き、最終的にはすべて「✅」または意図を明記した「➖」にする。

## SakuraScript

基準: [さくらスクリプトリスト](https://ssp.shillest.net/ukadoc/manual/list_sakura_script.html)

### 基本仕様

| UKADOC項目 | 状況 | Utataneの挙動・不足 |
| --- | --- | --- |
| `\\` | ✅ | `\` を文字として表示 |
| `\%` | ✅ | `%` を環境変数の開始記号として解釈せず、そのまま表示。Parserテストで確認 |
| スクリプトの寿命 | 🟡 | 再生、キャンセル、クリック待ち、終了後の自動消去は実装。SSPの全割込み規則とは未照合 |

### スコープ

| コマンド | 状況 | 備考 |
| --- | --- | --- |
| `\0`, `\h` | ✅ | scope 0 |
| `\1`, `\u` | ✅ | scope 1 |
| `\pID`, `\p[ID]` | 🟡 | 整数scopeに対応。UKADOCどおり括弧なしは1桁、複数桁は括弧形式 |

### サーフェス・アニメーション・ウィンドウ

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\sID`, `\s[ID]` | 🟡 | 数値IDに対応。UKADOCどおり括弧なしは1桁、複数桁は括弧形式 |
| `\s[識別子]` | ✅ | named surface / aliasとして解決 |
| `\i[ID]`, `\i[ID,wait]` | ✅ | 数値IDと`animation*.name`のSERIKOアニメーション開始、実完了待ちに対応 |
| `\![anim,clear/pause/resume/offset/add/stop,...]` | 🟡 | ID・名前指定の`clear`・`stop`・`pause`・`resume`・`offset`を実装。pause中はフレーム残り時間も停止。add・textは未実装 |
| `\__w[animation,ID]` | ✅ | 現scopeで同じID・名前のアニメーションTaskが完了・停止するまで待機 |
| `\![bind,...]`, `\![bind-noevent,...]` | 🟡 | カテゴリ・パーツ指定、明示ON/OFFとトグル、scope、`mustselect`・`multiple`・`addid`の描画、実行時再描画に対応。`bind`は`OnDressupChanged`と`OnNotifyDressupInfo`を通知。着せ替えメニューUIと選択状態の永続化は未実装 |
| `\![lock/unlock,repaint]` | ✅ | アニメーション進行を止めず描画だけ保留し、unlock時に最新フレームを反映。通常lockはスクリプト終端で自動解除、manualは維持 |
| `\![set,alignmentondesktop/alignmenttodesktop,...]` | ✅ | scope別の`top`・`bottom`・`left`・`right`・`free`・`default`に対応。端への吸着と吸着軸のドラッグ固定をゴースト終了まで保持 |
| `\![set,scaling,...]` | ✅ | ユーザー設定倍率を基準にscope別の単一・縦横倍率、負数による軸反転、`--time`・旧位置引数によるアニメーション、`--wait`に対応 |
| `\![set,alpha,...]` | ✅ | scope別の0〜100指定、上限クランプ、負値で値を維持した再描画、`--time`・旧位置引数によるアニメーション、`--wait`に対応 |
| `\4`, `\5` | ✅ | `\4`（他キャラから離れる方向への一定移動）と `\5`（他キャラとの隣接位置への接近移動）に対応 |
| `\![move]`, `\![moveasync]` | ✅ | 指定座標・アニメーション時間（ミリ秒）によるウィンドウ移動に対応（同期・非同期移動） |
| `\![set/reset,position...]` | ✅ | `set,position,x,y,scope`で指定scopeをスクリーン座標へ移動してドラッグ固定し、`reset,position`で全scopeの固定を解除 |
| `\![set/reset,zorder...]` | ✅ | `\![set,zorder,スコープ...]` によるサーフェス・バルーンウィンドウの重なり順序（Z-Order）指定と、`\![reset,zorder]` による解除に対応 |
| `\![set/reset,sticky-window...]` | ✅ | `\![set,sticky-window,スコープ...]` による複数キャラクターウィンドウの連動ドラッグ移動と、`\![reset,sticky-window]` による解除に対応 |
| `\![execute,resetwindowpos]` | ✅ | 保存済みの全scopeのサーフェス・バルーン位置を消去し、表示中ウィンドウを初期配置へ戻す |

### バルーンとテキスト

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\bID`, `\b[ID]` | ✅ | scope別のバルーンsurface変更に対応。括弧なしは1桁、複数桁は括弧形式。`\b[-1]` によるバルーン非表示に対応 |
| `\_b[ファイル,...]` 全形式 | 🟡 | `\_b[画像パス,inline]` および `\_b[画像パス,inline,opaque]` によるバルーン内インライン画像描画（相対パスおよび `data:image/...;base64,...` 画像）に対応。座標指定（x,y）描画は未実装 |
| `\n` | ✅ | 改行 |
| `\n[half]`, `\n[百分率]` | ✅ | `half`と数値・`%`付き百分率を改行文字の行高へ反映 |
| `\_n` | ✅ | 次の`\_n`まで現scopeの自動折返しを停止し、スクリプト終了時に復帰 |
| `\c` | ✅ | 現scopeの本文とリンクを消去 |
| `\c[char/line,...]` | ✅ | カーソル直前または0始まり開始位置から文字数・行数を消去。後続のリンク・文字装飾範囲も補正 |
| `\_l[x,y]` | ❌ | 描画位置変更 |
| `\C` | ✅ | 全scopeの本文・リンクを消去し、Playerテストで確認 |
| `\![set,autoscroll,...]` | ✅ | `disable` / `enable` をスコープ単位で反映 |
| `\![set,balloonoffset/balloonalign/balloonmarker/balloonnum,...]` | 🟡 | scope別のoffset（絶対・`@`相対構文）、left/center(top)/right/bottom/none配置、下部marker、受信数表示を実装。offset・marker・numはスクリプト終了時に解除、alignはゴースト終了まで保持。シェル・surfaces.txt固有offsetとの合成は未対応 |
| `\![set,balloontimeout,...]` | ✅ | 表示完了後のバルーン消去時間を指定。0以下で無効、選択肢タイムアウトとの競合は早い方を採用 |
| `\![set,balloonwait,...]` | ✅ | 倍率・百分率・`ms` 絶対値に対応し、スクリプト終了時に復帰 |
| `\![set,serikotalk,true/false]` | ✅ | 文字表示中に現在surfaceのSERIKO `talk` intervalを駆動。明示アニメーションとは競合させず、スクリプトごとにtrueへリセット |
| `\![*]` | ✅ | scope別の `marker*.png` をインライン表示 |
| online / nouserbreak mode | 🟡 | `enter` / `leave`を解析。onlineは現scopeのバルーンを強制表示して簡易オンライン印を表示し、nouserbreakは区間中の別スクリプトによる割込みを拒否。SSPの専用マーカー画像とOwned SSTP判定は未対応 |
| balloon repaint / move lock | ✅ | `balloonrepaint`は描画を保留してunlock時に最新内容を反映。通常lockは終端解除、manualは維持。`balloonmove`は明示解除までドラッグを抑止 |
| `\_!`, `\_?` | ✅ | 区間内のタグ・環境変数を解釈せずそのまま表示。閉じタグがない場合は末尾までを対象にしParserテストで確認 |
| `\__v` | ❌ | 音声合成・バックログ制御は未実装 |
| `\![execute,resetballoonpos]` | ✅ | 保存済みの全scopeのバルーン位置を消去し、表示中バルーンをサーフェス近傍へ戻す |

### 文字装飾

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\f[align/valign,...]` | ✅ | `align`のleft・center・rightは同じ行の既存文字にも反映し、明示改行でleftへ復帰。`valign`のtop・center・bottomは改行をまたいでscope別に維持 |
| `\f[name,フォント名]` | ✅ | 複数候補を優先順に選択し、ゴーストmaster／バルーン内のフォントファイルをプロセス登録。`default`への復帰にも対応 |
| `\f[height,数値]` | ✅ | 絶対値、相対値、百分率、`default`、CSS風の7段階サイズ名と`smaller`・`larger`に対応 |
| `\f[color,色指定]` | 🟡 | RGB、百分率RGB、`#RRGGBB`、主要な色名、`default` に対応。全色名は未照合 |
| shadow color/style、outline | ✅ | `shadowcolor`の色指定・`none`・`default`、`shadowstyle`の`offset`・`outline`、`outline`の真偽・`default`を文字範囲別に描画 |
| anchor font color | ✅ | `\f[anchor.font.color,...]`のRGB・百分率・16進・主要色名・defaultを以後のアンカー範囲へ反映 |
| bold / italic / strike / underline | ✅ | 有効・無効・defaultと、文字範囲別の描画に対応 |
| sub / sup | ✅ | true・false・1・0・default・disableに対応し、文字範囲別の描画をPlayerテストで確認 |
| `\f[default]`, `\f[disable]` | ✅ | 現scopeで以後に表示する文字属性を初期化 |

### ウェイト

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\w1`〜`\w9` | ✅ | 50ms単位 |
| `\_w[時間]` | ✅ | ミリ秒待ち |
| `\__w[時間]` | ✅ | 再生開始／クリック待ち／clearからの累計ミリ秒まで待機し、Parser・Player経路で確認 |
| `\x`, `\x[noclear]` | ✅ | クリック待ちと消去有無 |
| `\t` | ✅ | 実行後からスクリプト終了・キャンセルまで、通常・呼び出しゴーストのサーフェスマウスイベントをSHIORIへ通知しない。Player状態と配送経路をテスト |
| `\_q`, quicksection | ✅ | トグル形式と明示的なtrue/false・1/0に対応。文字ウェイトだけを省略し、明示ウェイトは実行 |
| `\_s`, `\_s[ID...]` | ✅ | 無引数はscope 0・1、ID指定は列挙scopeへ、区間内の文字と改行を同時表示。scope別の文字装飾も保持しPlayerテストで確認 |
| syncobject の wait / set / reset | 🟡 | Utatane内の通常・呼び出しゴースト間で共有する名前付きシグナルとしてset・reset・waitとtimeoutを実装。WindowsのMutex・Semaphore種別判定と`--reset`は未対応 |

### 選択肢・アンカー

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\q[タイトル,ID]` | ✅ | クリック可能 |
| `\q[タイトル,OnID,r0...]` | ✅ | 追加引数を渡す |
| `\q[タイトル,ID1,ID2...]` | 🟡 | 2番目をID、以降を引数として扱う。旧形式固有の意味とは未照合 |
| `script:` 選択肢 | ✅ | 通常・範囲選択肢でクリック時に指定SakuraScriptを直接再生し、SHIORI選択イベントを発生させないことをPlayerテストで確認 |
| `\q[ID][タイトル]`, `\q*[ID][タイトル]` | ✅ | 旧仕様の選択肢（`\q*[...]` はマーカー付き）を受理し、自動改行付きで標準選択肢へ正規化 |
| `\__q[ID,...]...\__q` | ✅ | 範囲選択肢、引数、終了時の自動改行に対応 |
| `\z` | ✅ | 旧仕様の選択肢付きスクリプト終端として `\e` と同じ再生終了処理へ接続。Parser・Playerの終了経路で確認 |
| `\*`, `\![set,choicetimeout,時間]` | ✅ | 表示完了後から計時。省略時は設定値、0・-1・`\*`は無期限。期限時にバルーンを閉じ、通常・呼び出しゴーストへ`OnChoiceTimeout`を通知 |
| `\_a[ID]...\_a` | ✅ | アンカー範囲と引数に対応 |
| cursor / anchor style・各色 | 🟡 | バルーン `descript.txt` の通常・hover設定を反映。SakuraScriptの `\f[...]` 変更は未実装 |
| cursor / anchor method | ❌ | ROP / blend method未実装 |
| anchor visited style・各色・method | ❌ | 訪問済み状態を保持していない |

### イベント・本体操作

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\e` | ✅ | 再生終了 |
| `\-` | ✅ | ゴーストの終了処理を実行（呼び出しゴーストはdismiss、メインゴーストはアプリ終了）。Player・App経路で確認 |
| `\a` | ✅ | `OnAITalk` イベントを発生 |
| update / updatebymyself / updateother | 🟡 | `updatebymyself`、`update,ghost`、`update,balloon`を既存更新機能へ接続。platform・updateother・全オプションは未対応 |
| `\6`, `\7`, SNTP, biff, vanish | ❌ | 未実装 |
| `\![execute,headline,...]` | ✅ | 名前またはディレクトリ名で既存RSS／HEADLINEセンサーを実行 |
| `\+`, `\_+`, change/call ghost | 🟡 | ランダム／順次切替と、名前・ディレクトリ名・`random`・`sequential`指定を接続。lastinstalledとraise-eventオプションは未対応 |
| change shell / balloon | ✅ | 名前またはディレクトリ名で通常／呼び出しゴーストの既存切替処理へ接続 |
| `\v`, `\![set,windowstate,stayontop/!stayontop]` | ✅ | 最前面表示（`.floating` / `.normal`）のトグルと明示指定に対応。サーフェス・バルーン両方に反映しテストで確認 |
| windowstate (その他) / wallpaper / tray | ➖ | macOSでの代替仕様を決める必要あり |
| otherghosttalk / othersurfacechange | 🟡 | 呼び出し中ゴースト間の独自連携は実装。UKADOCの `\![set,otherghosttalk,...]` / `\![set,othersurfacechange,...]` による通知制御は未実装 |
| `\![raise,...]` | ✅ | SHIORIイベントを発生させ、元スクリプトの残りを破棄して応答スクリプトへ切り替える |
| `\![embed,...]` | ✅ | SHIORIイベントの戻り値を現在の再生列へ埋め込む |
| timerraise / raiseother / timerraiseother | 🟡 | `timerraise`、`raiseother`、`timerraiseother`に対応。他ゴーストは名前指定と全ゴースト指定が可能。プラグイン宛は未対応 |
| notify / timernotify / timernotifyother | 🟡 | 自ゴーストへの`notify`・`timernotify`と`notifyother`・`timernotifyother`に対応し、SHIORI応答は表示しない。プラグイン宛は未対応 |

### サウンド

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\8[file]`, `\_v[file]`, `\_V`, `\![sound,...]` | ✅ | `\8` / `\_v`（非同期音声再生）、`\_V`（音声再生完了待ち）、`\![sound,...]`（play/load/loop/wait/pause/resume/stop/option）に対応。volume、balance、rate、seektimeに対応。`ghost/master` 内のAVFoundation対応音声のみ。CD・動画ウィンドウは対象外 |

### 外部UI・入力

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\j[ID]`, `\![open,browser,...]` | 🟡 | メイン／呼び出しゴーストともHTTP・HTTPSを既定ブラウザで開く。`file:`・`mailto:`は未対応 |
| mailer / addressbar / editor / explorer | ➖ | macOSでの代替と安全境界が必要 |
| teachbox / communicatebox | ✅ | `\![open,communicatebox,初期値]` / `\![open,teachbox,初期値]` に対応し、入力値を `OnCommunicate` / `OnTeach` イベントとして SHIORI へ通知 |
| `\![open,inputbox,...]` | 🟡 | ID、timeout、初期値を解析し、入力値を指定されたIDのSHIORIイベントへ `Reference0` として返す。timeoutの実動作と全オプションは未対応 |
| password/date/slider/time/ip input | 🟡 | inputbox互換の入力プロンプトとして受付 |
| `\![close,inputbox,...]` | ✅ | `\![close,inputbox,ID]` の構文解析とハンドラ接続に対応 |
| configuration / 各explorer / graph / calendar | 🟡 | `\![open,configurationdialog]` でUtataneの設定画面オープンに対応。各explorer等は未実装 |
| help / messenger / readme / terms / file | 🟡 | `\![open,readme]`、`\![open,help]`、`\![open,file,パス]`、`\![open,folder,パス]` に対応。該当ドキュメントやファイルを外部アプリ／Finderで開く |
| open/save/folder/color dialog、close dialog | 🟡 | `open` / `save` / `folder` / `color` とID指定・全ダイアログのcloseに対応。title、dir、filter、ext、name、color、idを受け取り、結果を `OnSystemDialog` / `OnSystemDialogCancel` または指定イベントへ通知。filterは拡張子ワイルドカードのみ、実UIは未確認 |
| surfacetest / aigraph / developer / shiorirequest / errorlog | ❌ | 開発UI未実装 |
| dressup / picture / archive / backlog viewer | ❌ | 未実装 |

### Property System

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\![set,property,...]` | 🟡 | 構文・書込可否検証・Property Systemへの書き込み経路を実装。個別のUI／サウンド状態setterは未実装 |
| `\![get,property,...]` | 🟡 | 複数プロパティを解決して指定イベントのReference0以降へ通知。日時・OS・CPU・メモリ・カーソル・モニター・テーマ、baseware、currentghost、ghostlist、shelllistの基本値に対応 |
| `%property[...]` | 🟡 | Property Systemの値を再生中に展開。日時・OS・CPU・メモリ・カーソル・モニター・テーマ、baseware、currentghost、ghostlist、shelllistの基本値に対応 |

### HTTP、WebSocket、アーカイブなど

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\![execute,http-get,URL,...]` | 🟡 | async/syncのID、param、主要header、timeout、no-cache、file/nofileを実装。fileはghost/master/varへ保存し、nofileは文字コード指定・128KB制限・改行変換を行って `Reference3` へ返す。非同期並行実行、multipart、streaming、progressは未対応 |
| http-post/head/put/delete/patch/options | 🟡 | 全メソッドを共通HTTP実行基盤へ接続。URL encoded bodyと主要共通オプションに対応。multipart、入力ファイル、証明書検証無効化は未対応 |
| `\![execute,rss-get/rss-post,URL,...]` | 🟡 | RSS/Atomの取得・基本パースと完了/失敗通知に対応。日時形式・全オプション・SSL情報は未照合 |
| websocket execute/send/close/cancel | 🟡 | URL単位のws/wss接続、HTTP 101確立後のOpen通知、header・subprotocol、テキスト/バイナリ送受信、close/cancelを実装。自動再接続とSSLInfoは未対応 |
| `\![cancel,http/http-get,...]` | ✅ | `\![cancel,http,URL]` / `\![cancel,http-get,URL]` で特定URLまたは全実行中HTTPリクエストをキャンセル |
| `\![execute,extractarchive/compressarchive,...]` | 🟡 | ghost/master配下に限定してZIP展開・圧縮を実行し、結果またはエラーコードをイベント通知。パストラバーサル・シンボリックリンクを拒否。SSP管理下の他フォルダと暗号化方式の完全互換は未対応 |
| dumpsurface | 🟡 | 表示中サーフェスのPNG出力と完了通知に対応。scope・surface列挙・prefix・cropなどUKADOCの全引数は未実装 |
| `\![execute,install,path/url,...]` | ✅ | ローカルファイルパスまたはURL指定のNARインストールコマンドを接続 |
| ping / nslookup | 🟡 | macOSのping・DNSキャッシュ照会へ接続。host/eventとpingのcount/size/timeout/ttl、完了・失敗イベントに対応。ping progress、df/dataは未対応 |
| createnar / createupdatedata | 🟡 | `createupdatedata` は引数なしで実行元ゴーストの `updates2.dau` を生成（明示パス拡張も対応）。`createnar` は明示パス拡張のみで、UKADOCの引数なし形式は未実装 |
| emptyrecyclebin / create shortcut | ➖ | OS依存かつ危険。原則対象外候補 |
| passive / induction / select / collision mode | 🟡 | passive／inductionはenter・leaveと`cantalk=false`を実装し、passive中は選択肢・バルーンの時間切れも停止。collisionは矩形・多角形の領域を名前つきまたは`rect`指定で枠のみ表示。メニュー・DnD・更新・最小化・終了等の全制限とselect modeは未実装 |
| reload surface/descript/shiori/makoto/shell/balloon/ghost/aigraph | 🟡 | ghost・shell・balloonに加え、旧`reloadsurface`、surface、shiori、descriptの全体指定とghost／shell／balloon対象指定を実装。shioriとghost descriptは人格全体の再起動で代替。makoto・headline・plugin・aigraphは未対応 |
| unload/load shiori・makoto、shioridebugmode | ❌ | 未実装 |
| `\_u`, `\_m` | ✅ | 16進・10進のUCS-2／ASCIIコードを文字へ変換。範囲外とサロゲートは拒否しParserテストで確認 |
| `\&[ID]` | ✅ | amp・apos・gt・lt・nbsp・quotに加え、yen・cent・pound・euro・copy・reg・trade・deg・plusmn・sup1-3・frac・times・divide・half_solidus・bull・hellip・矢印等の主要HTML/XML実体参照に対応 |
| `\m` | ➖ | SSTPのWindowsウィンドウメッセージ送信に依存するためmacOSでは対象外候補 |
| `\![execute,weather-get,...]` | 🟡 | Utatane拡張。`--async=イベントID` のみ |

### 環境変数

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `%month/day/hour/minute/second` | ✅ | 描画時のローカル日時へ置換 |
| `%username`, `%selfname`, `%selfname2`, `%keroname` | 🟡 | macOSユーザー名とゴーストのキャラクター名へ置換。`selfname2`専用キー未保持のため本体名へフォールバック |
| `%screenwidth`, `%screenheight` | ✅ | 現在のメインスクリーンのポイント単位サイズへ置換 |
| `%exh`, `%et`, `%wronghour` | ✅ | `%exh`をOS連続起動秒、`%et`を間違った連続起動時間文字列、`%wronghour`を正しくない現在時へ置換 |
| `%ms/%mz/%ml/%mc/%mh/%mt/%me/%mp/%m?` | 🟡 | UKADOCの各ランダム単語カテゴリをUtatane内蔵語彙で置換。SSPの語彙集合とは異なる |
| `%dms`, `%lastghostname`, `%lastobjectname` | ✅ | `%dms`はUtatane内蔵の「～に～する～」相当語彙で置換。`%lastghostname` / `%lastobjectname` はNARインストール完了時に直近のインストール対象名で環境変数を更新 |
| `%*` | ✅ | `\![*]` と同じバルーンマーカーを表示 |

## SakuraScript以外のUKADOC領域

これは個々のキーやイベントを網羅する表ではなく、次に詳細対応表を作るべき領域の棚卸し。各領域を実装する時に別表へ展開する。

| UKADOC領域 | 状況 | 現在の範囲・主な不足 |
| --- | --- | --- |
| SHIORI Event（外部） | 🟡 | SSTPや一部コールバック。全イベント未網羅 |
| SHIORI Resource | ❌ | 完全なresource照会表なし |
| SHIORI/3.0 | 🟡 | GET/NOTIFY、Reference、Charset、Valueなど基本モデルあり。全ヘッダー・ステータス未照合 |
| SSTP/1.x | ✅ | localhost Socket／HTTPのportable coreを実装。SEND、NOTIFY、COMMUNICATE、EXECUTE、GIVE、ゴースト指定、IfGhost、nobreak、情報取得・Cookie・Property・Archive系commandに対応。詳細は[UKADOC-SSTP-Compatibility.md](UKADOC-SSTP-Compatibility.md) |
| SAORI/1.0 | 🟡 | SSU等の限定ネイティブ互換。任意SAORI、Windows DLL汎用実行は対象外 |
| HEADLINE/2.0 | 🟡 | native `config.txt` とWine DLL fallback。全応答差異は未照合 |
| DLL規格 | 🟡 | SHIORIはnative実装と限定Wine経路。一般Windows DLLは対象外 |
| FMO / MUTEX | ❌ | Windows固有FMOは対象外。macOS向け互換公開方式も未設計 |
| Web関連 | 🟡 | homeurl更新、RSS/Atom、SSTP over HTTP中心。全仕様未照合 |
| Property System | 🟡 | 大文字小文字を無視する値解決、組み込みsystem/baseware値、動的な値登録、書込可否管理をコアに実装。SakuraScript・ゴースト一覧・UI状態との接続は未完 |

## 優先順位案

1. 実在ゴーストで利用頻度が高いsoundオプションと、残る表示・入力系コマンド。
2. 既存Utatane機能へ接続する update、change ghost/shell/balloon、headline、install。
3. `surfaces.txt`、Balloon/Ghost/Shell `descript.txt`、SHIORI Eventの詳細対応表。
4. HTTPの高度なオプション、timerraise、Property Systemなど高度な互換機能。
5. Windows・SSP固有UIに依存する項目は、macOS向け代替仕様を決めてから実装可否を判定する。

## 更新ルール

- 実装PRでは該当行を同時に更新する。
- 「✅」へ変更する時はテストまたは実機確認の根拠を書く。
- UKADOCの項目追加を定期的に確認し、確認日を冒頭で更新する。
- SSPとの差異を意図的に残す場合は「未対応」ではなく理由付きの「対象外候補」とする。
