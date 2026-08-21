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
| `\![set,alignmentondesktop/... ]` | ❌ | デスクトップ配置 |
| `\![set,scaling,...]` | ❌ | 実行中の倍率変更。設定画面の表示倍率とは別 |
| `\![set,alpha,...]` | ✅ | scope別の0〜100指定、上限クランプ、負値で値を維持した再描画、`--time`・旧位置引数によるアニメーション、`--wait`に対応 |
| `\![effect...]`, `\![filter...]` | ➖ | SSPプラグイン依存。実装方針が必要 |
| `\4`, `\5` | ❌ | キャラクター位置操作 |
| `\![move]`, `\![moveasync]` | ❌ | 全引数・衝突処理を含め未実装 |
| `\![set/reset,position...]` | ❌ | 未実装 |
| `\![set/reset,zorder...]` | ❌ | 未実装 |
| `\![set/reset,sticky-window...]` | ❌ | 未実装 |
| `\![execute,resetwindowpos]` | ❌ | 設定UIからの位置リセットとは未接続 |

### バルーンとテキスト

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\bID`, `\b[ID]` | 🟡 | scope別のバルーンsurface変更に対応。括弧なしは1桁、複数桁は括弧形式 |
| `\_b[ファイル,...]` 全形式 | ❌ | 座標表示、inline、opaque、各オプションとも未実装 |
| `\n` | ✅ | 改行 |
| `\n[half]`, `\n[百分率]` | 🟡 | 構文は受理するが通常改行と同じ |
| `\_n` | ❌ | 自動改行 |
| `\c` | ✅ | 現scopeの本文とリンクを消去 |
| `\c[char/line,...]` | ❌ | 部分消去 |
| `\_l[x,y]` | ❌ | 描画位置変更 |
| `\C` | ✅ | 全scopeの本文・リンクを消去し、Playerテストで確認 |
| `\![set,autoscroll,...]` | ✅ | `disable` / `enable` をスコープ単位で反映 |
| `\![set,balloonoffset/balloonalign/balloonmarker/balloonnum,...]` | ❌ | 未実装 |
| `\![set,balloontimeout,...]` | ✅ | 表示完了後のバルーン消去時間を指定。0以下で無効、選択肢タイムアウトとの競合は早い方を採用 |
| `\![set,balloonwait,...]` | ✅ | 倍率・百分率・`ms` 絶対値に対応し、スクリプト終了時に復帰 |
| `\![set,serikotalk,...]` | ❌ | 発話中の SERIKO `talk` アニメーション駆動が未実装 |
| `\![*]` | ✅ | scope別の `marker*.png` をインライン表示 |
| online / nouserbreak mode | ❌ | `enter` / `leave` とも未実装 |
| balloon repaint / move lock | ❌ | `lock` / `unlock` とも未実装 |
| `\_!`, `\_?` | ✅ | 区間内のタグ・環境変数を解釈せずそのまま表示。閉じタグがない場合は末尾までを対象にしParserテストで確認 |
| `\__v` | ❌ | 音声合成・バックログ制御は未実装 |
| `\![execute,resetballoonpos]` | ❌ | 未実装 |

### 文字装飾

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\f[align/valign,...]` | ❌ | 未実装 |
| `\f[name,フォント名]` | 🟡 | インストール済みフォント名と `default` に対応。代替フォントファイル指定は未対応 |
| `\f[height,数値]` | 🟡 | 絶対値、相対値、百分率、`default` に対応。CSS風サイズ名は未対応 |
| `\f[color,色指定]` | 🟡 | RGB、百分率RGB、`#RRGGBB`、主要な色名、`default` に対応。全色名は未照合 |
| shadow color/style、outline | ❌ | 未実装 |
| anchor font color | ❌ | バルーン `descript.txt` の色は使うが実行中変更なし |
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
| syncobject の wait / set / reset | ❌ | 未実装 |

### 選択肢・アンカー

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\q[タイトル,ID]` | ✅ | クリック可能 |
| `\q[タイトル,OnID,r0...]` | ✅ | 追加引数を渡す |
| `\q[タイトル,ID1,ID2...]` | 🟡 | 2番目をID、以降を引数として扱う。旧形式固有の意味とは未照合 |
| `script:` 選択肢 | ✅ | 通常・範囲選択肢でクリック時に指定SakuraScriptを直接再生し、SHIORI選択イベントを発生させないことをPlayerテストで確認 |
| `\q[ID][タイトル]`, `\q*[ID][タイトル]` | ❌ | 旧形式未実装 |
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
| `\-`, `\a` | ❌ | 終了・自動終了未実装 |
| update / updatebymyself / updateother | 🟡 | `updatebymyself`、`update,ghost`、`update,balloon`を既存更新機能へ接続。platform・updateother・全オプションは未対応 |
| `\6`, `\7`, SNTP, biff, vanish | ❌ | 未実装 |
| `\![execute,headline,...]` | ✅ | 名前またはディレクトリ名で既存RSS／HEADLINEセンサーを実行 |
| `\+`, `\_+`, change/call ghost | 🟡 | ランダム／順次切替と、名前・ディレクトリ名・`random`・`sequential`指定を接続。lastinstalledとraise-eventオプションは未対応 |
| change shell / balloon | ✅ | 名前またはディレクトリ名で通常／呼び出しゴーストの既存切替処理へ接続 |
| `\v` | ❌ | 未実装 |
| windowstate / wallpaper / tray | ➖ | macOSでの代替仕様を決める必要あり |
| otherghosttalk / othersurfacechange | ❌ | 未実装 |
| `\![raise,...]` | ✅ | SHIORIイベントを発生させ、元スクリプトの残りを破棄して応答スクリプトへ切り替える |
| `\![embed,...]` | ✅ | SHIORIイベントの戻り値を現在の再生列へ埋め込む |
| timerraise / raiseother / raiseplugin | 🟡 | `timerraise`と`raiseother`に対応。他ゴーストは名前指定と全ゴースト指定が可能。timerraiseother・プラグイン宛は未対応 |
| notify / timernotify / other / plugin | 🟡 | 自ゴーストへの`notify`・`timernotify`と`notifyother`に対応し、SHIORI応答は表示しない。timernotifyother・プラグイン宛は未対応 |

### サウンド

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\8[file]`, `\_v[file]`, `\_V`, `\![sound,...]` | 🟡 | `play`・`load`・`loop`・`wait`・`pause`・`resume`・`stop`・`option` を実装。volume、balance、rate、seektimeに対応。`ghost/master` 内のAVFoundation対応音声のみ。CD・動画ウィンドウは対象外 |

### 外部UI・入力

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\j[ID]`, `\![open,browser,...]` | 🟡 | メイン／呼び出しゴーストともHTTP・HTTPSを既定ブラウザで開く。`file:`・`mailto:`は未対応 |
| mailer / addressbar / editor / explorer | ➖ | macOSでの代替と安全境界が必要 |
| teachbox / communicatebox | ❌ | UI未実装 |
| `\![open,inputbox,...]` | 🟡 | ID、timeout、初期値を解析し、入力値を指定されたIDのSHIORIイベントへ `Reference0` として返す。timeoutの実動作と全オプションは未対応 |
| password/date/slider/time/ip input | ❌ | 未実装 |
| close inputbox | ❌ | 未実装 |
| configuration / 各explorer / graph / calendar | ❌ | SSP固有UI未実装 |
| help / messenger / readme / terms / file | ❌ | 未実装 |
| open/save/folder/color dialog、close dialog | ❌ | 未実装 |
| surfacetest / aigraph / developer / shiorirequest / errorlog | ❌ | 開発UI未実装 |
| dressup / picture / archive / backlog viewer | ❌ | 未実装 |

### Property System

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\![set,property,...]` | ❌ | Property System自体が未実装 |
| `\![get,property,...]` | ❌ | MCPでも意図的に提供していない |
| `%property[...]` | ❌ | 未実装 |

### HTTP、WebSocket、アーカイブなど

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `\![execute,http-get,URL,...]` | 🟡 | `--async=イベントID` を含むGETのみ。結果一時ファイルを `Reference3` で返す |
| http-post/head/put/delete/patch/options | ❌ | 未実装 |
| rss-get/rss-post | ❌ | RSS/Atom取得機能はあるがこのコマンド未接続 |
| websocket execute/send/close/cancel | ❌ | 未実装 |
| cancel http | ❌ | 未実装 |
| extract/compress archive | ❌ | NAR展開処理はあるが任意コマンドとしては未接続 |
| dumpsurface | ❌ | 未実装 |
| install path / URL | ❌ | ドロップによるNARインストールはあるがコマンド未接続 |
| ping / nslookup | ❌ | 未実装 |
| createnar / createupdatedata | ❌ | 未実装 |
| emptyrecyclebin / create shortcut | ➖ | OS依存かつ危険。原則対象外候補 |
| passive / induction / select / collision mode | ❌ | 未実装 |
| reload surface/descript/shiori/makoto/shell/balloon/ghost/aigraph | ❌ | 未実装 |
| unload/load shiori・makoto、shioridebugmode | ❌ | 未実装 |
| `\_u`, `\_m` | ✅ | 16進・10進のUCS-2／ASCIIコードを文字へ変換。範囲外とサロゲートは拒否しParserテストで確認 |
| `\&[ID]` | 🟡 | amp・apos・gt・lt・nbsp・quotの主要な実体参照に対応。全識別子は未対応 |
| `\m` | ➖ | SSTPのWindowsウィンドウメッセージ送信に依存するためmacOSでは対象外候補 |
| `\![execute,weather-get,...]` | 🟡 | Utatane拡張。`--async=イベントID` のみ |

### 環境変数

| コマンド群 | 状況 | 備考 |
| --- | --- | --- |
| `%month/day/hour/minute/second` | ✅ | 描画時のローカル日時へ置換 |
| `%username`, `%selfname`, `%selfname2`, `%keroname` | 🟡 | macOSユーザー名とゴーストのキャラクター名へ置換。`selfname2`専用キー未保持のため本体名へフォールバック |
| `%screenwidth`, `%screenheight` | ✅ | 現在のメインスクリーンのポイント単位サイズへ置換 |
| `%exh`, `%et`, `%wronghour` | 🟡 | `%exh`をOS連続起動秒へ置換。ジョーク用途の`et`・`wronghour`は未実装 |
| `%ms/%mz/%ml/%mc/%mh/%mt/%me/%mp/%m?` | 🟡 | UKADOCの各ランダム単語カテゴリをUtatane内蔵語彙で置換。SSPの語彙集合とは異なる |
| `%dms`, `%lastghostname`, `%lastobjectname` | 🟡 | `%dms`はUtatane内蔵の「～に～する～」相当語彙で置換。インストールイベント用のlast系は未接続 |
| `%*` | ✅ | `\![*]` と同じバルーンマーカーを表示 |

## SakuraScript以外のUKADOC領域

これは個々のキーやイベントを網羅する表ではなく、次に詳細対応表を作るべき領域の棚卸し。各領域を実装する時に別表へ展開する。

| UKADOC領域 | 状況 | 現在の範囲・主な不足 |
| --- | --- | --- |
| Ghost `descript.txt` | 🟡 | 名前、SHIORI、scope、default surface、更新URLなど実利用キー中心。全キー表が必要 |
| Shell `descript.txt` | 🟡 | 基本情報、scope、メニュー関係の一部。全キー未網羅 |
| `surfaces.txt` | 🟡 | surface、alias、element、collision、主要animationを実装。SERIKOの全pattern・optionは要照合 |
| `surfacetable.txt` | ❌ | 明示的な実装なし |
| Balloon `descript.txt` | 🟡 | 画像、位置、文字領域、フォント、cursor/anchorの主要設定。ROP、visited、全キー未対応 |
| `balloon(s/k)*s.txt` | ❌ | 旧バルーン定義形式は未実装 |
| Plugin `descript.txt` / PLUGIN | ❌ | プラグイン機構なし |
| Headline `descript.txt` | 🟡 | RSS型とHEADLINEセンサーを実装。全SSPキー・イベント未照合 |
| `install.txt` | 🟡 | Ghost/Shell/Balloon NARと同梱バルーンを実装。全インストール種別・上書き規則は未網羅 |
| `delete.txt` | ❌ | 明示的な実装なし |
| `developer_options.txt` | ❌ | 明示的な実装なし |
| SHIORI Event | 🟡 | 起動、終了、切替、時刻、マウス、選択肢、入力、更新など実利用イベント中心。完全イベント表が必要 |
| SHIORI Event（外部） | 🟡 | SSTPや一部コールバック。全イベント未網羅 |
| SHIORI Resource | ❌ | 完全なresource照会表なし |
| SHIORI/3.0 | 🟡 | GET/NOTIFY、Reference、Charset、Valueなど基本モデルあり。全ヘッダー・ステータス未照合 |
| SSTP/1.x | 🟡 | localhostのSEND/NOTIFYとHTTPラップ。全メソッド、ヘッダー、セキュリティレベル未対応 |
| SAORI/1.0 | 🟡 | SSU等の限定ネイティブ互換。任意SAORI、Windows DLL汎用実行は対象外 |
| HEADLINE/2.0 | 🟡 | native `config.txt` とWine DLL fallback。全応答差異は未照合 |
| DLL規格 | 🟡 | SHIORIはnative実装と限定Wine経路。一般Windows DLLは対象外 |
| FMO / MUTEX | ❌ | Windows固有FMOは対象外。macOS向け互換公開方式も未設計 |
| 更新定義ファイル | 🟡 | `updates2.dau` / `updates.txt`、MD5、ロールバック対応。全オプション未照合 |
| Web関連 | 🟡 | homeurl更新、RSS/Atom、SSTP over HTTP中心。全仕様未照合 |
| Property System | ❌ | 未実装 |

## 優先順位案

1. 実在ゴーストで利用頻度が高いsoundオプションと、残る表示・入力系コマンド。
2. 既存Utatane機能へ接続する update、change ghost/shell/balloon、headline、install。
3. `surfaces.txt`、Balloon/Ghost/Shell `descript.txt`、SHIORI Eventの詳細対応表。
4. HTTPメソッド、timerraise、Property Systemなど高度な互換機能。
5. Windows・SSP固有UIに依存する項目は、macOS向け代替仕様を決めてから実装可否を判定する。

## 更新ルール

- 実装PRでは該当行を同時に更新する。
- 「✅」へ変更する時はテストまたは実機確認の根拠を書く。
- UKADOCの項目追加を定期的に確認し、確認日を冒頭で更新する。
- SSPとの差異を意図的に残す場合は「未対応」ではなく理由付きの「対象外候補」とする。
