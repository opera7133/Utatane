# UKADOC SakuraScript互換状況

SakuraScriptの命令について、Utataneで使える範囲とSSPとの差をまとめた対応表です。[UKADOC](https://ssp.shillest.net/ukadoc/manual/)の項目を基準にしています。

この表は2026-09-21時点のソースコードを基にしています。各節の調査日と備考で、確認した範囲を確認してください。実機で未確認の項目は「対応」に含めません。

現行UKADOCには、構文違いを個別に数えて359件のSakuraScript項目があります。この表では同じ実装経路を使う構文をまとめ、147行に分類しています。集計と行数はCIで検査します。

## 判定

| 記号 | 意味 |
| --- | --- |
| ✅ | 主要な構文を解析し、実行結果まで確認できます |
| 🟡 | 一部の構文・引数・描画だけ対応 |
| ❌ | 未実装。現在は `unknown` として無視されるか、文字列として扱われます |
| ➖ | macOS では意味が薄い、危険、または別機能として設計判断が必要 |

命令を読み取れるだけでは「対応」にしません。読み取りから再生までつながり、メインゴーストと呼び出したゴーストなど、必要な場面で動くことを確認します。

対応を進める際は、各項目を「✅」または理由付きの「➖」にすることを目指します。macOSで実現できない機能やSSP固有の画面、安全な代替方法を用意できない機能は、理由を明記します。

## SakuraScript

基準: [さくらスクリプトリスト](https://ssp.shillest.net/ukadoc/manual/list_sakura_script.html)

調査日: 2026-09-21
UKADOC掲載構文数: 359
UKADOC分類行数: 147
調査結果: ✅ 117 / 🟡 21 / ❌ 0 / ➖ 9

### 基本仕様

| UKADOC項目 | 状況 | Utataneの挙動・不足 |
| --- | --- | --- |
| `\\` | ✅ | `\` を文字として表示 |
| `\%` | ✅ | `%` を環境変数の開始記号として解釈せず、そのまま表示。Parserテストで確認 |
| スクリプトの寿命 | ✅ | 再生、通常割込み、選択肢応答からの一時割込みと再開、クリック待ち、キャンセル、終了後の自動消去、time critical／nouserbreakによる割込み抑止を実装してPlayerテストで確認 |

### スコープ

| コマンド | 状況 | 備考 |
| --- | --- | --- |
| `\0`, `\h` | ✅ | scope 0 |
| `\1`, `\u` | ✅ | scope 1 |
| `\pID`, `\p[ID]` | ✅ | 整数scopeに対応。UKADOCどおり括弧なしは1桁、複数桁は括弧形式。Parserテストで確認 |

### サーフェス・アニメーション・ウィンドウ

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\sID`, `\s[ID]` | ✅ | 数値IDに対応。UKADOCどおり括弧なしは1桁、複数桁は括弧形式。Parserテストで確認 |
| `\s[識別子]` | ✅ | sakura／kero／charのsurface aliasと、`surfaces.txt`の各surfaceに書く`name`を解決。候補が複数あるalias／nameはその中から選択 |
| `\i[ID]`, `\i[ID,wait]` | ✅ | 数値IDと`animation*.name`のSERIKOアニメーション開始、実完了待ちに対応 |
| `\![anim,clear/pause/resume/offset/add/stop,...]` | ✅ | ID・名前指定の`clear`・`stop`・`pause`・`resume`・`offset`を実装。pause中はフレーム残り時間も停止。`add`のoverlay／overlayfast／base／move、複数フレームとrunonce／always、サーフェス上のtext描画にも対応 |
| `\__w[animation,ID]` | ✅ | 現scopeで同じID・名前のアニメーションTaskが完了・停止するまで待機 |
| `\![bind,...]`, `\![bind-noevent,...]` | ✅ | カテゴリ・パーツ指定、明示ON/OFFとトグル、scope、`mustselect`・`multiple`・`addid`の描画、実行時再描画に対応。`bind`は`OnDressupChanged`と`OnNotifyDressupInfo`を通知。右クリックの着せ替えメニューと、ゴースト・シェル別の選択状態保存にも対応 |
| `\![lock/unlock,repaint]` | ✅ | アニメーション進行を止めず描画だけ保留し、unlock時に最新フレームを反映。通常lockはスクリプト終端で自動解除、manualは維持 |
| `\![set,alignmentondesktop/alignmenttodesktop,...]` | ✅ | scope別の`top`・`bottom`・`left`・`right`・`free`・`default`に対応。端への吸着と吸着軸のドラッグ固定をゴースト終了まで保持 |
| `\![set,scaling,...]` | ✅ | ユーザー設定倍率を基準にscope別の単一・縦横倍率、負数による軸反転、`--time`・旧位置引数によるアニメーション、`--wait`に対応 |
| `\![set,alpha,...]` | ✅ | scope別の0〜100指定、上限クランプ、負値で値を維持した再描画、`--time`・旧位置引数によるアニメーション、`--wait`に対応 |
| effect / effect2 / filter | ➖ | SSPのWindows用サーフェスエフェクトプラグインを呼ぶ命令。互換プラグイン実行基盤がmacOSにないため対象外 |
| `\4`, `\5` | ✅ | `\4`（他キャラから離れる方向への一定移動）と `\5`（他キャラとの隣接位置への接近移動）に対応 |
| `\![move]`, `\![moveasync]` | ✅ | 指定座標・アニメーション時間（ミリ秒）によるウィンドウ移動に対応（同期・非同期移動） |
| `\![set/reset,position...]` | ✅ | `set,position,x,y,scope`で指定scopeをスクリーン座標へ移動してドラッグ固定し、`reset,position`で全scopeの固定を解除 |
| `\![set/reset,zorder...]` | ✅ | `\![set,zorder,スコープ...]` によるサーフェス・バルーンウィンドウの重なり順序（Z-Order）指定と、`\![reset,zorder]` による解除に対応 |
| `\![set/reset,sticky-window...]` | ✅ | `\![set,sticky-window,スコープ...]` による複数キャラクターウィンドウの連動ドラッグ移動と、`\![reset,sticky-window]` による解除に対応 |
| `\![execute,resetwindowpos]` | ✅ | 保存済みの全scopeのサーフェス・バルーン位置を消去し、表示中ウィンドウを初期配置へ戻します |
| `\![vanishbymyself]` | ✅ | 現在のゴーストを安全に終了してmacOSのゴミ箱へ移動。切り替え先ゴースト名と`--option=query`による確認画面にも対応 |

### バルーンとテキスト

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\bID`, `\b[ID]` | ✅ | scope別のバルーンsurface変更に対応。括弧なしは1桁、複数桁は括弧形式。`\b[-1]` によるバルーン非表示に対応 |
| `\_b[ファイル,...]` 全形式 | 🟡 | inline／座標指定、相対パスとbase64、opaque／use_self_alpha、clipping、ピクセル・百分率・縦横比維持のscaling、反転、fixed、background／foreground、画像representation番号のsourceに対応。画像URL、プラグイン内探索、DLL／EXEリソース、PSDレイヤー名指定は未対応 |
| `\n` | ✅ | 改行 |
| `\n[half]`, `\n[百分率]` | ✅ | `half`と数値・`%`付き百分率を改行文字の行高へ反映 |
| `\_n` | ✅ | 次の`\_n`まで現scopeの自動折返しを停止し、スクリプト終了時に復帰 |
| `\c` | ✅ | 現scopeの本文とリンクを消去 |
| `\c[char/line,...]` | ✅ | カーソル直前または0始まり開始位置から文字数・行数を消去。後続のリンク・文字装飾範囲も補正 |
| `\_l[x,y]`／`\_l[x]` | ✅ | ピクセル・em・lh・%と`@`相対指定を解釈し、文字描画範囲左上を基準に配置。Xだけの旧来形、右タブとして使う同一行の左右分割、AppKit縦書きレイアウトにも同じ座標モデルを反映 |
| `\C` | ✅ | スクリプト先頭では直前の表示内容・リンク・装飾を維持してscope 0から追記。途中では全scopeを消去。Playerテストで確認 |
| `\![set,autoscroll,...]` | ✅ | `disable` / `enable` をスコープ単位で反映 |
| `\![set,balloonoffset/balloonalign/balloonmarker/balloonnum,...]` | 🟡 | scope別のoffset、配置、下部marker、受信数表示を実装。`@`付きoffsetはShell／surface固有offsetへ加算し、`@`なしは置換。利用者がドラッグした座標との加算・終端復帰規則は未対応 |
| `\![set,balloontimeout,...]` | ✅ | 表示完了後のバルーン消去時間を指定。0以下で無効、選択肢タイムアウトとの競合は早い方を採用 |
| `\![set,balloonwait,...]` | ✅ | 倍率・百分率・`ms` 絶対値に対応し、スクリプト終了時に復帰 |
| `\![set,serikotalk,true/false]` | ✅ | 文字表示中に現在surfaceのSERIKO `talk` intervalを駆動。明示アニメーションとは競合させず、スクリプトごとにtrueへリセット |
| `\![*]` | ✅ | scope別の `marker*.png` をインライン表示 |
| online / nouserbreak mode | ✅ | `enter`／`leave`を解析。onlineは現scopeのバルーンを強制表示してバルーンの`online*.png`・座標・アニメーション間隔を使用し、SSTP再生時は送信元markerを表示。nouserbreakは区間中の別スクリプトによる割込みを拒否 |
| balloon repaint / move lock | ✅ | `balloonrepaint`は描画を保留してunlock時に最新内容を反映。通常lockは終端解除、manualは維持。`balloonmove`は明示解除までドラッグを抑止 |
| `\_!`, `\_?` | ✅ | 区間内のタグ・環境変数を解釈せずそのまま表示。閉じタグがない場合は末尾までを対象にしParserテストで確認 |
| `\__v` | ✅ | `disable`で音声合成と発話履歴への記録を一時停止し、`alternate,テキスト`で読み上げと履歴へ残す代替文を指定。引数なしで通常動作へ戻ります |
| `\![execute,resetballoonpos]` | ✅ | 保存済みの全scopeのバルーン位置を消去し、表示中バルーンをサーフェス近傍へ戻します |

### 文字装飾

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\f[align/valign,...]` | ✅ | `align`のleft・center・rightは同じ行の既存文字にも反映し、明示改行でleftへ復帰。`valign`のtop・center・bottomは改行をまたいでscope別に維持 |
| `\f[name,フォント名]` | ✅ | 複数候補を優先順に選択し、ゴーストmaster／バルーン内のフォントファイルをプロセス登録。`default`への復帰にも対応 |
| `\f[height,数値]` | ✅ | 絶対値、相対値、百分率、`default`、CSS風の7段階サイズ名と`smaller`・`larger`に対応 |
| `\f[color,色指定]` | ✅ | RGB、百分率RGB、`#RGB`、`#RRGGBB`、CSS Color Level 3の全拡張色名、`default`、`disable`、`default.plain`と選択肢・アンカー各状態の既定色参照に対応。Playerテストで確認 |
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
| `\x`, `\x[noclear]` | ✅ | クリック待ちと消去有無。通常の`\x`はクリック時にバルーンを消し、`noclear`は表示を保持 |
| `\t` | ✅ | 実行後からスクリプト終了・キャンセルまで、通常・呼び出しゴーストのサーフェスマウスイベントをSHIORIへ通知しません。Player状態と配送経路をテスト |
| `\_q`, quicksection | ✅ | トグル形式と明示的なtrue/false・1/0に対応。文字ウェイトだけを省略し、明示ウェイトは実行 |
| `\_s`, `\_s[ID...]` | ✅ | 無引数はscope 0・1、ID指定は列挙scopeへ、区間内の文字と改行を同時表示。scope別の文字装飾も保持しPlayerテストで確認 |
| syncobject の wait / set / reset | ✅ | Utatane内の通常・呼び出しゴースト間で共有する名前付きシグナルとしてset・reset・waitとtimeoutを実装 |
| Windows Mutex／Semaphoreとのsyncobject連携 | ➖ | WindowsのOSオブジェクトを名前で取得し、種別に応じて`--reset`を処理する互換機能。macOSプロセスから同じオブジェクトへ接続できないため対象外 |

### 選択肢・アンカー

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\q[タイトル,ID]` | ✅ | クリック可能 |
| `\q[タイトル,OnID,r0...]` | ✅ | 追加引数を渡します |
| `\q[タイトル,ID1,ID2...]` | ✅ | CROW形式どおりID1をReference0、ID2以降をReference1以降としてOnChoiceSelectへ渡す。SSP形式では同じ値をOnChoiceSelectExのReference1以降にも渡す |
| `script:` 選択肢 | ✅ | 通常・範囲選択肢でクリック時に指定SakuraScriptを直接再生し、SHIORI選択イベントを発生させないことをPlayerテストで確認 |
| `\q[ID][タイトル]`, `\q*[ID][タイトル]` | ✅ | 旧仕様の選択肢（`\q*[...]` はマーカー付き）を受理し、自動改行付きで標準選択肢へ正規化 |
| `\__q[ID,...]...\__q` | ✅ | 範囲選択肢と引数に対応。終了時には暗黙の改行を挿入せず、空白で区切った複数リンクを同一行へ配置可能 |
| `\z` | ✅ | 旧仕様の選択肢付きスクリプト終端として `\e` と同じ再生終了処理へ接続。Parser・Playerの終了経路で確認 |
| `\*`, `\![set,choicetimeout,時間]` | ✅ | 表示完了後から計時。省略時は設定値、0・-1・`\*`は無期限。期限時にバルーンを閉じ、通常・呼び出しゴーストへ`OnChoiceTimeout`を通知 |
| `\_a[ID]...\_a` | ✅ | アンカー範囲と引数に対応 |
| cursor / anchor style・各色 | ✅ | バルーン`descript.txt`の通常・hover設定に加え、SakuraScriptのstyle、font／pen／brush色をリンクごとに反映。`default`でバルーン設定へ戻す |
| cursor / anchor method | ➖ | Win32 `SetROP2`の描画演算を直接指定する機能。AppKitへ同じ演算を移植できないため、Utataneでは通常のアルファ合成で描画 |
| anchor visited style・各色 | ✅ | 選択済みアンカーIDをゴースト実行中に保持し、バルーン設定とSakuraScriptの`\f[anchorvisited...]`によるstyle・font／pen／brush色を反映 |
| anchor visited method | ➖ | cursor／anchor methodと同じWin32 `SetROP2`指定のため、macOSでは通常のアルファ合成で描画 |

### イベント・本体操作

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\e` | ✅ | 再生終了 |
| `\-` | ✅ | ゴーストの終了処理を実行（呼び出しゴーストはdismiss、メインゴーストはアプリ終了）。Player・App経路で確認 |
| `\a` | ✅ | `OnAITalk` イベントを発生 |
| update / updatebymyself / updateother | 🟡 | ghost／shell／balloonの単体・複数対象、`updatebymyself`、`update,platform`、`updateother`のghost／shell／balloon／plugin／headline指定とcheckonly／recoveryを既存の更新基盤へ接続。SSPの残りのオプションと集約結果・言語指定は未対応 |
| `\7`, `\![executesntp]`, SNTP取得 | ✅ | HTTP Dateから時刻を取得し、OnSNTPBegin／OnSNTPCompare／失敗イベントを通知 |
| `\6`によるシステム時計の補正 | ➖ | macOSのシステム時計変更には管理者権限が必要で、安全な無権限APIがないため補正要求の受理まで対応 |
| `\![biff(,アカウント名)]` | ✅ | 本体設定のPOP3アカウントでメールを確認し、開始・成功・新着・失敗イベントを通知。パスワードはmacOS Keychainへ保存 |
| `\![execute,headline,...]` | ✅ | 名前またはディレクトリ名で既存RSS／HEADLINEセンサーを実行 |
| `\![execute,calendarplugin,...]` | ➖ | 旧来のスケジュールセンサはWindows DLL固有API（geturl／getschedule等）を使うためmacOSでは対象外。iCalendar取得と予定表への登録は別命令で対応 |
| `\+`, `\_+`, change/call ghost | ✅ | ランダム／順次切替、名前・ディレクトリ名・`random`・`sequential`・`lastinstalled`指定を接続。通常は切替イベントを抑止し、`--option=raise-event`指定時だけ通知 |
| change shell / balloon | ✅ | 名前またはディレクトリ名で通常／呼び出しゴーストの既存切替処理へ接続 |
| `\![change,calendarskin,...]` | ✅ | 名前・ID・ディレクトリ名・randomでUtataneカレンダーのスキンを切り替え |
| `\v`, `\![set,windowstate,stayontop/!stayontop]` | ✅ | 最前面表示（`.floating` / `.normal`）のトグルと明示指定に対応。サーフェス・バルーン両方に反映しテストで確認 |
| `\![set,trayballoon,...]` | ✅ | macOSのメニューバーへポップオーバーを表示し、クリック・時間切れイベントを通知 |
| `\![set,tasktrayicon,...]` | ✅ | ゴースト配下の画像とツールチップをMenuBarアイコンへ反映。`--duration`指定時は00〜99の連番画像を読み、`--runcount`回数または無限でアニメーション |
| windowstate (その他) / wallpaper | ✅ | `windowstate,minimize`と、壁紙のsave／restore／setに対応。相対画像、単色、center／stretch／fill／fit／tile系の配置をmacOSデスクトップへ反映 |
| otherghosttalk / othersurfacechange | ✅ | `\![set,otherghosttalk,true|false|before|after]`と`\![set,othersurfacechange,true|false]`で、呼び出し中ゴースト間の通知を制御 |
| `\![raise,...]` | ✅ | SHIORIイベントを発生させ、元スクリプトの残りを破棄して応答スクリプトへ切り替えます |
| `\![embed,...]` | ✅ | SHIORIイベントの戻り値を現在の再生列へ埋め込みます |
| timerraise / raiseother / timerraiseother | ✅ | `timerraise`、`raiseother`、`timerraiseother`に対応。他ゴーストは名前指定と全ゴースト指定が可能。遅延・反復・キャンセルとraise応答再生をテストで確認 |
| notify / timernotify / timernotifyother | ✅ | 自ゴーストへの`notify`・`timernotify`と`notifyother`・`timernotifyother`に対応し、SHIORI応答は表示しません。遅延・反復・キャンセルをテストで確認 |
| timerraiseplugin / timernotifyplugin | ✅ | プラグインごと・イベント名ごとの遅延、反復、0ミリ秒指定によるキャンセル、raise応答再生に対応 |

### サウンド

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\8[file]`, `\_v[file]`, `\_V`, `\![sound,...]` | 🟡 | `\8` / `\_v`（非同期音声再生）、`\_V`（音声再生完了待ち）、`\![sound,...]`（play/load/loop/wait/pause/resume/stop/option）に対応。volume、balance、rate、seektimeに対応。`ghost/master` 内のAVFoundation対応音声のみ。CD・動画ウィンドウは未対応 |

### 外部UI・入力

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\j[ID]`, `\![open,browser,...]` | ✅ | メイン／呼び出しゴーストともHTTP・HTTPSを既定ブラウザで開き、`mailto:`を標準メールアプリへ、`file:`の絶対パスまたは`ghost/master`相対パスを関連付けアプリへ渡します。危険なURL schemeとゴースト外へ抜ける相対パスは拒否 |
| mailer / addressbar / editor / explorer | ➖ | macOSでの代替と安全境界が必要 |
| teachbox / communicatebox | ✅ | `\![open,communicatebox,初期値]` / `\![open,teachbox,初期値]` に対応し、入力値を `OnCommunicate` / `OnTeach` イベントとして SHIORI へ通知 |
| `\![open,inputbox,...]` | ✅ | 旧形式と`--timeout`・`--text`・`--limit`・`--reference`・`--balloon`を解析。時間切れと手動closeを区別し、`OnUserInputCancel`が空応答なら`timeout`値の入力イベントへフォールバック。通常のInputBoxでは`noclose`による複数回入力と、`noclear`による入力値保持にも対応 |
| password/date/slider/time/ip input | ✅ | パスワード欄、DatePicker、Slider、時刻選択、IPv4入力を使い、各形式のReference値を返します。旧形式と`--text`形式をParserテストで確認 |
| `\![close,inputbox,...]` | ✅ | `\![close,inputbox,ID]` の構文解析とハンドラ接続に対応 |
| configuration / 各explorer / calendar | ✅ | configurationの画面IDをUtataneの設定ペインへ対応付け、ghost／shell／balloon／headline／plugin explorerを共通コンテンツ画面、calendarを予定表として開く |
| graph / aigraph | 🟡 | `open,aigraph`で`getaistateex`の複数グラフと従来の`getaistate`をレーダーチャート表示し、`reload,aigraph`で表示中だけ再取得します。ゴースト／バルーン利用率グラフは未実装 |
| help / messenger / readme / terms / file | ✅ | `terms`はterms.txtをダイアログ表示して同意・拒否イベントを通知。`messenger`、`readme`、`help`、`file`、`folder`も対応 |
| open/save/folder/color dialog、close dialog | ✅ | AppKit標準のopen／save／folder／colorパネルをID別に管理し、title、dir、filter、ext、name、colorを反映。結果を`OnSystemDialog`／Cancelまたは指定イベントへ通知し、個別・一括closeにも対応 |
| surfacetest / developer / shiorirequest / errorlog | ✅ | 開発用パレットのサーフェステスト、イベントID・Reference指定のSHIORI Request、エラー絞り込み済みログへ接続 |
| `\![open,backlogviewer]` | ✅ | 通常・呼び出しゴーストとも対象ゴーストの発話履歴を開きます。ウィンドウモードでは設定に応じて下部へ統合表示 |
| dressup explorer | ✅ | 現在のシェルの着せ替え一覧をmacOS向けポップアップとして開き、選択内容を実際の着せ替え状態へ反映 |
| picture viewer | ✅ | 画像選択またはゴースト内の指定画像をmacOS標準ビューアで開く |
| archive viewer | ✅ | アーカイブ選択またはゴースト内の指定書庫をmacOS標準の関連付けアプリで開く |

### Property System

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\![set,property,...]` | 🟡 | 構文・書込可否検証・Property Systemへの書き込み経路を実装。個別のUI／サウンド状態setterは未実装 |
| `\![get,property,...]` | 🟡 | 複数プロパティを指定イベントのReferenceへ通知。日時、OS／locale／timezone／uptime、CPU、メモリ、ディスク、カーソル、モニター、テーマ、baseware、currentghostのscope座標・surface・balloon、activeghostlist、ghost／shell／balloon／headline／plugin一覧に対応。UKADOC全プロパティとの照合は継続中 |
| `%property[...]` | 🟡 | `get,property`と共通の値を再生中に展開。未登録値の拡充と、変動するAppKit値の取得時更新は継続中 |

### HTTP、WebSocket、アーカイブなど

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\![execute,http-get,URL,...]` | 🟡 | async／sync、param、主要header、timeout、no-cache、file／nofile、progress-notify、streaming、TLS情報通知に対応。fileはghost/master/varへ保存し、nofileは文字コード指定・128KB制限・改行変換を行います。同一URLの並行実行とmultipartは未対応 |
| http-post/head/put/delete/patch/options | 🟡 | 全メソッドを共通HTTP実行基盤へ接続。URL encoded bodyと主要共通オプションに対応。multipart、入力ファイル、証明書検証無効化は未対応 |
| `\![execute,rss-get/rss-post,URL,...]` | 🟡 | RSS/Atomの取得・基本パース、完了／失敗、TLS情報通知に対応。全オプションは未照合 |
| `\![execute,ical-get/ical-post,URL,...]` | 🟡 | iCalendar取得・解析、完了／失敗／進捗／TLS情報通知、主要VEVENTフィールドとlimitに対応。繰り返し展開とfrom／toによる完全な絞り込みは未対応 |
| `\![execute,schedule-add/delete/get,...]` | 🟡 | Utataneの共有予定表へ登録・削除・取得し、完了／失敗を通知。主要フィールドと単純な週・月・年の繰り返しに対応し、RRULE・EXDATEの完全解釈は未対応 |
| `\![execute,filewatch,...]` / `\![cancel,filewatch,...]` | ✅ | ファイル・ディレクトリを監視し、作成・更新・削除をdebounce後に通知。ゴースト終了時に監視を解除 |
| websocket execute/send/close/cancel | 🟡 | ws/wss接続、Open、header・subprotocol、テキスト／バイナリ送受信、close／cancel、最大5回の自動再接続とTLS情報通知に対応。証明書subject／issuerは空欄 |
| `\![cancel,http/http-get/ical,...]` | ✅ | 特定URLまたは全実行中のHTTP・iCalendarリクエストをキャンセル |
| `\![execute,extractarchive/compressarchive,...]` | 🟡 | ghost/master配下に限定してZIP展開・圧縮を実行し、結果またはエラーコードをイベント通知。パストラバーサル・シンボリックリンクを拒否。SSP管理下の他フォルダと暗号化方式の完全互換は未対応 |
| dumpsurface | 🟡 | ゴースト配下へのPNG出力、scope、surface ID／範囲／除外指定、`__system_surface_all__`／`__system_surface_defined__`、prefix、イベント完了時の成功件数に対応。通常描画器が負座標を切り落とすため、ゼロ位置切り出しを無効にした時の負座標拡張は未対応 |
| `\![execute,install,path/url,...]` | ✅ | ローカルファイルパスまたはURL指定のNARインストールコマンドを接続 |
| ping / nslookup | 🟡 | macOSのping・DNSキャッシュ照会へ接続。host/eventとpingのcount/size/timeout/ttl/df/data、応答単位progress、完了・失敗イベントに対応。macOS `ping`の制約によりdataは先頭16バイトのパターンを指定サイズまで繰り返します |
| createnar / createupdatedata | 🟡 | `createupdatedata`は引数なしで実行元ゴーストの`updates2.dau`を生成（明示パス拡張も対応）。`createnar`は引数なしで保存先を選び、実行元ゴーストをNAR化する。スクリプトが任意の絶対パスへ直接書き出す動作は安全のため制限 |
| emptyrecyclebin | ✅ | ユーザーの`~/.Trash`を空にし、実行元と他ゴーストへ前後の件数・容量・成否を通知 |
| create shortcut | ➖ | Windowsショートカット固有のためmacOSでは対象外 |
| passive / induction / select / collision mode | 🟡 | passive／induction、collision表示に加え、selectrectの全画面矩形選択と開始・終了・マウス・キャンセル通知に対応。メニュー・DnD・更新・最小化・終了等の全制限は未実装 |
| reload surface/descript/shiori/makoto/shell/balloon/ghost/aigraph | 🟡 | 旧`reloadsurface`、surface、shell、balloon、ghost、shiori、makoto、表示中のaigraphを実装。`reload,descript`は全体指定とghost／shell／balloon／headline／plugin／calendar.skinの対象指定に対応する。SHIORIとMAKOTOは結合された人格エンジンを再生成する。language／calendar.pluginは未対応 |
| `\![unload/load,shiori]` | ✅ | 実行中の人格エンジンを解放し、load時にゴースト設定から再生成。unload中はイベントに応答しない |
| `\![unload/load,makoto]` | 🟡 | MAKOTO変換を外した／含めた人格エンジンへ切り替える。切り替え時にSHIORIも再生成される点はSSPと異なる |
| `\![set,shioridebugmode,true/false]` | ✅ | 開発用パレットのSHIORIリクエスト画面を表示／非表示にする。Utataneは通常時もSHIORI通信をログへ記録する |
| `\_u`, `\_m` | ✅ | 16進・10進のUCS-2／ASCIIコードを文字へ変換。範囲外とサロゲートは拒否しParserテストで確認 |
| `\&[ID]` | ✅ | amp・apos・gt・lt・nbsp・quotに加え、yen・cent・pound・euro・copy・reg・trade・deg・plusmn・sup1-3・frac・times・divide・half_solidus・bull・hellip・矢印等の主要HTML/XML実体参照に対応 |
| `\m` | ➖ | SSTPのWindowsウィンドウメッセージ送信に依存するためmacOSでは対象外候補 |
| `\![execute,weather-get,...]` | ✅ | Utatane独自拡張として`--async=イベントID`を受け、天気取得結果を指定イベントへ通知 |

### 環境変数

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `%month/day/hour/minute/second` | ✅ | 描画時のローカル日時へ置換 |
| `%username`, `%selfname`, `%selfname2`, `%keroname` | ✅ | macOSユーザー名と、ゴーストまたは現在のシェルの`descript.txt`にあるキャラクター名へ置換。`%selfname2`は`sakura.name2`を使用 |
| `%screenwidth`, `%screenheight` | ✅ | 現在のメインスクリーンのポイント単位サイズへ置換 |
| `%exh`, `%et`, `%wronghour` | ✅ | `%exh`をOS連続起動秒、`%et`を間違った連続起動時間文字列、`%wronghour`を正しくない現在時へ置換 |
| `%ms/%mz/%ml/%mc/%mh/%mt/%me/%mp/%m?` | ✅ | UKADOCの各ランダム単語カテゴリをUtatane内蔵語彙から選んで置換。語彙集合はベースウェア固有 |
| `%dms`, `%lastghostname`, `%lastobjectname` | ✅ | `%dms`はUtatane内蔵の「～に～する～」相当語彙で置換。`%lastghostname` / `%lastobjectname` はNARインストール完了時に直近のインストール対象名で環境変数を更新 |
| `%*` | ✅ | `\![*]` と同じバルーンマーカーを表示 |

## SakuraScript以外のUKADOC領域

SakuraScript以外の仕様について、対応を進める領域をまとめています。個々のキーやイベントの一覧ではありません。詳しい確認結果は、各領域の対応表へ分けて記載します。

| UKADOC領域 | 状況 | 現在の範囲・主な不足 |
| --- | --- | --- |
| SHIORI Event（外部） | 🟡 | 現行UKADOCの304イベントを分類済み。実装範囲は[SHIORI Event対応表](UKADOC-SHIORI-Event-Compatibility.md)を参照 |
| SHIORI Resource | 🟡 | 主要なシステム・ゴースト・シェル・バルーン・メニュー・サイト情報を実装。完全な照会表は未作成 |
| SHIORI/3.0 | 🟡 | GET/NOTIFY、Reference、Charset、Valueなど基本モデルあり。全ヘッダー・ステータス未照合 |
| SSTP/1.x | ✅ | localhost Socket／HTTPのportable coreを実装。SEND、NOTIFY、COMMUNICATE、EXECUTE、GIVE、ゴースト指定、IfGhost、nobreak、情報取得・Cookie・Property・Archive系commandに対応。詳細は[UKADOC-SSTP-Compatibility.md](UKADOC-SSTP-Compatibility.md) |
| SAORI/1.0 | 🟡 | SSU等の限定ネイティブ互換。任意SAORI、Windows DLL汎用実行は対象外 |
| HEADLINE/2.0 | 🟡 | native `config.txt` とWine DLL fallback。全応答差異は未照合 |
| DLL規格 | 🟡 | SHIORIはnative実装と限定Wine経路。一般Windows DLLは対象外 |
| FMO / MUTEX | ❌ | Windows固有FMOは対象外。macOS向け互換公開方式も未設計 |
| Web関連 | 🟡 | homeurl更新、RSS/Atom、SSTP over HTTP中心。全仕様未照合 |
| Property System | 🟡 | 大文字小文字を無視する値解決、組み込みsystem/baseware値、動的な値登録、書込可否管理をコアに実装。SakuraScript・ゴースト一覧・UI状態との接続は未完 |

## 優先順位案

1. anim add/text、updateなど、実在ゴーストで使われる🟡を優先して埋める。
2. HTTP・RSS・iCalendar・Property Systemの未対応オプションを実データで確認する。
3. MenuBarアイコンのアニメーションなど、macOSで代替できるSSP固有UIを仕上げる。
4. Windows DLLを前提とする機能は、外部ホストまたはmacOSネイティブAPIの仕様を決めてから実装します。

## 更新ルール

- 実装PRでは該当行を同時に更新します。
- 「✅」へ変更する時はテストまたは実機確認の根拠を書きます。
- UKADOCの項目追加を定期的に確認し、確認日を冒頭で更新します。
- SSPとの差異を意図的に残す場合は「未対応」ではなく理由付きの「対象外候補」とします。
