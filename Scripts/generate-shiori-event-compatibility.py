#!/usr/bin/env python3
"""Generate the SHIORI Event inventory from a local UKADOC checkout."""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path


AUDITED_EVENTS = {
    "hwnd": ("✅", "起動時に各scopeのNSWindow番号をバイト値1区切りでNOTIFY。macOSではWindows HWNDの代わりにwindowNumberを通知し、未生成バルーンは空欄"),
    "otherghostname": ("✅", "起動時に呼び出し起動中の他ゴースト名とscope 0/1のsurface番号をバイト値1区切りでNOTIFY。通常起動側から見える呼出ゴーストのみ"),
    "installedplugin": ("✅", "起動時に空のNOTIFYを送り、プラグインがインストールされていない状態を通知。プラグイン機能自体は未実装"),
    "configuredbiffname": ("✅", "起動時に空のNOTIFYを送り、設定済みメールアカウントがない状態を通知。メールチェック機能自体は未実装"),
    "pluginpathlist": ("✅", "起動時に空のNOTIFYを送り、プラグイン格納パスがない状態を通知。プラグイン機能自体は未実装"),
    "calendarskinpathlist": ("✅", "起動時に空のNOTIFYを送り、カレンダースキン格納パスがない状態を通知。カレンダー機能自体は未実装"),
    "calendarpluginpathlist": ("✅", "起動時に空のNOTIFYを送り、カレンダープラグイン格納パスがない状態を通知。カレンダー機能自体は未実装"),
    "rateofusegraph": ("✅", "起動中ゴーストをboot状態の1レコードとしてNOTIFY。起動回数・時間・割合は0固定で履歴集計は未実装"),
    "enable_log": ("✅", "起動時にUtataneのアプリ内ログが有効であることをReference0=1でNOTIFY。SSP開発パレット相当の切替UIは未実装"),
    "enable_debug": ("✅", "起動時にDebugビルドなら1、Releaseなら0をReference0へNOTIFY。実行中の切替UIは未実装"),
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
    "OnBalloonScaling": ("✅", "設定でバルーン倍率が変わった時に新旧の縦横パーセントをReference0〜3へ通知。縦横個別設定は未実装"),
    "OnChoiceEnter": ("✅", "選択肢への出入りでラベル・ID・追加引数を通知し、外れた時はReferenceなし。Playerテストで確認"),
    "OnChoiceHover": ("✅", "選択肢上で1秒静止した時にラベル・ID・追加引数を通知。SSPの静止時間との完全一致は未確認"),
    "OnShellScaling": ("✅", "設定でシェル倍率が変わった時に新旧の縦横パーセントをReference0〜3へ通知。縦横個別設定は未実装"),
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
    "OnCommunicate": ("✅", "他ゴースト連携と入力Boxの両経路で送信元をReference0、本文をReference1へ通知。キャンセル系は未対応"),
    "OnCommunicateInputCancel": ("✅", "CommunicateBoxをキャンセルまたは閉じた時に空のReference0とReference1=cancelを通知。イベント生成テストで確認"),
    "OnCompressArchiveComplete": ("✅", "実際のZIP圧縮成功後にファイル・出力先・形式・ユーザーIDをReference0〜3へ通知。圧縮処理とイベント生成をテスト済み"),
    "OnCompressArchiveFailure": ("✅", "ZIP圧縮失敗時に対象ファイルとエラー内容をReference0〜1へ通知。失敗経路とイベント生成をテスト済み"),
    "OnDressupChanged": ("✅", "scriptによるbind変更とReference0〜4を実装。複数変更時のNOTIFY/最後だけGET規則は未対応"),
    "OnExecuteHTTPComplete": ("✅", "取得成功時に小文字のメソッド・識別ID・URL・本文または保存先・HTTPコード・Cookie・全ヘッダをReference0〜6へ通知。標準／独自イベントIDをテスト済み"),
    "OnExecuteHTTPFailure": ("✅", "HTTPステータス、timeout、fileio、artificial、toomanyredirect等をReference4へ入れ、Completeと同じReference0〜6で通知。イベント生成をテスト済み"),
    "OnExecuteRSSComplete": ("✅", "RSS各項目をタイトル・URL・SSP形式日時・作者・要約のバイト値1区切りでReference0以降へ通知。標準／独自イベントIDをテスト済み"),
    "OnExecuteRSSFailure": ("✅", "解析失敗はReference4=parse、通信失敗はHTTPと同じReference0〜6で通知。標準／独自イベントIDをテスト済み"),
    "OnExecuteWebSocketClose": ("✅", "close code・userbreakを通知。自動再接続と再接続後の最終Close規則は未実装"),
    "OnExecuteWebSocketFailure": ("✅", "接続・受信エラーを通知。UKADOCの5回自動再接続後Failureは未実装"),
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
    "OnOtherSurfaceChange": ("✅", "他の実行中ゴーストへ本体名・Sakura名・scope・新旧surface・矩形をReference0〜5で通知。othersurfacechange無効化設定は未対応"),
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
    "OnUserInput": ("✅", "Onで始まらないInputBox IDの決定時にID・入力内容・空の補足をReference0〜2へ通知。追加reference等は未対応"),
    "OnUserInputCancel": ("✅", "InputBoxをキャンセルまたは閉じた時にID・close・空の補足をReference0〜2へ通知。タイムアウト理由は未対応"),
    "OnWindowStateMinimize": ("✅", "macOSでアプリが非表示になった時にReference0=systemを通知。script・user理由の区別は未対応"),
    "OnWindowStateRestore": ("✅", "macOSでアプリの非表示が解除された時にReference0=systemを通知。script・user理由の区別は未対応"),
}

# Events whose trigger belongs to an SSP/Windows-only facility or to a feature
# Utatane intentionally does not provide. Keeping these explicit prevents a
# missing fixed event ID from being mistaken for an unaudited implementation.
UNSUPPORTED_EVENTS = {
    "OnOtherGhostChanged": "Utataneは呼び出しゴースト同士を直接切り替える操作を提供しないため対象外",
    "OnCacheSuspend": "SSPのキャッシュ休止機能を提供しないため対象外",
    "OnCacheRestore": "SSPのキャッシュ復帰機能を提供しないため対象外",
    "OnBasewareUpdating": "実行中のベースウェア自己更新を提供しないため対象外",
    "OnBasewareUpdated": "実行中のベースウェア自己更新を提供しないため対象外",
    "OnConfigurationDialogHelp": "SSP形式の設定ダイアログ拡張ヘルプを提供しないため対象外",
    "OnGhostTermsAccept": "SSP形式のゴースト利用規約ダイアログを提供しないため対象外",
    "OnGhostTermsDecline": "SSP形式のゴースト利用規約ダイアログを提供しないため対象外",
    "OnVanishButtonHold": "消滅スクリプトのダブルクリック中断操作を提供しないため対象外",
    "OnBalloonBreak": "通常トークを途中位置付きで中断する操作を提供しないため対象外",
    "OnTrayBalloonClick": "Windows通知領域のトレイバルーン機能でありmacOS版では対象外",
    "OnTrayBalloonTimeout": "Windows通知領域のトレイバルーン機能でありmacOS版では対象外",
    "OnFileDropped": "旧仕様のため対象外。複数項目とMIME typeを扱えるOnFileDrop2を発行",
    "OnFileDrop": "旧仕様のため対象外。複数項目とMIME typeを扱えるOnFileDrop2を発行",
    "OnFileDropEx": "旧仕様のため対象外。複数項目とMIME typeを扱えるOnFileDrop2を発行",
    "OnOtherObjectDropping": "SSPの他オブジェクトDnD連携を提供しないため対象外",
    "OnOtherObjectDropped": "SSPの他オブジェクトDnD連携を提供しないため対象外",
    "OnWallpaperChange": "画像DnDによる壁紙変更機能を提供しないため対象外",
    "OnBIFFBegin": "メールアカウントとPOPメールチェック機能を提供しないため対象外",
    "OnBIFFComplete": "メールアカウントとPOPメールチェック機能を提供しないため対象外",
    "OnBIFF2Complete": "メールアカウントとPOPメールチェック機能を提供しないため対象外",
    "OnBIFFFailure": "メールアカウントとPOPメールチェック機能を提供しないため対象外",
    "OnSSTPBlacklisting": "UtataneのSSTPはlocalhostだけを受け付け、IPブラックリストを持たないため対象外",
    "OnExecuteHTTPProgress": "execute-httpのprogress-notifyオプションを提供しないため対象外",
    "OnExecuteHTTPStreaming": "execute-httpのstreamingオプションを提供しないため対象外",
    "OnExecuteHTTPSSLInfo": "TLS証明書詳細をSHIORIへ公開する機能を提供しないため対象外",
    "OnExecuteRSS_SSLInfo": "TLS証明書詳細をSHIORIへ公開する機能を提供しないため対象外",
    "OnExecuteICalComplete": "SakuraScriptからのical-get／ical-post操作を提供しないため対象外",
    "OnExecuteICalFailure": "SakuraScriptからのical-get／ical-post操作を提供しないため対象外",
    "OnExecuteICalProgress": "SakuraScriptからのical-get／ical-post操作を提供しないため対象外",
    "OnExecuteICal_SSLInfo": "SakuraScriptからのical-get／ical-post操作を提供しないため対象外",
    "OnExecuteScheduleComplete": "SakuraScriptからのschedule-add／schedule-delete操作を提供しないため対象外",
    "OnExecuteScheduleFailure": "SakuraScriptからのschedule-add／schedule-delete操作を提供しないため対象外",
    "OnExecuteScheduleGetComplete": "SakuraScriptからのschedule-get操作を提供しないため対象外",
    "OnExecuteFileWatchChange": "SakuraScriptからのfilewatch操作を提供しないため対象外",
    "OnExecuteFileWatchFailure": "SakuraScriptからのfilewatch操作を提供しないため対象外",
    "OnExecuteWebSocketReconnect": "WebSocket自動再接続オプションを提供しないため対象外",
    "OnExecuteWebSocket_SSLInfo": "TLS証明書詳細をSHIORIへ公開する機能を提供しないため対象外",
    "OnPingProgress": "pingの応答単位progress通知を提供しないため対象外",
    "OnRaiseOtherFailure": "他ベースウェア宛てraise配送を提供しないため対象外",
    "OnNotifyOtherFailure": "他ベースウェア宛てnotify配送を提供しないため対象外",
    "OnDisplayHandover": "画面間移動の監視を提供しないため対象外",
    "OnTabletMode": "macOSに対応するタブレットモードがないため対象外",
    "OnOSUpdateInfo": "Windows Update履歴を通知するイベントでありmacOS版では対象外",
    "OnRecycleBinEmpty": "SakuraScriptからmacOSのゴミ箱を空にする操作を提供しないため対象外",
    "OnRecycleBinEmptyFromOther": "ゴミ箱を空にする操作を提供しないため対象外。外部変更はOnRecycleBinStatusUpdateで通知",
    "OnSelectModeBegin": "selectrect画面領域選択モードを提供しないため対象外",
    "OnSelectModeCancel": "selectrect画面領域選択モードを提供しないため対象外",
    "OnSelectModeComplete": "selectrect画面領域選択モードを提供しないため対象外",
    "OnSelectModeMouseDown": "selectrect画面領域選択モードを提供しないため対象外",
    "OnSelectModeMouseUp": "selectrect画面領域選択モードを提供しないため対象外",
    "OnTranslate": "SHIORIをMAKOTOとして再呼び出しする翻訳フックを提供しないため対象外",
    "OnOtherGhostTalk": "他ゴーストの全発話を監視するopt-in機能を提供しないため対象外",
    "OnEmbryoExist": "Windows用Materiaの同時起動検出イベントでありmacOS版では対象外",
    "OnNekodorifExist": "Windows用猫どりふの同時起動検出イベントでありmacOS版では対象外",
    "property.get": "SSPのactiveghostlist.ext拡張プロパティを提供しないため対象外",
    "property.set": "SSPのactiveghostlist.ext拡張プロパティを提供しないため対象外",
    "installedcalendarskinname": "カレンダースキンの起動時一覧通知を提供しないため対象外",
    "installedcalendarpluginname": "外部カレンダープラグインを提供しないため対象外",
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
    if event_id in UNSUPPORTED_EVENTS:
        return "—", "—"
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
    sections = unique_sections
    event_count = len(seen)
    status_counts = {"✅": 0, "🟡": 0, "❌": event_count - len(AUDITED_EVENTS) - len(UNSUPPORTED_EVENTS), "➖": len(UNSUPPORTED_EVENTS)}
    for status, _ in AUDITED_EVENTS.values():
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
        "| ✅ | Utataneが発行経路を提供。macOS固有差や未提供のSSP拡張は備考に記載 |",
        "| 🟡 | 再監査中の一時状態。公開時には残しません |",
        "| ❌ | 未分類の一時状態。公開時には残しません |",
        "| ➖ | 対応する本体機能を提供しない、macOSでは非該当、または新仕様に置き換え済み |",
        "",
        "名前がソースに現れるだけでは対応としません。発生条件とReferenceをUKADOCに照らし、提供する契約は✅、発生元機能を提供しないものは➖に分類します。",
        "任意IDを中継できる経路（raise、inputbox、HTTP等）は、そのイベントをベースウェアが自動発行する実装とは数えません。",
        "全イベントを本番Swiftコード（テストコードを除く）の固定IDおよびイベント生成経路と照合します。✅のmacOS固有差と実機確認状況は備考に残します。",
        "➖はイベントだけを単独実装せず、前提となる本体機能を将来追加する際に再評価します。",
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
            if event_id in AUDITED_EVENTS:
                status, note = AUDITED_EVENTS[event_id]
            elif event_id in UNSUPPORTED_EVENTS:
                status = "➖"
                note = UNSUPPORTED_EVENTS[event_id]
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
    }
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
