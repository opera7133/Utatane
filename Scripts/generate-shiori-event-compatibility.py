#!/usr/bin/env python3
"""Generate the SHIORI Event inventory from a local UKADOC checkout."""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path


AUDITED_EVENTS = {
    "hwnd": ("🟡", "起動時に各scopeのNSWindow番号をバイト値1区切りでNOTIFY。macOSのwindowNumberでありWindows HWNDではなく、未生成バルーンは空欄"),
    "otherghostname": ("🟡", "起動時に呼び出し起動中の他ゴースト名とscope 0/1のsurface番号をバイト値1区切りでNOTIFY。通常起動側から見える呼出ゴーストのみ"),
    "installedplugin": ("🟡", "起動時に空のNOTIFYを送り、プラグインがインストールされていない状態を通知。プラグイン機能自体は未実装"),
    "configuredbiffname": ("🟡", "起動時に空のNOTIFYを送り、設定済みメールアカウントがない状態を通知。メールチェック機能自体は未実装"),
    "pluginpathlist": ("🟡", "起動時に空のNOTIFYを送り、プラグイン格納パスがない状態を通知。プラグイン機能自体は未実装"),
    "calendarskinpathlist": ("🟡", "起動時に空のNOTIFYを送り、カレンダースキン格納パスがない状態を通知。カレンダー機能自体は未実装"),
    "calendarpluginpathlist": ("🟡", "起動時に空のNOTIFYを送り、カレンダープラグイン格納パスがない状態を通知。カレンダー機能自体は未実装"),
    "rateofusegraph": ("🟡", "起動中ゴーストをboot状態の1レコードとしてNOTIFY。起動回数・時間・割合は0固定で履歴集計は未実装"),
    "enable_log": ("🟡", "起動時にUtataneのアプリ内ログが有効であることをReference0=1でNOTIFY。SSP開発パレット相当の切替UIは未実装"),
    "enable_debug": ("🟡", "起動時にDebugビルドなら1、Releaseなら0をReference0へNOTIFY。実行中の切替UIは未実装"),
    "basewareversion": ("🟡", "起動時にUtataneの表示バージョン・本体名・ビルド番号をNOTIFY。SSPの数値形式との完全一致は未確認"),
    "uniqueid": ("🟡", "起動時にゴーストのインストールディレクトリ名を一意IDとしてNOTIFY。SSTPでの利用は未確認"),
    "capability": ("🟡", "起動時にUtataneが扱う主要SHIORIリクエスト・レスポンスヘッダをNOTIFY。拡張ヘッダの網羅は未対応"),
    "ownerghostname": ("🟡", "起動時に現在のゴースト名をReference0へNOTIFY"),
    "installedsakuraname": ("🟡", "起動時に全インストール済みゴーストのscope 0名を同一順序のReference列へNOTIFY"),
    "installedkeroname": ("🟡", "起動時に全インストール済みゴーストのscope 1名を同一順序のReference列へNOTIFY"),
    "installedghostname": ("🟡", "起動時に全インストール済みゴースト名をReference列へNOTIFY"),
    "installedshellname": ("🟡", "起動中ゴーストにインストールされたシェル名をReference列へNOTIFY。他ゴーストのシェルは含めない"),
    "installedballoonname": ("🟡", "起動時に全インストール済みバルーン名をReference列へNOTIFY"),
    "installedheadlinename": ("🟡", "起動時に全インストール済みRSS・ヘッドライン名をReference列へNOTIFY"),
    "ghostpathlist": ("🟡", "起動時にUtataneが参照するゴースト格納フォルダの絶対パスをNOTIFY。DebugではBundledとLocalの双方を含む"),
    "balloonpathlist": ("🟡", "起動時にUtataneが参照するバルーン格納フォルダの絶対パスをNOTIFY。DebugではBundledとLocalの双方を含む"),
    "headlinepathlist": ("🟡", "起動時にヘッドライン格納フォルダの絶対パスをReference0へNOTIFY"),
    "OnGamepadAxisMove": ("🟡", "GameControllerの左右スティック変化を0.08のデッドゾーン付きで全ゴーストへ通知。トリガー軸と通知間引きは未対応"),
    "OnGamepadButtonDown": ("🟡", "GameControllerの主要ボタン押下をパッド番号・ボタン名で全ゴーストへ通知。追加ボタンは未対応"),
    "OnGamepadButtonUp": ("🟡", "GameControllerの主要ボタン解放をパッド番号・ボタン名で全ゴーストへ通知。追加ボタンは未対応"),
    "OnGamepadConnected": ("🟡", "GameController接続時と起動時の接続済みコントローラを0始まり番号で全ゴーストへ通知。実機未確認"),
    "OnGamepadDisconnected": ("🟡", "GameController切断時に割当済みパッド番号を全ゴーストへ通知。実機未確認"),
    "OnKeyPress": ("🟡", "Utataneがアクティブな時のkeyDownを文字・macOS keyCode・repeat・scope・修飾キーで通知。Reference1はWin32仮想キーコードではない"),
    "OnScreenSaverEnd": ("🟡", "macOS分散通知でスクリーンセーバ終了を検出。名称は固定、実行ファイルと待ち時間は空欄"),
    "OnScreenSaverStart": ("🟡", "macOS分散通知でスクリーンセーバ開始を検出。名称は固定、実行ファイルと待ち時間は空欄"),
    "OnSessionDisconnect": ("🟡", "macOSユーザーセッションが非アクティブになった時にLockと併せて通知。簡易ユーザー切替と画面ロックを区別しない"),
    "OnSessionReconnect": ("🟡", "macOSユーザーセッションがアクティブへ戻った時にUnlockと併せて通知。簡易ユーザー切替と画面ロックを区別しない"),
    "OnAnchorEnter": ("🟡", "アンカーへの出入りでラベル・ID・追加引数を通知し、外れた時はReferenceなし。実動未確認"),
    "OnAnchorHover": ("🟡", "アンカー上で1秒静止した時にラベル・ID・追加引数を通知。SSPの静止時間との完全一致は未確認"),
    "OnBalloonScaling": ("🟡", "設定でバルーン倍率が変わった時に新旧の縦横パーセントをReference0〜3へ通知。縦横個別設定は未実装"),
    "OnChoiceEnter": ("🟡", "選択肢への出入りでラベル・ID・追加引数を通知し、外れた時はReferenceなし。実動未確認"),
    "OnChoiceHover": ("🟡", "選択肢上で1秒静止した時にラベル・ID・追加引数を通知。SSPの静止時間との完全一致は未確認"),
    "OnShellScaling": ("🟡", "設定でシェル倍率が変わった時に新旧の縦横パーセントをReference0〜3へ通知。縦横個別設定は未実装"),
    "OnSoundError": ("🟡", "音声ファイル解決・AVAudioPlayer生成・再生終了失敗時にplay・エラーコード・ファイル・説明を通知。実動未確認"),
    "OnSoundStop": ("🟡", "SakuraScript音声の自然終了とstop操作でファイル名・end/closeを通知。ループ終了など全経路は未確認"),
    "OnTextDrop": ("🟡", "サーフェスへのテキストDnDで改行をバイト値1に変換し本文とscopeを通知。実動未確認"),
    "OnURLDragDropping": ("🟡", "Web URLがサーフェスへ重なった時にURLとscopeを通知。受入可否の詳細判定は未実装"),
    "OnURLDropping": ("🟡", "Web URLがサーフェスへドロップされた時にURLとscopeを通知。後続のダウンロード機能は未実装"),
    "OnAITalk": ("✅", "\\a・手動ランダムトークからGETで発行。Referenceなし"),
    "OnBalloonChange": ("🟡", "切替後に名前とディレクトリ名を通知。UKADOCのパス表現との完全一致は未確認"),
    "OnBalloonClose": ("🟡", "再生完了後にユーザーがバルーンをクリックして閉じた時、表示スクリプトをReference0へ通知。実動未確認"),
    "OnBalloonTimeout": ("🟡", "選択肢のないバルーンが表示期限で閉じる時、スクリプトと残り時間0を通知。実動未確認"),
    "OnBoot": ("🟡", "起動時にReference0へ起動シェル名を通知。OnFirstBoot等からの204フォールバック規則は未対応"),
    "OnChoiceSelect": ("✅", "通常選択肢のIDをReference0、追加引数をReference1以降へ渡す"),
    "OnChoiceSelectEx": ("🟡", "選択肢ラベル・ID・追加引数をReference0以降へ通知。応答による通常OnChoiceSelectの抑制・フォールバックは未対応"),
    "OnChoiceTimeout": ("✅", "選択肢タイムアウト時に対象スクリプト全文をReference0へ通知。Playerテストで確認"),
    "OnClose": ("🟡", "終了時に発行するが終了理由・操作scopeのReferenceを送っていない"),
    "OnCommunicate": ("🟡", "他ゴースト連携と入力Boxの両経路で送信元をReference0、本文をReference1へ通知。キャンセル系は未対応"),
    "OnCommunicateInputCancel": ("🟡", "CommunicateBoxをキャンセルまたは閉じた時に空のReference0とReference1=cancelを通知。実動未確認"),
    "OnCompressArchiveComplete": ("🟡", "静的照合では圧縮成功時のイベントID規則とReference0〜3が一致。実行経路は未確認"),
    "OnCompressArchiveFailure": ("🟡", "静的照合では圧縮失敗時のイベントID規則とReference0〜1が一致。実行経路は未確認"),
    "OnDressupChanged": ("🟡", "scriptによるbind変更とReference0〜4を実装。複数変更時のNOTIFY/最後だけGET規則は未対応"),
    "OnExecuteHTTPComplete": ("🟡", "HTTP完了時のReference0〜6を実装。全結果コード・Cookie・高度なHTTPオプションは未照合"),
    "OnExecuteHTTPFailure": ("🟡", "HTTP失敗時にComplete互換Referenceを送るが、UKADOCの失敗理由コードとは未照合"),
    "OnExecuteRSSComplete": ("🟡", "RSS項目をReference列へ通知。更新日時形式などRSS互換の細部は未照合"),
    "OnExecuteRSSFailure": ("🟡", "解析失敗を通知。HTTP失敗時を含む全Reference構成は未照合"),
    "OnExecuteWebSocketClose": ("🟡", "close code・userbreakを通知。自動再接続と再接続後の最終Close規則は未実装"),
    "OnExecuteWebSocketFailure": ("🟡", "接続・受信エラーを通知。UKADOCの5回自動再接続後Failureは未実装"),
    "OnExecuteWebSocketOpen": ("✅", "HTTP 101成立後にReference0〜2を発行"),
    "OnExecuteWebSocketReceive": ("✅", "text/binary opcodeと本文またはBase64をReference0〜3へ発行"),
    "OnExtractArchiveComplete": ("🟡", "静的照合では展開成功時のイベントID規則とReference0〜3が一致。実行経路は未確認"),
    "OnExtractArchiveFailure": ("🟡", "静的照合では展開失敗時のイベントID規則とReference0〜1が一致。実行経路は未確認"),
    "OnGhostCallComplete": ("🟡", "呼出完了後に発行。Reference0〜3・7のうちReference3はUKADOC外の拡張"),
    "OnGhostCalled": ("🟡", "呼出先でReference0〜3・7を発行。204時のOnBootフォールバックは未対応"),
    "OnGhostCalling": ("🟡", "手動呼出時のReference0〜3を実装。automatic経路は未実装"),
    "OnFileDrop": ("🟡", "ドロップした先頭ファイルのパス・scope・MIME typeをReference0〜2へ通知。新旧イベント間の応答フォールバックは未対応"),
    "OnFileDrop2": ("🟡", "全ファイルのパスとMIME typeをバイト値1区切りでReference0・2へ、scopeをReference1へ通知。応答フォールバックは未対応"),
    "OnFileDropEx": ("🟡", "全ファイルのパスとMIME typeをバイト値1区切りでReference0・2へ、scopeをReference1へ通知。応答フォールバックは未対応"),
    "OnFileDropped": ("🟡", "ドロップ完了時に先頭ファイルのパス・scope・MIME typeをReference0〜2へ通知。新旧イベント間の応答フォールバックは未対応"),
    "OnFileDropping": ("🟡", "ファイルドラッグ進入時に先頭ファイルのパスとscopeをReference0〜1へ通知。複数ファイルの個別通知は未対応"),
    "OnDirectoryDrop": ("🟡", "ドロップされた各ディレクトリについてパスとscopeをReference0〜1へ通知。応答フォールバックは未対応"),
    "OnGhostChanging": ("🟡", "切替前に発行するがReference0のみ。manual/automatic・名前・パスが不足"),
    "OnHeadlinesense.OnFind": ("🟡", "静的照合ではサイト名・URL・phase・見出しのReference0〜3が一致。実行経路は未確認"),
    "OnHeadlinesenseBegin": ("🟡", "静的照合ではサイト名とURLのReference0〜1が一致。実行経路は未確認"),
    "OnHeadlinesenseComplete": ("🟡", "静的照合では更新なし時のReference0=no updateが一致。実行経路は未確認"),
    "OnHeadlinesenseFailure": ("🟡", "静的照合では取得・解析失敗理由のReference0が一致。実行経路は未確認"),
    "OnInstallBegin": ("🟡", "静的照合ではNARインストール開始前にReferenceなしで発行。実行経路は未確認"),
    "OnInstallCompleteEx": ("🟡", "複数項目をバイト値1区切りで通知するがReference2がインストール先ではなく元ファイル名"),
    "OnInstallFailure": ("🟡", "静的照合ではNARインストール失敗理由をReference0へ通知。実行経路は未確認"),
    "OnMouseClick": ("🟡", "Reference0〜6を通知。OnMouseUp応答後のフォールバック判定は未対応"),
    "OnMouseClickEx": ("🟡", "中・拡張ボタンのクリックをボタン名付きReference0〜6で通知。OnMouseUpEx応答後のフォールバック判定は未対応"),
    "OnMouseDoubleClick": ("🟡", "左・右ボタンのダブルクリックをReference0〜6で通知。実動未確認"),
    "OnMouseDoubleClickEx": ("🟡", "中・拡張ボタンのダブルクリックをボタン名付きReference0〜6で通知。実動未確認"),
    "OnMouseEnter": ("🟡", "当たり判定へ入った時に座標・scope・collision・入力種別をReference0〜6へ通知。マウス以外の入力種別は未対応"),
    "OnMouseEnterAll": ("🟡", "キャラクターウインドウへ入った時に座標・scope・collision・入力種別をReference0〜6へ通知。実動未確認"),
    "OnMouseLeave": ("🟡", "当たり判定から出た時に直前のcollisionと座標をReference0〜6へ通知。マウス以外の入力種別は未対応"),
    "OnMouseLeaveAll": ("🟡", "キャラクターウインドウから出た時に直前のcollisionと座標をReference0〜6へ通知。実動未確認"),
    "OnMouseDown": ("🟡", "左・右ボタンが押された時に座標・scope・collision・button・入力種別を通知。実動未確認"),
    "OnMouseDownEx": ("🟡", "中・拡張ボタンが押された時にボタン名付きReference0〜6で通知。実動未確認"),
    "OnMouseDragEnd": ("🟡", "キャラクター移動ドラッグ終了時にReference0〜6を通知。左ボタン以外のドラッグは未対応"),
    "OnMouseDragStart": ("🟡", "2px以上のキャラクター移動ドラッグ開始時にReference0〜6を通知。左ボタン以外のドラッグは未対応"),
    "OnMouseHover": ("🟡", "キャラクター上でマウス移動が1秒止まった時にReference0〜6を通知。SSPの静止時間との完全一致は未確認"),
    "OnMouseMove": ("🟡", "移動量がcollision別の閾値を超えた時にReference0〜6を通知。SSPの全移動通知とは頻度が異なる"),
    "OnMouseMultipleClick": ("🟡", "左・右ボタンの3連打以上を回数付きReference0〜7で通知。204時の通常Click系フォールバックは未対応"),
    "OnMouseMultipleClickEx": ("🟡", "中・拡張ボタンの3連打以上を回数付きReference0〜7で通知。204時の通常Click系フォールバックは未対応"),
    "OnMouseUp": ("🟡", "左・右ボタンが放された時にReference0〜6を通知。応答有無によるOnMouseClick抑制は未対応"),
    "OnMouseUpEx": ("🟡", "中・拡張ボタンが放された時にボタン名付きReference0〜6で通知。応答有無によるClickEx抑制は未対応"),
    "OnMouseWheel": ("🟡", "座標・wheel量・scope・collision・button・入力種別を通知。gestureフォールバックは未対応"),
    "OnNSLookupComplete": ("🟡", "静的照合では正引き・逆引きのReference0〜3が一致。実行経路は未確認"),
    "OnNSLookupFailure": ("🟡", "静的照合ではReference0〜2が一致するが、空のReference3を追加。実行経路は未確認"),
    "OnNotifyDressupInfo": ("🟡", "bind変更後に全着せ替え情報をバイト値1区切りで通知。起動時NOTIFYとuser操作GETは未対応"),
    "OnNotifyBalloonInfo": ("🟡", "起動時にバルーン名・絶対パス・検出したsakura/kero画像番号を通知。追加キャラクター用画像番号は未対応"),
    "OnNotifyFontInfo": ("🟡", "起動時にmacOSで利用可能なフォント名をReference列へNOTIFY。フォント変更の動的再通知は未対応"),
    "OnNotifyInternationalInfo": ("🟡", "起動時にUTC時差・夏時間・国・言語コードをReference0〜3へNOTIFY。Locale未設定時は空欄"),
    "OnNotifyOSInfo": ("🟡", "起動時にmacOS・CPUコア数・物理メモリ・uptimeをReference0〜3へNOTIFY。CPUクロックと仮想メモリは概算値"),
    "OnNotifySelfInfo": ("🟡", "起動時にゴースト・キャラクター・シェル・バルーンの名前と絶対パスをReference0〜6へNOTIFY"),
    "OnNotifyShellInfo": ("🟡", "起動時にシェル名・絶対パス・定義済みsurface番号一覧をReference0〜2へNOTIFY"),
    "OnNotifyUserInfo": ("🟡", "起動時にmacOSアカウント名とフルネームを通知。誕生日は空、性別はundef固定"),
    "OnOtherGhostClosed": ("🟡", "他ゴースト終了後に本体名・最終スクリプト・ゴースト名・シェル名をReference0/1/2/7へ通知。実動未確認"),
    "OnOtherSurfaceChange": ("🟡", "他の実行中ゴーストへ本体名・Sakura名・scope・新旧surface・矩形をReference0〜5で通知。othersurfacechange無効化設定は未対応"),
    "OnPingComplete": ("🟡", "ping完了を通知するがReference1の送信元アドレスとReference2以降の1応答1Reference構造が未対応"),
    "OnRSSBegin": ("🟡", "サイト名・URLを通知。無応答時のOnHeadlinesenseBeginフォールバックは未対応"),
    "OnRSSComplete": ("🟡", "フィード情報をReference0以降へ通知。無応答時のheadline系フォールバックと日時形式は未対応"),
    "OnRSSFailure": ("🟡", "失敗理由をReference0へ通知。無応答時のOnHeadlinesenseFailureフォールバックは未対応"),
    "OnResetWindowPos": ("🟡", "コンテキストメニューのウインドウ位置初期化で通知してからシェル・バルーン位置を初期化。無応答時のみ実行する制御は未対応"),
    "OnSecondChange": ("🟡", "毎秒Reference0〜4を通知。会話不能時もGETで送り、NOTIFYに切り替えていない"),
    "OnSessionLock": ("🟡", "macOSユーザーセッションが非アクティブになった時に通知。実機ロックでの実動未確認"),
    "OnSessionUnlock": ("🟡", "macOSユーザーセッションが再びアクティブになった時に通知。実機ロック解除での実動未確認"),
    "OnCPULoadHigh": ("🟡", "OS全体のCPU使用率が80%以上で5秒間隔3回続いた時に現在率をReference0へ通知。実負荷での実動未確認"),
    "OnCPULoadLow": ("🟡", "CPU High通知後に使用率が60%未満へ戻った時、現在率をReference0へ通知。状態遷移テストで確認"),
    "OnMemoryLoadHigh": ("🟡", "VM統計のメモリ使用率が80%以上で5秒間隔3回続いた時に現在率をReference0へ通知。実負荷での実動未確認"),
    "OnMemoryLoadLow": ("🟡", "Memory High通知後に使用率が60%未満へ戻った時、現在率をReference0へ通知。状態遷移テストで確認"),
    "OnDisplayChange": ("🟡", "画面構成変更時にプライマリ画面のbpp・幅・高さをReference0〜2へ通知。起動時NOTIFYは未対応"),
    "OnDestroy": ("🟡", "ゴースト終了処理でOnCloseより前にNOTIFY。リロード時のReference0=reloadは未対応"),
    "OnDarkTheme": ("🟡", "起動時とアプリ再アクティブ化時にmacOSのダークモード状態をReference0〜1へ通知。非アクティブ中の変更は復帰時通知"),
    "OnMinuteChange": ("🟡", "分の変化ごとにReference0〜4を通知。会話不能時は応答を無視するがSHIORIメソッドはGETのまま"),
    "OnHourTimeSignal": ("🟡", "正時後、会話可能になるまで保留してReference0〜4を通知。実時間での実動未確認"),
    "OnInitialize": ("🟡", "SHIORIセッション開始直後、OnBootまたはOnGhostCalledより前にNOTIFY。リロード時のReference0=reloadは未対応"),
    "OnLanguageChange": ("🟡", "起動時に現在の言語名とLocale IDをReference0〜1へ通知。実行中の言語変更監視とUtatane言語フォルダ・ヘルプURLは未対応"),
    "OnShellChanged": ("🟡", "切替後に現シェル名・ゴースト名・シェルパスをReference0〜2へ通知。実動未確認"),
    "OnShellChanging": ("🟡", "切替前に新旧シェル名と新シェルパスをReference0〜2へ通知。実動未確認"),
    "OnSurfaceRestore": ("🟡", "会話消去時に現在surfaceをReference0〜1へ通知。UKADOCのバルーン消去後15秒という発生時刻とは異なる"),
    "OnSurfaceChange": ("🟡", "SakuraScript等でsurfaceが変わった時に本体側・相方側の現在IDをReference0〜1へ通知。NOTIFYメソッドの区別は未対応"),
    "OnAnchorSelect": ("🟡", "アンカーIDをReference0へ通知。OnAnchorSelectExの204応答を待つフォールバックではなく両方を発行"),
    "OnAnchorSelectEx": ("🟡", "アンカーの表示ラベル・ID・追加引数をReference0以降へ通知。204応答時だけOnAnchorSelectへ進む制御は未対応"),
    "OnSysResume": ("🟡", "macOSのスリープ復帰通知でReference0=normalを発行。自動復帰理由autoの判定は未対応"),
    "OnSysSuspend": ("🟡", "macOSがスリープへ入る直前にNOTIFY。実機スリープでの実動未確認"),
    "OnTeach": ("🟡", "同一ゴーストセッション中の入力履歴をReference0から順に通知。入力UIを含む実動未確認"),
    "OnTeachInputCancel": ("🟡", "TeachBoxをキャンセルまたは閉じた時に空のReference0とReference1=cancelを通知。実動未確認"),
    "OnTeachStart": ("🟡", "TeachBoxを表示する直前に通知。応答スクリプトは表示せず通知として扱う"),
    "OnUpdateBegin": ("🟡", "更新開始時に発行するがReference0〜4を送っていない"),
    "OnUpdateComplete": ("🟡", "成功時に発行するがReference1がファイル名一覧でなく件数。Reference3〜4も不足"),
    "OnUpdateFailure": ("🟡", "失敗時にReference0を通知。失敗ファイル・対象種別・実行理由が不足"),
    "OnUserInput": ("🟡", "Onで始まらないInputBox IDの決定時にID・入力内容・空の補足をReference0〜2へ通知。追加reference等は未対応"),
    "OnUserInputCancel": ("🟡", "InputBoxをキャンセルまたは閉じた時にID・close・空の補足をReference0〜2へ通知。タイムアウト理由は未対応"),
    "OnWindowStateMinimize": ("🟡", "macOSでアプリが非表示になった時にReference0=systemを通知。script・user理由の区別は未対応"),
    "OnWindowStateRestore": ("🟡", "macOSでアプリの非表示が解除された時にReference0=systemを通知。script・user理由の区別は未対応"),
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
    if event_id in AUDITED_EVENTS:
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
    status_counts = {"✅": 0, "🟡": 0, "❌": event_count - len(AUDITED_EVENTS)}
    for status, _ in AUDITED_EVENTS.values():
        status_counts[status] += 1
    lines = [
        "# SHIORI Event compatibility matrix",
        "",
        "Utatane が発行する SHIORI Event を UKADOC の一覧と比較するための詳細表。",
        "項目名と分類は `Scripts/generate-shiori-event-compatibility.py` によりローカルの UKADOC から生成する。",
        "",
        "基準: [SHIORI Eventリスト](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html)",
        "",
        f"UKADOC掲載イベント数: {event_count}",
        "調査日: 2026-08-24",
        f"調査結果: ✅ {status_counts['✅']} / 🟡 {status_counts['🟡']} / ❌ {status_counts['❌']}",
        "",
        "## 判定",
        "",
        "| 記号 | 意味 |",
        "| --- | --- |",
        "| ✅ | 発生条件、GET/NOTIFY、Reference、応答の扱いまで確認済み |",
        "| 🟡 | Utataneに発行経路があるが、UKADOCとの差分が残るか未照合 |",
        "| ❌ | 発生させる機能・経路が未実装であることを確認済み |",
        "| ➖ | macOSでは意味が薄い、または代替仕様の設計判断が必要 |",
        "",
        "名前がソースに現れるだけでは対応としない。🟡候補についても、発生条件とReferenceをUKADOCに照らしてから✅へ変更する。",
        "任意IDを中継できる経路（raise、inputbox、HTTP等）は、そのイベントをベースウェアが自動発行する実装とは数えない。",
        "全290件を本番Swiftコード（テストコードを除く）の固定IDおよびイベント生成経路と静的照合した。✅は既存テストまたは実動確認の根拠があるものに限定する。",
        "❌には、イベント通知だけでなく、その発生元となる本体機能自体が未実装の項目も含む。前提機能の実装後にイベント経路を追加する。",
        "難度はUtataneの現状を基準にした暫定評価で、UKADOC照合だけなら低、OS監視や新規UIを伴うものは中、アカウント・外部サービス・大きな新機能を伴うものは高とする。",
        "",
    ]
    for title, event_ids in sections:
        lines.extend([
            f"## {title}",
            "",
            "| イベント | 状況 | 前提 | 難度 | Utataneの挙動・不足 |",
            "| --- | --- | --- | --- | --- |",
        ])
        for event_id in event_ids:
            link = f"https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#{event_id}"
            prerequisite, difficulty = implementation_metadata(title, event_id)
            if event_id in AUDITED_EVENTS:
                status, note = AUDITED_EVENTS[event_id]
            else:
                status = "❌"
                note = "本番コードにベースウェアからの自動発行経路なし"
            lines.append(
                f"| [`{event_id}`]({link}) | {status} | {prerequisite} | {difficulty} | {note} |"
            )
        lines.append("")
    lines.extend([
        "## 更新ルール",
        "",
        "- 実装または調査時に、発生条件・Reference・GET/NOTIFY・応答利用の4点を確認する。",
        "- 難度は実装調査で随時更新し、対応状況とは独立して扱う。",
        "- ✅へ変更する場合は、テストまたは実機確認の根拠を備考に残す。",
        "- UKADOC側の増減確認には生成スクリプトを使い、既存の手動判定を上書きしないよう差分を確認する。",
        "- 外部からのSHIORI EventとSHIORI Resourceは、この表とは分けて管理する。",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ukadoc", type=Path, help="path to UKADOC's list_shiori_event.html")
    parser.add_argument("output", type=Path, help="Markdown output path")
    args = parser.parse_args()
    args.output.write_text(render(args.ukadoc), encoding="utf-8")


if __name__ == "__main__":
    main()
