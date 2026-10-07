# UKADOC SSTP/1.x互換状況

外部のアプリからゴーストへ話しかけるSSTPについて、使える通信方式と命令をまとめています。基準はUKADOCの`SSTP/1.x`です。

UtataneはSocket SSTPとSSTP over HTTPを扱います。Windowsの`WM_COPYDATA`を使うDirect SSTPは、macOSでは対象外です。

調査日: 2026-10-07（状態取得・割り込み制御・表示プロパティを追記）
調査結果: ✅ 19 / 🟡 3 / ❌ 0 / ➖ 3

## 通信と共通仕様

| 項目 | 状況 | Utataneの対応 |
| --- | --- | --- |
| Socket SSTP | ✅ | localhostのTCP 9801で待受。リクエストごとに切断 |
| SSTP over HTTP | ✅ | `POST /api/sstp/v1`、`text/plain`、Content-Length、HTTP 200内のSSTP応答 |
| 文字コード | ✅ | Charset必須。UTF-8とShift_JISを受理し、UTF-8で応答 |
| version | ✅ | SSTP/1.0以上3.0未満を受理。不正範囲は400 |
| サイズ制限 | ✅ | 1MiBを超えるリクエストは413 |
| セキュリティ | ✅ | リスナー自体を127.0.0.1へ限定。HTTPはlocalhost Originのみ受理 |
| Direct SSTP | ➖ | WindowsのHWND／WM_COPYDATA依存のためmacOS対象外 |

## メソッド

| メソッド | 状況 | Utataneの対応 |
| --- | --- | --- |
| SEND／NOTIFY | ✅ | Script、Event、Reference0〜255、Event応答なし時のScript fallback |
| COMMUNICATE | ✅ | Sender／SentenceをOnCommunicateのReference0／1へ、SSTP ReferenceをReference2以降へ転送 |
| GIVE | ✅ | DocumentをOnCommunicate、SongをOnMusicPlayへ変換 |
| EXECUTE | ✅ | 下記portable commandを実行。未知commandは501 |

SEND／NOTIFYは`Ghost`または`ReceiverGhostName`で起動中ゴーストを選択できます。`IfGhost`と直後の`Script`の組を出現順に評価し、該当しなければdefault Scriptを使います。`Option: nobreak`は現在の再生完了後へキューイングします。`nodescript`はUtataneに専用SSTPマーカーがないため結果に差はありません。`notranslate`は、SSTPで受け取ったScriptを現在のMAKOTO経路へ渡していないため、指定の有無で差はありません。

新しいSSTPが再生中のSSTPを中断する時は、`OnSSTPBreak`へその時点のスクリプト・話者・タグ込みの文字位置を渡します。`nobreak`の予約内容を中断対象と取り違えないようにし、新しい会話へ置き換えたり再生をキャンセルしたりした時は、残った予約も取り消します。

`\t`による割り込み禁止中は通常のSEND／NOTIFY／COMMUNICATE／GIVEを409で拒否します。SEND／NOTIFYの`nobreak`は予約でき、SHIORI `uniqueid`と一致する`ID`を付けたOwned SSTPは割り込みできます。

`Option: strict`はSEND／NOTIFY／GIVEとnobreakによる予約再生で解釈警告をログへ記録します。未知の命令、一部の不正な引数、存在しないサーフェス・アニメーションを元スクリプトの位置付きで診断します。すべての命令の引数検証とSSPの警告条件の完全な再現は未対応です。

## EXECUTE command

| command | 状況 | 備考 |
| --- | --- | --- |
| GetStatus | ✅ | 選択対象のSHIORI Status形式の現在状態。再生、モード、入力欄、選択肢、表示中バルーンを反映。非同期バックグラウンド通信のonline表示は一部未接続 |
| GetName／GetNames | ✅ | 起動中キャラクター名、インストール済みゴースト名 |
| GetGhostName／GetShellName／GetBalloonName | ✅ | 選択対象の現在値 |
| GetVersion／GetShortVersion | ✅ | Utataneのbundle version |
| GetGhostNameList／GetShellNameList／GetBalloonNameList／GetHeadlineNameList | ✅ | 認識済みコンテンツ一覧 |
| GetPluginNameList | ✅ | 認識済みプラグイン名を改行区切りで返します |
| Quiet／Restore | ✅ | 16秒またはRestoreまで通常SSTP再生を409で抑止 |
| SetCookie／GetCookie | ✅ | Sender単位の実行中メモリ保存 |
| SetProperty／GetProperty | ✅ | Property Systemと対象プレイヤーへ接続。surface.num／animation.num／seriko.defaultsurface／sticky-windowは表示へ反映。その他の読み取り専用値への書込は420 |
| CompressArchive／ExtractArchive | 🟡 | ghost/master配下に限定した安全なZIP操作。SSP管理下全フォルダや暗号化ZIP完全互換は未対応 |
| DumpSurface | 🟡 | scope・surface指定・crop・prefix・eventの位置／名前付き引数からPNGを出力。対象ゴーストを選択できる。animation指定で基本パターンを連番出力。別アニメーションの開始・停止、動画・拡縮パターンは未対応 |
| DumpBalloon | 🟡 | 対象ゴースト・scopeの保持中バルーンをPNGへ出力。位置／名前付き引数、prefix、event、hideを受理。実バルーンとの画素照合は未確認 |
| GetFMO／ReceiverGhostHWnd | ➖ | WindowsのFMO／HWND依存のためmacOS対象外 |
| MoveAsync／SetTrayIcon／SetTrayBalloon | ➖ | macOSに同等のSSP tray／HWND機構がないため対象外 |

`Command[param1,param2]`と`Reference0`以降の両方の引数形式を受理します。レスポンス追加データはUKADOCどおりヘッダー後の空行に続けて返します。
