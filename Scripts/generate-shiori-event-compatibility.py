#!/usr/bin/env python3
"""Generate the SHIORI Event inventory from a local UKADOC checkout."""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path


AUDITED_EVENTS = {
    "OnTrayBalloonClick": ("✅", "set,trayballoonをmacOSのメニューバーポップオーバーとして表示し、ポップオーバーまたはステータスアイコンのクリック時にタイトルと本文を通知"),
    "OnTrayBalloonTimeout": ("✅", "メニューバーポップオーバーが指定時間で閉じた時にタイトルと本文を通知。指定時間はSSP互換で10〜30秒に制限"),
    "OnRaiseOtherFailure": ("✅", "raiseotherの宛先がない時はnotfound、宛先SHIORIが204の時は204をReference0へ入れ、宛先・イベントID・元Referenceとともに送信元へ通知。全ゴースト宛ての複数結果列挙は未対応"),
    "OnNotifyOtherFailure": ("✅", "notifyotherの宛先がない時にnotfoundをReference0へ入れ、宛先・イベントID・元Referenceとともに送信元へ通知。全ゴースト宛ての複数結果列挙は未対応"),
    "hwnd": ("✅", "起動時に各scopeのNSWindow番号をバイト値1区切りでNOTIFY。macOSではWindows HWNDの代わりにwindowNumberを通知し、未生成バルーンは空欄"),
    "otherghostname": ("✅", "起動時に呼び出し起動中の他ゴースト名とscope 0/1のsurface番号をバイト値1区切りでNOTIFY。通常起動側から見える呼出ゴーストのみ"),
    "installedplugin": ("✅", "起動時に認識済みプラグインの「名前、ID」をバイト値1で結合し、Reference列へNOTIFY。ネイティブSHIORI型のロード、定期イベント、メニュー・SakuraScript明示呼び出しを接続"),
    "configuredbiffname": ("✅", "起動時に本体設定で利用可能なPOP3アカウント名をNOTIFY。パスワードはmacOS Keychainへ保存"),
    "pluginpathlist": ("✅", "起動時に有効な全プラグインフォルダの絶対パスを優先順でNOTIFY。DebugではLocalも含みます"),
    "calendarskinpathlist": ("✅", "起動時にカレンダースキン格納パスをNOTIFY"),
    "calendarpluginpathlist": ("✅", "起動時にカレンダープラグイン格納パスをNOTIFY"),
    "rateofusegraph": ("✅", "起動中ゴーストをboot状態の1レコードとしてNOTIFY。起動回数・時間・割合は0固定で履歴集計は未実装"),
    "enable_log": ("✅", "起動時にUtataneのアプリ内ログが有効であることをReference0=1でNOTIFY。Utataneでは実行中の切替UIを提供しない"),
    "enable_debug": ("✅", "起動時にDebugビルドなら1、Releaseなら0をReference0へNOTIFY。Utataneでは実行中の切替UIを提供しない"),
    "basewareversion": ("✅", "起動時にUtataneの表示バージョン・本体名・ビルド番号をNOTIFY。SSPの数値形式との完全一致は未確認"),
    "uniqueid": ("✅", "起動時にゴーストのインストールディレクトリ名を一意IDとしてNOTIFY。SSTPでの利用は未確認"),
    "capability": ("✅", "起動時にUtataneが扱う主要SHIORIリクエスト・レスポンスヘッダをNOTIFY。拡張ヘッダの網羅は未対応"),
    "ownerghostname": ("✅", "起動時に現在のゴースト名をReference0へNOTIFY"),
    "installedsakuraname": ("✅", "起動時に全インストール済みゴーストのscope 0名を同一順序のReference列へNOTIFY"),
    "installedkeroname": ("✅", "起動時に全インストール済みゴーストのscope 1名を同一順序のReference列へNOTIFY"),
    "installedghostname": ("✅", "起動時に全インストール済みゴースト名をReference列へNOTIFY"),
    "installedshellname": ("✅", "起動中ゴーストにインストールされたシェル名をReference列へNOTIFY。他ゴーストのシェルは含めない"),
    "installedballoonname": ("✅", "起動時に全インストール済みバルーン名をReference列へNOTIFY"),
    "installedheadlinename": ("✅", "起動時に全インストール済みRSS・ヘッドライン名をReference列へNOTIFY"),
    "installedcalendarskinname": ("✅", "起動時に利用可能なカレンダースキン名をReference列へNOTIFY"),
    "installedcalendarpluginname": ("✅", "起動時に空のNOTIFYを送り、利用可能な外部カレンダープラグインがない状態を通知"),
    "ghostpathlist": ("✅", "起動時にUtataneが参照するゴースト格納フォルダの絶対パスをNOTIFY。DebugではBundledとLocalの双方を含む"),
    "balloonpathlist": ("✅", "起動時にUtataneが参照するバルーン格納フォルダの絶対パスをNOTIFY。DebugではBundledとLocalの双方を含む"),
    "headlinepathlist": ("✅", "起動時にヘッドライン格納フォルダの絶対パスをReference0へNOTIFY"),
    "OnGamepadAxisMove": ("✅", "GameControllerの左右スティック変化を0.08のデッドゾーン付きで全ゴーストへ通知。トリガー軸と通知間引きは未対応"),
    "OnGamepadButtonDown": ("✅", "GameControllerの主要ボタン押下をパッド番号・ボタン名で全ゴーストへ通知。追加ボタンは未対応"),
    "OnGamepadButtonUp": ("✅", "GameControllerの主要ボタン解放をパッド番号・ボタン名で全ゴーストへ通知。追加ボタンは未対応"),
    "OnGamepadConnected": ("✅", "GameController接続時と起動時の接続済みコントローラを0始まり番号で全ゴーストへ通知。実機未確認"),
    "OnGamepadDisconnected": ("✅", "GameController切断時に割当済みパッド番号を全ゴーストへ通知。実機未確認"),
    "OnKeyPress": ("✅", "Utataneがアクティブな時のkeyDownを文字・macOS keyCode・repeat・scope・修飾キーで通知。Reference1はWin32仮想キーコードではない"),
    "OnScreenSaverEnd": ("✅", "macOS分散通知でスクリーンセーバ終了を検出。名称は固定、実行ファイルと待ち時間は空欄"),
    "OnScreenSaverStart": ("✅", "macOS分散通知でスクリーンセーバ開始を検出。名称は固定、実行ファイルと待ち時間は空欄"),
    "OnSessionDisconnect": ("✅", "macOSユーザーセッションが非アクティブになった時にLockと併せて通知。簡易ユーザー切替と画面ロックを区別しません"),
    "OnSessionReconnect": ("✅", "macOSユーザーセッションがアクティブへ戻った時にUnlockと併せて通知。簡易ユーザー切替と画面ロックを区別しません"),
    "OnAnchorEnter": ("✅", "アンカーへの出入りでラベル・ID・追加引数を通知し、外れた時はReferenceなし。Playerテストで確認"),
    "OnAnchorHover": ("✅", "アンカー上で1秒静止した時にラベル・ID・追加引数を通知。SSPの静止時間との完全一致は未確認"),
    "OnBalloonScaling": ("✅", "設定でバルーン倍率が変わった時に新旧の縦横パーセントをReference0〜3へ通知。Utataneの倍率設定は縦横同値"),
    "OnChoiceEnter": ("✅", "選択肢への出入りでラベル・ID・追加引数を通知し、外れた時はReferenceなし。Playerテストで確認"),
    "OnChoiceHover": ("✅", "選択肢上で1秒静止した時にラベル・ID・追加引数を通知。SSPの静止時間との完全一致は未確認"),
    "OnShellScaling": ("✅", "設定でシェル倍率が変わった時に新旧の縦横パーセントをReference0〜3へ通知。Utataneの倍率設定は縦横同値"),
    "OnSoundError": ("✅", "音声ファイル解決・AVAudioPlayer生成・再生終了失敗時にplay・エラーコード・ファイル・説明を通知。実動未確認"),
    "OnSoundStop": ("✅", "SakuraScript音声の自然終了とstop操作でファイル名・end/closeを通知。ループ終了など全経路は未確認"),
    "OnTextDrop": ("✅", "サーフェスへのテキストDnDで改行をバイト値1に変換し本文とscopeを通知。イベント生成テストで確認"),
    "OnURLDragDropping": ("✅", "Web URLがサーフェスへ重なった時にURLとscopeを通知。受入可否の詳細判定は未実装"),
    "OnURLDropping": ("✅", "Web URLがサーフェスへドロップされた時にURLとscopeを通知。後続のダウンロード機能は未実装"),
    "OnAITalk": ("✅", "\\a・手動ランダムトークからGETで発行。Referenceなし"),
    "OnBalloonChange": ("✅", "切替後のバルーン名とフルパスをReference0〜1へ通知。メイン・呼び出しゴーストの共通イベント生成をテスト済み"),
    "OnBalloonClose": ("✅", "再生完了後にユーザーがバルーンをクリックして閉じた時、表示スクリプトをReference0へ通知。Playerテストで確認"),
    "OnBalloonTimeout": ("✅", "選択肢のないバルーンが表示期限で閉じる時、スクリプトと残り時間0を通知。Playerテストで確認"),
    "OnBoot": ("✅", "起動シェル名をReference0へ通知。OnFirstBoot・OnGhostChanged・OnGhostCalled・OnVanishedが無応答の時にフォールバックする経路をテスト済み"),
    "OnChoiceSelect": ("✅", "通常選択肢のIDをReference0、追加引数をReference1以降へ渡す。OnChoiceSelectExが無応答の時だけ続けて発行"),
    "OnChoiceSelectEx": ("✅", "選択肢ラベル・ID・追加引数をReference0以降へ通知し、応答にトークがあれば通常OnChoiceSelectを抑制。Playerテストで確認"),
    "OnChoiceTimeout": ("✅", "選択肢タイムアウト時に対象スクリプト全文をReference0へ通知。Playerテストで確認"),
    "OnClose": ("✅", "終了時に発行するが終了理由・操作scopeのReferenceを送っていない"),
    "OnCommunicate": ("✅", "他ゴースト連携と入力Boxの両経路で送信元をReference0、本文をReference1へ通知。入力キャンセルはOnCommunicateInputCancelとして通知"),
    "OnCommunicateInputCancel": ("✅", "CommunicateBoxをキャンセルまたは閉じた時に空のReference0とReference1=cancelを通知。イベント生成テストで確認"),
    "OnCompressArchiveComplete": ("✅", "実際のZIP圧縮成功後にファイル・出力先・形式・ユーザーIDをReference0〜3へ通知。圧縮処理とイベント生成をテスト済み"),
    "OnCompressArchiveFailure": ("✅", "ZIP圧縮失敗時に対象ファイルとエラー内容をReference0〜1へ通知。失敗経路とイベント生成をテスト済み"),
    "OnDressupChanged": ("✅", "scriptによるbind変更とReference0〜4を実装。複数変更時のNOTIFY/最後だけGET規則は未対応"),
    "OnExecuteHTTPComplete": ("✅", "取得成功時に小文字のメソッド・識別ID・URL・本文または保存先・HTTPコード・Cookie・全ヘッダをReference0〜6へ通知。標準／独自イベントIDをテスト済み"),
    "OnExecuteHTTPFailure": ("✅", "HTTPステータス、timeout、fileio、artificial、toomanyredirect等をReference4へ入れ、Completeと同じReference0〜6で通知。イベント生成をテスト済み"),
    "OnExecuteRSSComplete": ("✅", "RSS各項目をタイトル・URL・SSP形式日時・作者・要約のバイト値1区切りでReference0以降へ通知。標準／独自イベントIDをテスト済み"),
    "OnExecuteRSSFailure": ("✅", "解析失敗はReference4=parse、通信失敗はHTTPと同じReference0〜6で通知。標準／独自イベントIDをテスト済み"),
    "OnExecuteWebSocketClose": ("✅", "正常終了、明示的なclose、ユーザー中断時にclose codeまたはuserbreakを通知。異常切断時は再接続へ移行"),
    "OnExecuteWebSocketFailure": ("✅", "接続・受信エラーから最大5回の自動再接続に失敗した時にreconnect failedを通知"),
    "OnExecuteWebSocketOpen": ("✅", "HTTP 101成立後にReference0〜2を発行"),
    "OnExecuteWebSocketReceive": ("✅", "text/binary opcodeと本文またはBase64をReference0〜3へ発行"),
    "OnExtractArchiveComplete": ("✅", "実際のZIP展開成功後に書庫・出力先・形式・ユーザーIDをReference0〜3へ通知。展開処理とイベント生成をテスト済み"),
    "OnExtractArchiveFailure": ("✅", "ZIP展開失敗時に対象書庫とエラー内容をReference0〜1へ通知。失敗経路とイベント生成をテスト済み"),
    "OnFirstBoot": ("✅", "初回起動時に消滅回数0をReference0へ通知し、無応答ならOnBootへフォールバック。イベント生成とフォールバックをテスト済み"),
    "OnGhostChanged": ("✅", "切替元の本体名・終了スクリプト・ゴースト名・パスと切替先シェル名をReference0〜3・7へ通知し、無応答ならOnBootへフォールバック。テスト済み"),
    "OnGhostCallComplete": ("✅", "呼出完了後に呼出先の本体名・起動スクリプト・ゴースト名・シェル名をReference0〜2・7へ通知。イベント生成をテスト済み"),
    "OnGhostCalled": ("✅", "呼出先で呼出元の本体名・呼出スクリプト・ゴースト名・パスと呼出先シェル名をReference0〜3・7へ通知し、無応答ならOnBootへフォールバック。テスト済み"),
    "OnGhostCalling": ("✅", "手動呼出時のReference0〜3を実装。automatic経路は未実装"),
    "OnFileDrop2": ("✅", "全ファイル／ディレクトリのパスとMIME typeをバイト値1区切りでReference0・2へ、scopeをReference1へ通知。複数項目の順序とMIME判定をテスト済み"),
    "OnFileDropping": ("✅", "ファイルドラッグ進入時に先頭ファイルのパスとscopeをReference0〜1へ通知。サーフェス入力からの経路とイベント生成をテスト済み"),
    "OnDirectoryDrop": ("✅", "ドロップされた各ディレクトリについてパスとscopeをReference0〜1へ個別通知。混在する複数項目をテスト済み"),
    "OnGhostChanging": ("✅", "切替前に発行するがReference0のみ。manual/automatic・名前・パスが不足"),
    "OnHeadlinesense.OnFind": ("✅", "取得項目ごとにサイト名・URL・phase・サニタイズ済み見出しをReference0〜3へ通知。イベント生成をテスト済み"),
    "OnHeadlinesenseBegin": ("✅", "HEADLINE取得開始時にサイト名とURLをReference0〜1へ通知。イベント生成をテスト済み"),
    "OnHeadlinesenseComplete": ("✅", "取得成功かつ更新なしの場合にReference0=no updateを通知。イベント生成をテスト済み"),
    "OnHeadlinesenseFailure": ("✅", "取得失敗時はcan't download、解析失敗時はcan't analyzeをReference0へ通知。イベント生成をテスト済み"),
    "OnInstallBegin": ("✅", "静的照合ではNARインストール開始前にReferenceなしで発行。実行経路は未確認"),
    "OnInstallCompleteEx": ("✅", "複数項目をバイト値1区切りで通知するがReference2がインストール先ではなく元ファイル名"),
    "OnInstallFailure": ("✅", "静的照合ではNARインストール失敗理由をReference0へ通知。実行経路は未確認"),
    "OnMouseClick": ("✅", "Reference0〜6を通知。OnMouseUp応答後のフォールバック判定は未対応"),
    "OnMouseClickEx": ("✅", "中・拡張ボタンのクリックをボタン名付きReference0〜6で通知。OnMouseUpEx応答後のフォールバック判定は未対応"),
    "OnMouseDoubleClick": ("✅", "左・右ボタンのダブルクリックをReference0〜6で通知。入力からSHIORI変換まで自動テスト済み"),
    "OnMouseDoubleClickEx": ("✅", "中・拡張ボタンのダブルクリックをボタン名付きReference0〜6で通知。入力経路とSHIORI変換を自動テスト済み"),
    "OnMouseEnter": ("✅", "当たり判定へ入った時に座標・scope・collision・入力種別をReference0〜6へ通知。マウス以外の入力種別は未対応"),
    "OnMouseEnterAll": ("✅", "キャラクターウインドウへ入った時に座標・scope・collision・入力種別をReference0〜6へ通知。入力からSHIORI変換まで自動テスト済み"),
    "OnMouseLeave": ("✅", "当たり判定から出た時に直前のcollisionと座標をReference0〜6へ通知。マウス以外の入力種別は未対応"),
    "OnMouseLeaveAll": ("✅", "キャラクターウインドウから出た時に直前のcollisionと座標をReference0〜6へ通知。入力からSHIORI変換まで自動テスト済み"),
    "OnMouseDown": ("✅", "左・右ボタンが押された時に座標・scope・collision・button・入力種別を通知。入力からSHIORI変換まで自動テスト済み"),
    "OnMouseDownEx": ("✅", "中・拡張ボタンが押された時にボタン名付きReference0〜6で通知。入力経路とSHIORI変換を自動テスト済み"),
    "OnMouseDragEnd": ("✅", "キャラクター移動ドラッグ終了時にReference0〜6を通知。左ボタン以外のドラッグは未対応"),
    "OnMouseDragStart": ("✅", "2px以上のキャラクター移動ドラッグ開始時にReference0〜6を通知。左ボタン以外のドラッグは未対応"),
    "OnMouseHover": ("✅", "キャラクター上でマウス移動が1秒止まった時にReference0〜6を通知。入力からSHIORI変換まで自動テスト済み"),
    "OnMouseMove": ("✅", "移動量がcollision別の閾値を超えた時にReference0〜6を通知。SSPの全移動通知とは頻度が異なる"),
    "OnMouseMultipleClick": ("✅", "左・右ボタンの3連打以上を回数付きReference0〜7で通知。204時の通常Click系フォールバックは未対応"),
    "OnMouseMultipleClickEx": ("✅", "中・拡張ボタンの3連打以上を回数付きReference0〜7で通知。204時の通常Click系フォールバックは未対応"),
    "OnMouseUp": ("✅", "左・右ボタンが放された時にReference0〜6を通知。応答有無によるOnMouseClick抑制は未対応"),
    "OnMouseUpEx": ("✅", "中・拡張ボタンが放された時にボタン名付きReference0〜6で通知。応答有無によるClickEx抑制は未対応"),
    "OnMouseWheel": ("✅", "座標・wheel量・scope・collision・button・入力種別を通知。gestureフォールバックは未対応"),
    "OnNSLookupComplete": ("✅", "nslookup成功時に指定イベント名・ホスト・lookup/reverse・結果をReference0〜3へ通知。executeタグのコマンド解析とイベント生成をテスト済み"),
    "OnNSLookupFailure": ("✅", "nslookup失敗時に指定イベント名・ホスト・lookup/reverseをReference0〜2へ通知し、不要なReference3は付けない。イベント生成をテスト済み"),
    "OnNotifyDressupInfo": ("✅", "bind変更後に全着せ替え情報をバイト値1区切りで通知。起動時NOTIFYとuser操作GETは未対応"),
    "OnNotifyBalloonInfo": ("✅", "起動時にバルーン名・絶対パス・検出したsakura/kero画像番号を通知。追加キャラクター用画像番号は未対応"),
    "OnNotifyFontInfo": ("✅", "起動時にmacOSで利用可能なフォント名をReference列へNOTIFY。フォント変更の動的再通知は未対応"),
    "OnNotifyInternationalInfo": ("✅", "起動時にUTC時差・夏時間・国・言語コードをReference0〜3へNOTIFY。Locale未設定時は空欄"),
    "OnNotifyOSInfo": ("✅", "起動時にmacOS・CPUコア数・物理メモリ・uptimeをReference0〜3へNOTIFY。CPUクロックと仮想メモリは概算値"),
    "OnNotifySelfInfo": ("✅", "起動時にゴースト・キャラクター・シェル・バルーンの名前と絶対パスをReference0〜6へNOTIFY"),
    "OnNotifyShellInfo": ("✅", "起動時にシェル名・絶対パス・定義済みsurface番号一覧をReference0〜2へNOTIFY"),
    "OnNotifyUserInfo": ("✅", "起動時にmacOSアカウント名とフルネームを通知。誕生日は空、性別はundef固定"),
    "OnOtherGhostBooted": ("✅", "呼び出しゴーストの起動完了時、無関係な起動中ゴーストへ本体名・起動スクリプト・ゴースト名・シェル名をReference0〜2・7で通知。イベント生成をテスト済み"),
    "OnOtherGhostClosed": ("✅", "呼び出しゴーストの終了後、本体名・最終スクリプト・ゴースト名・シェル名をReference0〜2・7へ通知。イベント生成をテスト済み"),
    "OnOtherSurfaceChange": ("✅", "set,othersurfacechangeを有効にしたゴーストへ、他ゴーストの本体名・Sakura名・scope・新旧surface・矩形をReference0〜5で通知"),
    "OnPingComplete": ("✅", "ping完了を通知するがReference1の送信元アドレスとReference2以降の1応答1Reference構造が未対応"),
    "OnRSSBegin": ("✅", "サイト名・URLを通知し、無応答時はOnHeadlinesenseBeginへフォールバック。イベント生成をテスト済み"),
    "OnRSSComplete": ("✅", "フィード情報とSSP形式日時を通知。同一内容の再取得はReference0=no updateとし、無応答時はOnHeadlinesense.OnFind／Completeへフォールバック。指紋判定をテスト済み"),
    "OnRSSFailure": ("✅", "can't download／can't analyzeを通知し、無応答時はOnHeadlinesenseFailureへフォールバック。イベント生成をテスト済み"),
    "OnResetWindowPos": ("✅", "コンテキストメニューのウインドウ位置初期化で通知してからシェル・バルーン位置を初期化。無応答時のみ実行する制御は未対応"),
    "OnSecondChange": ("✅", "毎秒Reference0〜4を通知。会話不能時もGETで送り、NOTIFYに切り替えていない"),
    "OnSessionLock": ("✅", "macOSユーザーセッションが非アクティブになった時に通知。実機ロックでの実動未確認"),
    "OnSessionUnlock": ("✅", "macOSユーザーセッションが再びアクティブになった時に通知。実機ロック解除での実動未確認"),
    "OnSNTPBegin": ("✅", "時計合わせ開始時に接続先サーバをReference0へ通知。共通イベント生成をテスト済み"),
    "OnSNTPCompareEx": ("✅", "取得時刻・ローカル時刻・符号付き秒差／ミリ秒差をReference0〜4へ通知。時刻比較とイベント生成をテスト済み"),
    "OnSNTPCompare": ("✅", "CompareExが無応答の時に従来形式へフォールバックし、絶対値の秒差／ミリ秒差を通知。時刻比較とイベント生成をテスト済み"),
    "OnSNTPFailure": ("✅", "HTTP接続・応答・Date解析の失敗時に接続先サーバをReference0へ通知。共通イベント生成をテスト済み"),
    "OnCPULoadHigh": ("✅", "OS全体のCPU使用率が80%以上で5秒間隔3回続いた時に現在率をReference0へ通知。状態遷移テストで確認"),
    "OnCPULoadLow": ("✅", "CPU High通知後に使用率が60%未満へ戻った時、現在率をReference0へ通知。状態遷移テストで確認"),
    "OnMemoryLoadHigh": ("✅", "VM統計のメモリ使用率が80%以上で5秒間隔3回続いた時に現在率をReference0へ通知。状態遷移テストで確認"),
    "OnMemoryLoadLow": ("✅", "Memory High通知後に使用率が60%未満へ戻った時、現在率をReference0へ通知。状態遷移テストで確認"),
    "OnDisplayChange": ("✅", "画面構成変更時にプライマリ画面のbpp・幅・高さをReference0〜2へ通知。起動時NOTIFYは未対応"),
    "OnDestroy": ("✅", "ゴースト終了処理でOnCloseより前にNOTIFY。リロード時のReference0=reloadは未対応"),
    "OnVanishSelecting": ("✅", "コンテンツエクスプローラまたは確認付きvanishbymyselfから、確認画面を出す前に発行。実画面での一連操作は未確認"),
    "OnVanishSelected": ("✅", "確認後または即時vanishbymyselfで、SHIORI終了前に発行して応答スクリプトを再生。実画面での一連操作は未確認"),
    "OnVanishCancel": ("✅", "消滅確認をキャンセルした時に発行して応答スクリプトを再生。実画面での一連操作は未確認"),
    "OnVanished": ("✅", "消滅後の切り替え先へ消滅元の本体名・最終スクリプト・ゴースト名と切替先シェル名をReference0〜2・7で通知し、無応答ならOnBootへフォールバック。テスト済み"),
    "OnOtherGhostVanished": ("✅", "呼び出しゴーストの消滅後、他の起動中ゴーストへReference0〜2・7を発行し、204時はOnVanishedへフォールバック。実画面での一連操作は未確認"),
    "OnDarkTheme": ("✅", "起動時とアプリ再アクティブ化時にmacOSのダークモード状態をReference0〜1へ通知。非アクティブ中の変更は復帰時通知"),
    "OnDesktopWallpaperChange": ("✅", "起動時はNOTIFY、macOSの壁紙変更時はGETで、画面・画像パス・表示方法・背景色を通知。状態遷移とReferenceを自動テスト済み"),
    "OnMinuteChange": ("✅", "分の変化ごとにReference0〜4を通知。会話不能時は応答を無視するがSHIORIメソッドはGETのまま"),
    "OnHourTimeSignal": ("✅", "正時後、会話可能になるまで保留してReference0〜4を通知。実時間での実動未確認"),
    "OnInitialize": ("✅", "SHIORIセッション開始直後、OnBootまたはOnGhostCalledより前にNOTIFY。リロード時のReference0=reloadは未対応"),
    "OnLanguageChange": ("✅", "起動時に現在の言語名とLocale IDをReference0〜1へ通知。実行中の言語変更監視とUtatane言語フォルダ・ヘルプURLは未対応"),
    "OnShellChanged": ("✅", "切替後に現シェル名・ゴースト名・シェルパスをReference0〜2へ通知。イベント生成テストで確認"),
    "OnShellChanging": ("✅", "切替前に新旧シェル名と新シェルパスをReference0〜2へ通知。イベント生成テストで確認"),
    "OnSurfaceRestore": ("✅", "会話消去時に現在surfaceをReference0〜1へ通知。UKADOCのバルーン消去後15秒という発生時刻とは異なる"),
    "OnSurfaceChange": ("✅", "SakuraScript等でsurfaceが変わった時に本体側・相方側の現在IDをReference0〜1へ通知。NOTIFYメソッドの区別は未対応"),
    "OnAnchorSelect": ("✅", "OnAnchorSelectExがスクリプトを返さない場合のみアンカーIDをReference0へ通知。メイン・呼び出しゴーストの両経路で対応"),
    "OnAnchorSelectEx": ("✅", "アンカーの表示ラベル・ID・追加引数をReference0以降へ通知し、非空応答時はOnAnchorSelectを抑止。応答は割り込み再生"),
    "OnSysResume": ("✅", "macOSのスリープ復帰通知でReference0=normalを発行。自動復帰理由autoの判定は未対応"),
    "OnSysSuspend": ("✅", "macOSがスリープへ入る直前にNOTIFY。実機スリープでの実動未確認"),
    "OnTeach": ("✅", "同一ゴーストセッション中の入力履歴をReference0から順に通知。イベント生成テストで確認"),
    "OnTeachInputCancel": ("✅", "TeachBoxをキャンセルまたは閉じた時に空のReference0とReference1=cancelを通知。イベント生成テストで確認"),
    "OnTeachStart": ("✅", "TeachBoxを表示する直前にReferenceなしで通知。イベント生成テストで確認"),
    "OnUpdateProcessExec": ("✅", "更新指示時にmanual・auto・scriptを通知し、応答スクリプトがあれば標準更新を中止。イベント生成テストで確認"),
    "OnUpdateBegin": ("✅", "ゴースト名・フルパス・ghost・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認"),
    "OnUpdateReady": ("✅", "更新対象の最終番号・ファイル名一覧・ghost・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認"),
    "OnUpdateComplete": ("✅", "none／changed・変更ファイル一覧・ghost・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認"),
    "OnUpdateFailure": ("✅", "分類した失敗理由・失敗ファイル・ghost・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認"),
    "OnUpdate.OnDownloadBegin": ("✅", "取得前にファイル名・0始まり番号・最終番号・ghost・更新理由をReference0〜4へ通知。イベント生成テストで確認"),
    "OnUpdate.OnMD5CompareBegin": ("✅", "照合前にファイル名・期待値・実測MD5・ghost・更新理由をReference0〜4へ通知。イベント生成テストで確認"),
    "OnUpdate.OnMD5CompareComplete": ("✅", "MD5一致時にファイル名・期待値・実測値・ghost・更新理由をReference0〜4へ通知。イベント生成テストで確認"),
    "OnUpdate.OnMD5CompareFailure": ("✅", "MD5不一致時にファイル名・期待値・実測値・ghost・更新理由をReference0〜4へ通知して更新を中断。イベント生成テストで確認"),
    "OnUpdateOtherBegin": ("✅", "ゴースト以外の更新開始時に名前・フルパス・対象種別・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認"),
    "OnUpdateOtherReady": ("✅", "更新対象の最終番号・ファイル名一覧・対象種別・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認"),
    "OnUpdateOtherComplete": ("✅", "none／changed・変更ファイル一覧・対象種別・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認"),
    "OnUpdateOtherFailure": ("✅", "分類した失敗理由・失敗ファイル・対象種別・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認"),
    "OnUpdateOther.OnDownloadBegin": ("✅", "取得前にファイル名・0始まり番号・最終番号・対象種別・更新理由をReference0〜4へ通知。イベント生成テストで確認"),
    "OnUpdateOther.OnMD5CompareBegin": ("✅", "照合前にファイル名・期待値・実測MD5・対象種別・更新理由をReference0〜4へ通知。イベント生成テストで確認"),
    "OnUpdateOther.OnMD5CompareComplete": ("✅", "MD5一致時に期待値・実測値・対象種別・更新理由をReference1〜4へ通知。イベント生成テストで確認"),
    "OnUpdateOther.OnMD5CompareFailure": ("✅", "MD5不一致時に期待値・実測値・対象種別・更新理由をReference1〜4へ通知して更新を中断。イベント生成テストで確認"),
    "OnUpdateCheckComplete": ("✅", "更新チェック成功時にnone／changed・対象ファイル一覧・対象種別・Reference4=scriptを通知。イベント生成テストで確認"),
    "OnUpdateCheckFailure": ("✅", "更新チェック失敗時に分類した失敗理由とReference4=scriptを通知。イベント生成テストで確認"),
    "OnUpdateResult": ("✅", "複数対象の名前・種別・成否・件数または失敗理由・失敗パスを順番どおりReference0以降へ集約し、Exが無応答の時に通知。イベント生成テストで確認"),
    "OnUpdateResultEx": ("✅", "複数対象の名前・種別・成否・件数または失敗理由・失敗パスを順番どおりReference0以降へ集約して通知。イベント生成テストで確認"),
    "OnUpdateCheckResult": ("✅", "複数対象の更新チェック結果を順番どおりReference0以降へ集約し、Exが無応答の時に通知。イベント生成テストで確認"),
    "OnUpdateCheckResultEx": ("✅", "複数対象の更新チェック結果を順番どおりReference0以降へ集約して通知。イベント生成テストで確認"),
    "OnUpdateResultExplorer": ("✅", "コンテンツエクスプローラからの単体・一括更新と修復の結果を旧形式でReference0以降へ集約して通知。イベント生成テストで確認"),
    "OnRecommendsiteChoice": ("✅", "おすすめ・ポータルメニュー選択時にサイト名・URL・バナー・種別・選択scope・0始まりの位置をReference0〜5へ通知。イベント生成テストで確認"),
    "OnUserInput": ("✅", "Onで始まらないInputBox IDの決定時にID・入力内容・補足・追加Referenceを通知"),
    "OnUserInputCancel": ("✅", "InputBoxをキャンセル・閉じた時はclose、時間切れ時はtimeoutを理由としてID・補足とともに通知"),
    "OnWindowStateMinimize": ("✅", "macOSでアプリが非表示になった時にReference0=systemを通知。script・user理由の区別は未対応"),
    "OnWindowStateRestore": ("✅", "macOSでアプリの非表示が解除された時にReference0=systemを通知。script・user理由の区別は未対応"),
    "OnDisplayHandover": ("✅", "シェル位置の初期化時と別スクリーンへの移動時に、scopeと移動前後の画面座標・色深度・主画面フラグを通知"),
}

AUDITED_EVENTS.update({
    "configuredbiffname": ("✅", "起動時に本体設定で利用可能なPOP3アカウント名をNOTIFY。パスワードはmacOS Keychainへ保存"),
    "OnOtherGhostChanged": ("✅", "呼び出しゴーストの切替時に切替前後の本体名・ゴースト名・パス・シェル名を、メインと他の呼び出しゴーストへ通知"),
    "OnCacheSuspend": ("✅", "呼び出しゴーストを右クリックメニューから休止する前に発行し、ウインドウを非表示化"),
    "OnCacheRestore": ("✅", "休止中の呼び出しゴーストをメニューから復帰した後に発行"),
    "OnBasewareUpdating": ("✅", "Sparkleが更新をインストールする直前に旧バージョンとビルド番号を通知"),
    "OnBasewareUpdated": ("✅", "更新後の初回起動で保存済みの旧版情報と現在版情報を通知"),
    "OnConfigurationDialogHelp": ("✅", "本体設定のヘルプボタンから現在の設定ページIDを通知"),
    "OnGhostTermsAccept": ("✅", "terms.txtの利用規約ダイアログで同意した時に通知。UTF-8とShift_JISを読込"),
    "OnGhostTermsDecline": ("✅", "terms.txtの利用規約ダイアログで拒否した時に通知"),
    "OnVanishButtonHold": ("✅", "OnVanishSelected再生中のバルーンをダブルクリックした時にスクリプト・scope・表示文字位置を通知し、再生と消滅処理を取り消す"),
    "OnBalloonBreak": ("✅", "通常トークを別のトークが置き換える時にスクリプト・scope・表示文字位置を通知。生SakuraScriptのバイト位置とは一致しない場合あり"),
    "OnWallpaperChange": ("✅", "画像をサーフェスへドロップして全macOS画面の壁紙変更に成功した時に画像パスを通知"),
    "OnBIFFBegin": ("✅", "biffコマンドによるPOP3メールチェック開始時に設定アカウント名を通知"),
    "OnBIFFComplete": ("✅", "POP3 STAT成功時に通数・総バイト数・アカウント名・前回との差分を通知。LIST・UIDL・ヘッダ一覧は空欄"),
    "OnBIFF2Complete": ("✅", "新着がありOnBIFFCompleteが無応答だった場合に通数・総バイト数・アカウント名を通知"),
    "OnBIFFFailure": ("✅", "POP3設定不足・接続・認証・応答解析失敗を理由とアカウント名付きで通知"),
    "OnExecuteHTTPProgress": ("✅", "progress-notify指定時に受信済みバイト数と期待総量をデータ受信ごとに通知"),
    "OnExecuteHTTPStreaming": ("✅", "streaming指定時に改行単位の受信データを通知"),
    "OnExecuteHTTPSSLInfo": ("✅", "HTTPS通信のTLSバージョン・暗号スイート・証明書概要をURLSession metricsから通知。証明書日時は空欄"),
    "OnExecuteRSS_SSLInfo": ("✅", "HTTPSのRSS取得時にHTTPと同じTLS情報を通知。証明書日時は空欄"),
    "OnExecuteWebSocketReconnect": ("✅", "WebSocket受信失敗後の自動再接続を最大5回行い、試行回数を通知"),
    "OnExecuteWebSocket_SSLInfo": ("✅", "wss接続のTLSバージョンと暗号スイートを通知。証明書subject・issuerは空欄"),
    "OnPingProgress": ("✅", "pingの応答行ごとに指定イベントID・ホスト・応答番号・解析した遅延を通知"),
    "OnOSUpdateInfo": ("✅", "macOSのsystem_profilerインストール履歴から直近20件の名称・版・導入日を起動時に通知。Windows固有項目は空欄"),
    "OnRecycleBinEmpty": ("✅", "emptyrecyclebinでユーザーの~/.Trashを空にし、前後の件数・容量と成否を通知"),
    "OnRecycleBinEmptyFromOther": ("✅", "他ゴーストがemptyrecyclebinを実行した時に同じ結果を通知"),
    "OnSelectModeBegin": ("✅", "enter,selectrectで全画面の矩形選択オーバーレイを開始して通知"),
    "OnSelectModeCancel": ("✅", "selectrectをEscまたは選択未完了で終了した時に通知"),
    "OnSelectModeComplete": ("✅", "leave,selectrectで選択矩形の画面座標を通知"),
    "OnSelectModeMouseDown": ("✅", "矩形選択開始点をクリックした時にscope・モード・画面座標を通知"),
    "OnSelectModeMouseUp": ("✅", "矩形選択終了点でボタンを離した時にscope・モード・画面座標を通知"),
    "OnTranslate": ("✅", "イベント応答の再生前に元スクリプト・イベントID・Reference等で同じSHIORIを再呼出しし、応答があれば置換"),
    "OnOtherGhostTalk": ("✅", "set,otherghosttalkでopt-inしたゴーストへ他ゴーストの再生前または再生後のスクリプトと発生元情報を通知"),
    "property.get": ("✅", "activeghostlist.extの対象ゴーストへ拡張プロパティ取得を中継"),
    "property.set": ("✅", "activeghostlist.extの対象ゴーストへ拡張プロパティ設定を中継"),
})

PARTIAL_EVENTS = {
    "OnGhostChanging",
    "OnGhostCalling",
    "OnDressupChanged",
    "OnWindowStateRestore",
    "OnWindowStateMinimize",
    "OnInitialize",
    "OnDestroy",
    "OnSysResume",
    "OnSurfaceChange",
    "OnMouseWheel",
    "OnMouseEnter",
    "OnMouseLeave",
    "OnMouseDragStart",
    "OnMouseDragEnd",
    "OnMouseGesture",
    "OnMouseMove",
    "OnGamepadButtonDown",
    "OnGamepadButtonUp",
    "OnGamepadAxisMove",
    "OnBalloonBreak",
    "OnUpdatedataCreating",
    "OnNarCreating",
    "OnURLDragDropping",
    "OnURLDropping",
    "OnURLQuery",
    "OnBIFFComplete",
    "OnScheduleRead",
    "OnSchedulesenseBegin",
    "OnSSTPBreak",
    "OnExecuteHTTPSSLInfo",
    "OnExecuteRSS_SSLInfo",
    "OnExecuteWebSocket_SSLInfo",
    "OnPingComplete",
    "OnRaiseOtherFailure",
    "OnNotifyOtherFailure",
    "OnNetworkHeavy",
    "OnDisplayChange",
    "OnDisplayChangeEx",
    "OnLanguageChange",
    "OnResetWindowPos",
    "capability",
    "rateofusegraph",
    "OnNotifyBalloonInfo",
    "OnNotifyDressupInfo",
    "OnNotifyFontInfo",
}

# An event belongs here when Utatane has no usable automatic emission path.
# Keep it separate from PARTIAL_EVENTS so the published table distinguishes an
# incomplete contract from a wholly unavailable event.
UNIMPLEMENTED_EVENTS = {
    "OnSNTPCorrectEx": "`\\6`の要求は受理するが、macOSのシステム時刻を実際に補正する経路がなく、成功イベントは発行されない",
    "OnSNTPCorrect": "OnSNTPCorrectExからのフォールバック処理はあるが、実補正の成功経路がないため発行されない",
}

PARTIAL_EVENT_NOTES = {
    "OnDisplayChangeEx": "画面構成変更時にupdateと全画面の矩形・色深度・プライマリ判定を通知。macOSにはタスクバーがないため末尾はunknown,0。起動時initは未対応",
    "OnMouseGesture": "右ボタンまたはホイールの8方向ドラッグと終了を、scope・現在位置／開始位置・各collision・角度とともに通知。circle.cw／circle.ccwは未対応",
    "OnNarCreating": "`createnar`実行直前にinstall.txt由来の名前、出力絶対パス、識別子をReference0〜2へ通知。フォルダD&Dからの作成UIは未実装",
    "OnNetworkHeavy": "SakuraScriptのHTTP/RSS要求が設定時間でタイムアウトした時、設定秒数と経過秒数を通知。HEADLINEや更新通信は未接続",
    "OnSSTPBreak": "nobreakなしの新しいSSTPが再生中SSTPを中断する際に発行。Reference0は中断スクリプト、Reference1は0。Reference2は現在0固定",
    "OnScheduleRead": "カレンダー詳細の「予定を読む」からReference0〜3を通知。スキンアイコンのホバー読み上げは未実装",
    "OnURLQuery": "URL・scope・推定MIME type・nar/unknownを通知し、スクリプト応答時は標準処理を中止。feed・homeurl判定は未対応",
    "OnUpdatedataCreating": "`createupdatedata`による`updates2.dau`生成の直前にReferenceなしで通知。フォルダD&Dからの作成UIは未実装",
}

INAPPLICABLE_EVENTS = {
    "OnFileDropped": "旧仕様のため対象外。複数項目とMIME typeを扱えるOnFileDrop2を発行",
    "OnFileDrop": "旧仕様のため対象外。複数項目とMIME typeを扱えるOnFileDrop2を発行",
    "OnFileDropEx": "旧仕様のため対象外。複数項目とMIME typeを扱えるOnFileDrop2を発行",
    "OnTabletMode": "macOSに対応するタブレットモードがないため対象外",
    "OnEmbryoExist": "Windows用Materiaの同時起動検出イベントでありmacOS版では対象外",
    "OnNekodorifExist": "Windows用猫どりふの同時起動検出イベントでありmacOS版では対象外",
    "OnOtherObjectDropping": "Windows Shellの仮想オブジェクトを表すイベント。macOSのファイル・URL・テキストDnDは各専用イベントで処理",
    "OnOtherObjectDropped": "Windows Shellの仮想オブジェクトを表すイベント。macOSのファイル・URL・テキストDnDは各専用イベントで処理",
    "OnSSTPBlacklisting": "UKADOCではMateria専用の送信元ブラックリストイベントであり、SSP互換対象外",
}

ONLINE_ADDITIONAL_EVENTS = [
    "OnScheduleTodayNotify",
    "OnDesktopWallpaperChange",
    "OnWindowModeChange",
    "installedcalendarskinname",
    "installedcalendarpluginname",
    "OnExecuteICalComplete",
    "OnExecuteICalFailure",
    "OnExecuteICalProgress",
    "OnExecuteICal_SSLInfo",
    "OnExecuteScheduleComplete",
    "OnExecuteScheduleFailure",
    "OnExecuteScheduleGetComplete",
    "OnExecuteFileWatchChange",
    "OnExecuteFileWatchFailure",
]

ONLINE_ADDITIONAL_AUDITED_EVENTS = {
    "OnScheduleTodayNotify": ("✅", "予定の追加・編集・削除・取り込みや日付変更で今日の予定が変化した時、全起動ゴーストへNOTIFY"),
    "OnDesktopWallpaperChange": AUDITED_EVENTS["OnDesktopWallpaperChange"],
    "OnWindowModeChange": ("✅", "起動時とウインドウモード切替時に現在・直前のモードを通知し、切替時はOnDisplayChangeも発行"),
    "installedcalendarskinname": AUDITED_EVENTS["installedcalendarskinname"],
    "installedcalendarpluginname": AUDITED_EVENTS["installedcalendarpluginname"],
    "OnExecuteICalComplete": ("✅", "ical-get／ical-postで取得したiCalendarを解析し、カレンダー情報とVEVENTをReference列へ通知。主要フィールドと件数制限に対応"),
    "OnExecuteICalFailure": ("✅", "iCalendarの通信・HTTP・解析失敗をHTTP系と同じReference形式で通知"),
    "OnExecuteICalProgress": ("✅", "--progress-notify指定時にiCalendar取得の進捗を通知"),
    "OnExecuteICal_SSLInfo": ("✅", "HTTPSでiCalendarを取得した時にTLS情報を通知"),
    "OnExecuteScheduleComplete": ("✅", "schedule-add／schedule-deleteで共有予定表への登録・削除が完了した時に操作種別とUIDを通知"),
    "OnExecuteScheduleFailure": ("✅", "schedule-add／schedule-deleteの入力不正・対象なしを理由とUID付きで通知"),
    "OnExecuteScheduleGetComplete": ("✅", "schedule-getで共有予定表をiCalendarと同じReference形式で通知"),
    "OnExecuteFileWatchChange": ("✅", "filewatchで指定したファイルまたはディレクトリの作成・更新・削除をdebounce後に通知"),
    "OnExecuteFileWatchFailure": ("✅", "filewatchの監視先ディレクトリがない場合や監視を継続できない場合に理由を通知"),
}

HIGH_DIFFICULTY_CATEGORIES = {
    "メールチェックイベント": "メールアカウント設定・通信機能",
    "カレンダーイベント": "カレンダー／スケジュール機能",
    "音声認識・合成イベント": "音声認識・音声合成機能",
}

MEDIUM_DIFFICULTY_CATEGORIES = {
    "ゲームパッドイベント": "ゲームパッド監視",
    "時計合わせイベント": "時刻同期機能",
    "ネットワーク状態イベント": "ネットワーク状態監視",
    "OS状態イベント": "macOS状態監視",
    "ファイルドロップイベント": "ドラッグ＆ドロップ／関連UI",
    "URLドロップイベント": "URLドラッグ＆ドロップ",
    "選択領域モードイベント": "画面領域選択UI",
}

LOW_DIFFICULTY_CATEGORIES = {
    "入力ボックスイベント": "既存入力UIへの通知追加",
    "時間イベント": "既存タイマーへの通知追加",
    "選択肢イベント": "既存選択肢UIへの通知追加",
    "サーフェスイベント": "既存サーフェス処理への通知追加",
    "マウスイベント": "既存マウス処理への通知追加",
    "バルーンイベント": "既存バルーン処理への通知追加",
}


def implementation_metadata(title: str, event_id: str) -> tuple[str, str]:
    if event_id in INAPPLICABLE_EVENTS:
        return "—", "—"
    if event_id in UNIMPLEMENTED_EVENTS:
        return "イベント発生元の本体機能", "中"
    if event_id in PARTIAL_EVENTS:
        return "イベント発生元の本体機能", "中"
    if event_id in AUDITED_EVENTS:
        if AUDITED_EVENTS[event_id][0] == "✅":
            return "—", "—"
        return "通知経路のUKADOC照合", "低"
    if event_id.startswith(("OnCPULoad", "OnMemoryLoad")):
        return "CPU・メモリ使用率の定期監視", "低"
    if title in HIGH_DIFFICULTY_CATEGORIES:
        return HIGH_DIFFICULTY_CATEGORIES[title], "高"
    if title in MEDIUM_DIFFICULTY_CATEGORIES:
        return MEDIUM_DIFFICULTY_CATEGORIES[title], "中"
    if title in LOW_DIFFICULTY_CATEGORIES:
        return LOW_DIFFICULTY_CATEGORIES[title], "低"
    return "イベント発生元の本体機能", "中"


def strip_tags(value: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", value)).strip()


def toc_sections(source: str) -> list[tuple[str, list[str]]]:
    # The first event definition marks the end of UKADOC's table of contents.
    toc = source.split('<dl id="', 1)[0]
    tokens = re.findall(
        r"<h1[^>]*>(.*?)</h1>|<li><a href=\"#([^\"]+)\"[^>]*>.*?</a></li>",
        toc,
        flags=re.DOTALL,
    )
    sections: list[tuple[str, list[str]]] = []
    current: tuple[str, list[str]] | None = None
    for heading, event_id in tokens:
        if heading:
            title = strip_tags(heading)
            if title and title not in {"SHIORI Event", "Ghost Status"}:
                current = (title, [])
                sections.append(current)
        elif event_id and current is not None:
            current[1].append(html.unescape(event_id))
    return [(title, ids) for title, ids in sections if ids]


def render(ukadoc_file: Path) -> str:
    sections = toc_sections(ukadoc_file.read_text(encoding="utf-8"))
    seen: set[str] = set()
    unique_sections: list[tuple[str, list[str]]] = []
    for title, event_ids in sections:
        unique_ids = []
        for event_id in event_ids:
            if event_id not in seen:
                unique_ids.append(event_id)
                seen.add(event_id)
        if unique_ids:
            unique_sections.append((title, unique_ids))
    missing_online_events = [event_id for event_id in ONLINE_ADDITIONAL_EVENTS if event_id not in seen]
    if missing_online_events:
        unique_sections.append(("オンラインUKADOC追加イベント", missing_online_events))
    sections = unique_sections
    event_count = len(seen) + len(missing_online_events)
    status_counts = {status: 0 for status in ("✅", "🟡", "❌", "➖")}
    for _, event_ids in sections:
        for event_id in event_ids:
            if event_id in ONLINE_ADDITIONAL_AUDITED_EVENTS:
                status = ONLINE_ADDITIONAL_AUDITED_EVENTS[event_id][0]
            elif event_id in AUDITED_EVENTS:
                status = AUDITED_EVENTS[event_id][0]
            elif event_id in UNIMPLEMENTED_EVENTS:
                status = "❌"
            elif event_id in PARTIAL_EVENTS:
                status = "🟡"
            elif event_id in INAPPLICABLE_EVENTS:
                status = "➖"
            else:
                status = "❌"
            status_counts[status] += 1
    lines = [
        "# UKADOC SHIORIイベント互換状況",
        "",
        "ゴーストへ送るSHIORIイベントについて、Utataneが通知する条件と、SSPとの違いをまとめています。",
        "項目名と分類の生成には`Scripts/generate-shiori-event-compatibility.py`と、ローカルに保存したUKADOCを使います。各行の判定と備考は、実装や確認結果に合わせて更新します。",
        "",
        "基準: [SHIORI Eventリスト](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html)",
        "",
        f"UKADOC掲載イベント数: {event_count}",
        "調査日: 2026-09-20",
        f"調査結果: ✅ {status_counts['✅']} / 🟡 {status_counts['🟡']} / ❌ {status_counts['❌']} / ➖ {status_counts['➖']}",
        "",
        "## 判定",
        "",
        "| 記号 | 意味 |",
        "| --- | --- |",
        "| ✅ | 発生条件・Reference・応答処理を実装。実機未確認やmacOS固有差は備考に記載 |",
        "| 🟡 | 発行経路はあるが、実装可能な発生条件・Reference・応答処理の一部が未対応 |",
        "| ❌ | Utataneから自動発行する実装がない |",
        "| ➖ | Windows固有などmacOSでは非該当、旧仕様に置き換え済み、または現行UKADOCで契約未定義 |",
        "",
        "名前がソースに現れるだけでは対応としません。発生条件・Reference・GET/NOTIFY・応答利用をUKADOCに照らし、契約を満たすものは✅、一部不足は🟡、自動発行経路がないものは❌に分類します。",
        "任意IDを中継できる経路（raise、inputbox、HTTP等）は、そのイベントをベースウェアが自動発行する実装とは数えません。",
        "全イベントを本番Swiftコード（テストコードを除く）の固定IDおよびイベント生成経路と照合します。✅のmacOS固有差と実機確認状況は備考に残します。",
        "➖はWindows固有機能、旧仕様、または現行UKADOCで契約を実装できない根拠を備考へ記録します。Utatane側の機能不足だけを理由に➖へ分類しません。",
        "",
    ]
    for title, event_ids in sections:
        lines.extend([
            f"## {title}",
            "",
            "| イベント | 状況 | Utataneの挙動・差分 |",
            "| --- | --- | --- |",
        ])
        for event_id in event_ids:
            link = f"https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#{event_id}"
            if event_id in ONLINE_ADDITIONAL_AUDITED_EVENTS:
                status, note = ONLINE_ADDITIONAL_AUDITED_EVENTS[event_id]
            elif event_id in AUDITED_EVENTS:
                status, note = AUDITED_EVENTS[event_id]
            elif event_id in UNIMPLEMENTED_EVENTS:
                status = "❌"
                note = UNIMPLEMENTED_EVENTS[event_id]
            elif event_id in PARTIAL_EVENTS:
                status = "🟡"
                note = AUDITED_EVENTS.get(
                    event_id,
                    ("🟡", PARTIAL_EVENT_NOTES[event_id]),
                )[1]
            elif event_id in INAPPLICABLE_EVENTS:
                status = "➖"
                note = INAPPLICABLE_EVENTS[event_id]
            else:
                status = "❌"
                note = "本番コードにベースウェアからの自動発行経路なし"
            lines.append(
                f"| [`{event_id}`]({link}) | {status} | {note} |"
            )
        lines.append("")
    lines.extend([
        "## 更新ルール",
        "",
        "- 実装または調査時に、発生条件・Reference・GET/NOTIFY・応答利用の4点を確認します。",
        "- ✅へ変更する場合は、テストまたは実機確認の根拠を備考に残します。",
        "- UKADOC側の増減確認には生成スクリプトを使い、既存の手動判定を上書きしないよう差分を確認します。",
        "- 外部からのSHIORI EventとSHIORI Resourceは、この表とは分けて管理します。",
        "",
    ])
    return "\n".join(lines)


def merge_audited_rows(existing: str, generated: str, ukadoc_file: Path) -> str:
    audited_rows: dict[str, str] = {}
    for line in existing.splitlines():
        match = re.match(r"\| \[`([^`]+)`\]", line)
        if match:
            audited_rows[match.group(1)] = line

    known_events = {
        event_id
        for _, event_ids in toc_sections(ukadoc_file.read_text(encoding="utf-8"))
        for event_id in event_ids
    } | set(ONLINE_ADDITIONAL_EVENTS)
    merged: list[str] = []
    statuses: dict[str, str] = {}
    for line in generated.splitlines():
        match = re.match(r"\| \[`([^`]+)`\]", line)
        if match:
            event_id = match.group(1)
            if event_id in audited_rows:
                line = audited_rows[event_id]
            if event_id in known_events:
                status = re.search(r"\| (✅|🟡|❌|➖) \|", line)
                if status:
                    statuses[event_id] = status.group(1)
        merged.append(line)

    counts = {status: list(statuses.values()).count(status) for status in ("✅", "🟡", "❌", "➖")}
    total_line = (
        f"調査結果: ✅ {counts['✅']} / 🟡 {counts['🟡']} / "
        f"❌ {counts['❌']} / ➖ {counts['➖']}"
    )
    merged = [total_line if line.startswith("調査結果:") else line for line in merged]
    return "\n".join(merged) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ukadoc", type=Path, help="path to UKADOC's list_shiori_event.html")
    parser.add_argument("output", type=Path, help="Markdown output path")
    args = parser.parse_args()
    generated = render(args.ukadoc)
    if args.output.exists():
        generated = merge_audited_rows(args.output.read_text(encoding="utf-8"), generated, args.ukadoc)
    args.output.write_text(generated, encoding="utf-8")


if __name__ == "__main__":
    main()
