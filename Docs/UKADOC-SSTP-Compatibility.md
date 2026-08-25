# UKADOC SSTP/1.x互換状況

参照元はUKADOCの`SSTP/1.x`。UtataneではmacOSで利用可能なSocket SSTPとSSTP over HTTPを対象とし、Windowsの`WM_COPYDATA`に依存するDirect SSTPは対象外とする。

調査日: 2026-08-25
調査結果: ✅ 18 / 🟡 2 / ❌ 0 / ➖ 3

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

SEND／NOTIFYは`Ghost`または`ReceiverGhostName`で起動中ゴーストを選択できる。`IfGhost`と直後の`Script`の組を出現順に評価し、該当しなければdefault Scriptを使う。`Option: nobreak`は現在の再生完了後へキューイングする。`nodescript`はUtataneに専用SSTPマーカーがないため結果に差がなく、`notranslate`はMAKOTO／OnTranslate経路自体がないため常に同等の扱いになる。

## EXECUTE command

| command | 状況 | 備考 |
| --- | --- | --- |
| GetName／GetNames | ✅ | 起動中キャラクター名、インストール済みゴースト名 |
| GetGhostName／GetShellName／GetBalloonName | ✅ | 選択対象の現在値 |
| GetVersion／GetShortVersion | ✅ | Utataneのbundle version |
| GetGhostNameList／GetShellNameList／GetBalloonNameList／GetHeadlineNameList | ✅ | 認識済みコンテンツ一覧 |
| GetPluginNameList | ✅ | plugin未実装のため空リスト |
| Quiet／Restore | ✅ | 16秒またはRestoreまで通常SSTP再生を409で抑止 |
| SetCookie／GetCookie | ✅ | Sender単位の実行中メモリ保存 |
| SetProperty／GetProperty | ✅ | Property Systemへ接続。読み取り専用値への書込は420 |
| CompressArchive／ExtractArchive | 🟡 | ghost/master配下に限定した安全なZIP操作。SSP管理下全フォルダや暗号化ZIP完全互換は未対応 |
| DumpSurface | 🟡 | 現在の本体側surfaceをPNG出力。SSPの全scope・crop・prefix引数は未対応 |
| GetFMO／ReceiverGhostHWnd | ➖ | WindowsのFMO／HWND依存のためmacOS対象外 |
| MoveAsync／SetTrayIcon／SetTrayBalloon | ➖ | macOSに同等のSSP tray／HWND機構がないため対象外 |

`Command[param1,param2]`と`Reference0`以降の両方の引数形式を受理する。レスポンス追加データはUKADOCどおりヘッダー後の空行に続けて返す。
