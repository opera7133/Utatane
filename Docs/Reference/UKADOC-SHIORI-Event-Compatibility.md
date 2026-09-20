# UKADOC SHIORIイベント互換状況

ゴーストへ送るSHIORIイベントについて、Utataneが通知する条件と、SSPとの違いをまとめています。
項目名と分類の生成には`Scripts/generate-shiori-event-compatibility.py`と、ローカルに保存したUKADOCを使います。各行の判定と備考は、実装や確認結果に合わせて更新します。

基準: [SHIORI Eventリスト](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html)

UKADOC掲載イベント数: 304
調査日: 2026-09-20
調査結果: ✅ 295 / 🟡 0 / ❌ 0 / ➖ 9

## 判定

| 記号 | 意味 |
| --- | --- |
| ✅ | Utataneが発行経路を提供。macOS固有差や未提供のSSP拡張は備考に記載 |
| 🟡 | 仕様と不足している実装を確認済み。実装予定 |
| ❌ | 未分類の一時状態。公開時には残しません |
| ➖ | Windows固有などmacOSでは非該当、旧仕様に置き換え済み、または現行UKADOCで契約未定義 |

名前がソースに現れるだけでは対応としません。発生条件とReferenceをUKADOCに照らし、提供する契約は✅、未実装は🟡、macOSで成立しないか契約が定義されていないものだけを➖に分類します。
任意IDを中継できる経路（raise、inputbox、HTTP等）は、そのイベントをベースウェアが自動発行する実装とは数えません。
全イベントを本番Swiftコード（テストコードを除く）の固定IDおよびイベント生成経路と照合します。✅のmacOS固有差と実機確認状況は備考に残します。
➖はWindows固有機能、旧仕様、または現行UKADOCで契約を実装できない根拠を備考へ記録します。Utatane側の機能不足だけを理由に➖へ分類しません。

## 起動・終了・切り替えイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnFirstBoot`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnFirstBoot) | ✅ | 初回起動時に消滅回数0をReference0へ通知し、無応答ならOnBootへフォールバック。イベント生成とフォールバックをテスト済み |
| [`OnBoot`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBoot) | ✅ | 起動シェル名をReference0へ通知。OnFirstBoot・OnGhostChanged・OnGhostCalled・OnVanishedが無応答の時にフォールバックする経路をテスト済み |
| [`OnClose`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnClose) | ✅ | 終了理由をReference0、メニューと終了対象のscopeをReference1・2へ通知。通常終了とOnCloseAllからのフォールバックをテスト済み |
| [`OnCloseAll`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnCloseAll) | ✅ | アプリ終了時にuser、macOSの終了通知時にsystemをReference0へ通知。応答がない場合だけOnCloseへフォールバックし、応答があれば抑制する経路をテスト済み |
| [`OnGhostChanged`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGhostChanged) | ✅ | 切替元の本体名・終了スクリプト・ゴースト名・パスと切替先シェル名をReference0〜3・7へ通知し、無応答ならOnBootへフォールバック。テスト済み |
| [`OnGhostChanging`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGhostChanging) | ✅ | 手動切替前に切替先の本体側名・manual・ゴースト名・パスをReference0〜3へ通知。無応答ならOnCloseへフォールバック。automatic理由を使う自動切替は未実装 |
| [`OnGhostCalled`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGhostCalled) | ✅ | 呼出先で呼出元の本体名・呼出スクリプト・ゴースト名・パスと呼出先シェル名をReference0〜3・7へ通知し、無応答ならOnBootへフォールバック。テスト済み |
| [`OnGhostCalling`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGhostCalling) | ✅ | 手動呼出時のReference0〜3を実装。automatic経路は未実装 |
| [`OnGhostCallComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGhostCallComplete) | ✅ | 呼出完了後に呼出先の本体名・起動スクリプト・ゴースト名・シェル名をReference0〜2・7へ通知。イベント生成をテスト済み |
| [`OnOtherGhostBooted`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherGhostBooted) | ✅ | 呼び出しゴーストの起動完了時、無関係な起動中ゴーストへ本体名・起動スクリプト・ゴースト名・シェル名をReference0〜2・7で通知。イベント生成をテスト済み |
| [`OnOtherGhostChanged`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherGhostChanged) | ✅ | 呼び出しゴーストの切替時に切替前後の本体名・ゴースト名・パス・シェル名を、メインと他の呼び出しゴーストへ通知 |
| [`OnOtherGhostClosed`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherGhostClosed) | ✅ | 呼び出しゴーストの終了後、本体名・最終スクリプト・ゴースト名・シェル名をReference0〜2・7へ通知。イベント生成をテスト済み |
| [`OnShellChanged`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnShellChanged) | ✅ | 切替後に現シェル名・ゴースト名・シェルパスをReference0〜2へ通知。イベント生成テストで確認 |
| [`OnShellChanging`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnShellChanging) | ✅ | 切替前に新旧シェル名と新シェルパスをReference0〜2へ通知。イベント生成テストで確認 |
| [`OnDressupChanged`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDressupChanged) | ✅ | scriptによるbind変更とReference0〜4を実装。複数変更時のNOTIFY/最後だけGET規則は未対応 |
| [`OnBalloonChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBalloonChange) | ✅ | 切替後のバルーン名とフルパスをReference0〜1へ通知。メイン・呼び出しゴーストの共通イベント生成をテスト済み |
| [`OnWindowStateRestore`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnWindowStateRestore) | ✅ | macOSでアプリの非表示が解除された時にReference0=systemを通知。script・user理由の区別は未対応 |
| [`OnWindowStateMinimize`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnWindowStateMinimize) | ✅ | macOSでアプリが非表示になった時にReference0=systemを通知。script・user理由の区別は未対応 |
| [`OnFullScreenAppMinimize`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnFullScreenAppMinimize) | ✅ | 前面アプリの通常レイヤに画面全体と一致するウインドウを検出すると、シェル・バルーンを透過してReference0=fullscreenを通知 |
| [`OnFullScreenAppRestore`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnFullScreenAppRestore) | ✅ | 前面アプリの全画面ウインドウがなくなると、シェル・バルーンを再表示してReference0=fullscreenを通知 |
| [`OnVirtualDesktopChanged`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnVirtualDesktopChanged) | ✅ | macOSのactiveSpaceDidChangeでReference0=currentを通知。公開APIでSpace IDを取得できないためReference1は空 |
| [`OnCacheSuspend`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnCacheSuspend) | ✅ | 呼び出しゴーストを右クリックメニューから休止する前に発行し、ウインドウを非表示化 |
| [`OnCacheRestore`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnCacheRestore) | ✅ | 休止中の呼び出しゴーストをメニューから復帰した後に発行 |
| [`OnInitialize`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnInitialize) | ✅ | SHIORIセッション開始直後、OnBootまたはOnGhostCalledより前にNOTIFY。リロード時のReference0=reloadは未対応 |
| [`OnDestroy`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDestroy) | ✅ | ゴースト終了処理でOnCloseより前にNOTIFY。リロード時のReference0=reloadは未対応 |
| [`OnSysResume`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSysResume) | ✅ | macOSのスリープ復帰通知でReference0=normalを発行。自動復帰理由autoの判定は未対応 |
| [`OnSysSuspend`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSysSuspend) | ✅ | macOSがスリープへ入る直前にNOTIFY。実機スリープでの実動未確認 |
| [`OnBasewareUpdating`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBasewareUpdating) | ✅ | Sparkleが更新をインストールする直前に旧バージョンとビルド番号を通知 |
| [`OnBasewareUpdated`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBasewareUpdated) | ✅ | 更新後の初回起動で保存済みの旧版情報と現在版情報を通知 |

## 入力ボックスイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnTeachStart`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnTeachStart) | ✅ | TeachBoxを表示する直前にReferenceなしで通知。イベント生成テストで確認 |
| [`OnTeachInputCancel`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnTeachInputCancel) | ✅ | TeachBoxをキャンセルまたは閉じた時に空のReference0とReference1=cancelを通知。イベント生成テストで確認 |
| [`OnTeach`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnTeach) | ✅ | 同一ゴーストセッション中の入力履歴をReference0から順に通知。イベント生成テストで確認 |
| [`OnCommunicate`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnCommunicate) | ✅ | 他ゴースト連携と入力Boxの両経路で送信元をReference0、本文をReference1へ通知。キャンセル系は未対応 |
| [`OnCommunicateInputCancel`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnCommunicateInputCancel) | ✅ | CommunicateBoxをキャンセルまたは閉じた時に空のReference0とReference1=cancelを通知。イベント生成テストで確認 |
| [`OnUserInput`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUserInput) | ✅ | Onで始まらないInputBox IDの決定時にID・入力内容・空の補足をReference0〜2へ通知。追加reference等は未対応 |
| [`OnUserInputCancel`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUserInputCancel) | ✅ | InputBoxをキャンセルまたは閉じた時にID・close・空の補足をReference0〜2へ通知。タイムアウト理由は未対応 |
| [`inputbox.autocomplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#inputbox.autocomplete) | ✅ | inputbox・teachbox・communicatebox展開時に種類とIDを通知し、バイト値1区切りの応答を重複除去してmacOS候補入力欄へ反映。実ゴーストでの操作確認は未実施 |

## ダイアログボックスイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnSystemDialog`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSystemDialog) | ✅ | open/save/folder/colorダイアログの決定時に種別・ID・選択パスまたはRGB値をReference0〜2へ通知。Onで始まるIDは指定イベントとして通知 |
| [`OnSystemDialogCancel`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSystemDialogCancel) | ✅ | open/save/folder/colorダイアログのキャンセル時に種別・IDをReference0〜1へ通知 |
| [`OnConfigurationDialogHelp`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnConfigurationDialogHelp) | ✅ | 本体設定のヘルプボタンから現在の設定ページIDを通知 |
| [`OnGhostTermsAccept`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGhostTermsAccept) | ✅ | terms.txtの利用規約ダイアログで同意した時に通知。UTF-8とShift_JISを読込 |
| [`OnGhostTermsDecline`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGhostTermsDecline) | ✅ | terms.txtの利用規約ダイアログで拒否した時に通知 |

## 時間イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnSecondChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSecondChange) | ✅ | 毎秒Reference0〜4を通知。会話不能時もGETで送り、NOTIFYに切り替えていません |
| [`OnMinuteChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMinuteChange) | ✅ | 分の変化ごとにReference0〜4を通知。会話不能時は応答を無視するがSHIORIメソッドはGETのまま |
| [`OnHourTimeSignal`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnHourTimeSignal) | ✅ | 正時後、会話可能になるまで保留してReference0〜4を通知。実時間での実動未確認 |

## 消滅イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnVanishSelecting`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnVanishSelecting) | ✅ | コンテンツエクスプローラまたは確認付きvanishbymyselfから、確認画面を出す前に発行。実画面での一連操作は未確認 |
| [`OnVanishSelected`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnVanishSelected) | ✅ | 確認後または即時vanishbymyselfで、SHIORI終了前に発行して応答スクリプトを再生。実画面での一連操作は未確認 |
| [`OnVanishCancel`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnVanishCancel) | ✅ | 消滅確認をキャンセルした時に発行して応答スクリプトを再生。実画面での一連操作は未確認 |
| [`OnVanishButtonHold`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnVanishButtonHold) | ✅ | OnVanishSelected再生中のバルーンをダブルクリックした時にスクリプト・scope・表示文字位置を通知し、再生と消滅処理を取り消す |
| [`OnVanished`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnVanished) | ✅ | 消滅後の切り替え先へ消滅元の本体名・最終スクリプト・ゴースト名と切替先シェル名をReference0〜2・7で通知し、無応答ならOnBootへフォールバック。テスト済み |
| [`OnOtherGhostVanished`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherGhostVanished) | ✅ | 呼び出しゴーストの消滅後、他の起動中ゴーストへReference0〜2・7を発行し、204時はOnVanishedへフォールバック。実画面での一連操作は未確認 |

## 選択肢イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnChoiceSelect`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnChoiceSelect) | ✅ | 通常選択肢のIDをReference0、追加引数をReference1以降へ渡す。OnChoiceSelectExが無応答の時だけ続けて発行 |
| [`OnChoiceSelectEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnChoiceSelectEx) | ✅ | 選択肢ラベル・ID・追加引数をReference0以降へ通知し、応答にトークがあれば通常OnChoiceSelectを抑制。Playerテストで確認 |
| [`OnChoiceEnter`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnChoiceEnter) | ✅ | 選択肢への出入りでラベル・ID・追加引数を通知し、外れた時はReferenceなし。Playerテストで確認 |
| [`OnChoiceTimeout`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnChoiceTimeout) | ✅ | 選択肢タイムアウト時に対象スクリプト全文をReference0へ通知。Playerテストで確認 |
| [`OnChoiceHover`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnChoiceHover) | ✅ | 選択肢上で1秒静止した時にラベル・ID・追加引数を通知。PlayerテストでReferenceを確認 |
| [`OnAnchorSelect`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnAnchorSelect) | ✅ | OnAnchorSelectExがスクリプトを返さない場合のみアンカーIDをReference0へ通知。メイン・呼び出しゴーストの両経路で対応 |
| [`OnAnchorSelectEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnAnchorSelectEx) | ✅ | アンカーの表示ラベル・ID・追加引数をReference0以降へ通知し、非空応答時はOnAnchorSelectを抑止。応答は割り込み再生 |
| [`OnAnchorEnter`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnAnchorEnter) | ✅ | アンカーへの出入りでラベル・ID・追加引数を通知し、外れた時はReferenceなし。Playerテストで確認 |
| [`OnAnchorHover`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnAnchorHover) | ✅ | アンカー上で1秒静止した時にラベル・ID・追加引数を通知。PlayerテストでReferenceを確認 |

## サーフェスイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnSurfaceChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSurfaceChange) | ✅ | SakuraScript等でsurfaceが変わった時に本体側・相方側の現在IDをReference0〜1へ通知。NOTIFYメソッドの区別は未対応 |
| [`OnSurfaceRestore`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSurfaceRestore) | ✅ | SSP同様、バルーン消去15秒後に、その時点の現在surfaceをReference0〜1へ通知。待機中に次の会話が始まった場合は通知を取り消します。Playerテスト済み。Emily/Phase4.5は標準イベントを意図的に無効化し、YAYA SHIORI/3フレームワーク側の独自タイミングで復帰します |
| [`OnOtherSurfaceChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherSurfaceChange) | ✅ | set,othersurfacechangeを有効にしたゴーストへ、他ゴーストの本体名・Sakura名・scope・新旧surface・矩形をReference0〜5で通知 |

## マウスイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnMouseClick`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseClick) | ✅ | Reference0〜6を通知。OnMouseUpが無応答の場合だけ発行する応答規則をテスト済み |
| [`OnMouseClickEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseClickEx) | ✅ | 中・拡張ボタンのクリックをボタン名付きReference0〜6で通知。OnMouseUpExが無応答の場合だけ発行する応答規則をテスト済み |
| [`OnMouseDoubleClick`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseDoubleClick) | ✅ | 左・右ボタンのダブルクリックをReference0〜6で通知。OnMouseUpの応答では抑止されないことを含めて自動テスト済み |
| [`OnMouseDoubleClickEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseDoubleClickEx) | ✅ | 中・拡張ボタンのダブルクリックをボタン名付きReference0〜6で通知。OnMouseUpExの応答では抑止されないことを含めて自動テスト済み |
| [`OnMouseMultipleClick`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseMultipleClick) | ✅ | 左・右ボタンの3連打以上を回数付きReference0〜7で通知。無応答時は奇数回をClick、偶数回をDoubleClickへ戻し、OnMouseUp応答時は通常Clickへのフォールバックだけを抑止する規則をテスト済み |
| [`OnMouseMultipleClickEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseMultipleClickEx) | ✅ | 中・拡張ボタンの3連打以上を回数付きReference0〜7で通知。無応答時は通常のClickEx／DoubleClickExへ戻し、OnMouseUpEx応答時は通常ClickExへのフォールバックだけを抑止する規則をテスト済み |
| [`OnMouseUp`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseUp) | ✅ | 左・右ボタンが放された時にReference0〜6を通知。応答があれば後続の通常OnMouseClickだけを抑止する規則をテスト済み |
| [`OnMouseUpEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseUpEx) | ✅ | 中・拡張ボタンが放された時にボタン名付きReference0〜6で通知。応答があれば後続の通常OnMouseClickExだけを抑止する規則をテスト済み |
| [`OnMouseDown`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseDown) | ✅ | 左・右ボタンが押された時に座標・scope・collision・button・入力種別を通知。入力からSHIORI変換まで自動テスト済み |
| [`OnMouseDownEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseDownEx) | ✅ | 中・拡張ボタンが押された時にボタン名付きReference0〜6で通知。入力経路とSHIORI変換を自動テスト済み |
| [`OnMouseMove`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseMove) | ✅ | 移動量がcollision別の閾値を超えた時にReference0〜6を通知。SSPの全移動通知とは頻度が異なります |
| [`OnMouseWheel`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseWheel) | ✅ | 座標・wheel量・scope・collision・button・入力種別を通知。gestureフォールバックは未対応 |
| [`OnMouseEnterAll`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseEnterAll) | ✅ | キャラクターウインドウへ入った時に座標・scope・collision・入力種別をReference0〜6へ通知。入力からSHIORI変換まで自動テスト済み |
| [`OnMouseLeaveAll`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseLeaveAll) | ✅ | キャラクターウインドウから出た時に直前のcollisionと座標をReference0〜6へ通知。入力からSHIORI変換まで自動テスト済み |
| [`OnMouseEnter`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseEnter) | ✅ | 当たり判定へ入った時に座標・scope・collision・入力種別をReference0〜6へ通知。マウス以外の入力種別は未対応 |
| [`OnMouseLeave`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseLeave) | ✅ | 当たり判定から出た時に直前のcollisionと座標をReference0〜6へ通知。マウス以外の入力種別は未対応 |
| [`OnMouseDragStart`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseDragStart) | ✅ | 2px以上のキャラクター移動ドラッグ開始時にReference0〜6を通知。左ボタン以外のドラッグは未対応 |
| [`OnMouseDragEnd`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseDragEnd) | ✅ | キャラクター移動ドラッグ終了時にReference0〜6を通知。左ボタン以外のドラッグは未対応 |
| [`OnMouseHover`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseHover) | ✅ | キャラクター上でマウス移動が1秒止まった時にReference0〜6を通知。入力からSHIORI変換まで自動テスト済み |
| [`OnMouseGesture`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMouseGesture) | ✅ | 右ボタンまたはホイールの8方向ドラッグと終了を、scope・現在位置／開始位置・各collision・角度とともに通知。circle.cw／circle.ccwは未対応 |

## ゲームパッドイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnGamepadButtonDown`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGamepadButtonDown) | ✅ | GameControllerの主要ボタン押下をパッド番号・ボタン名で全ゴーストへ通知。追加ボタンは未対応 |
| [`OnGamepadButtonUp`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGamepadButtonUp) | ✅ | GameControllerの主要ボタン解放をパッド番号・ボタン名で全ゴーストへ通知。追加ボタンは未対応 |
| [`OnGamepadAxisMove`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGamepadAxisMove) | ✅ | GameControllerの左右スティック変化を0.08のデッドゾーン付きで全ゴーストへ通知。トリガー軸と通知間引きは未対応 |
| [`OnGamepadConnected`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGamepadConnected) | ✅ | GameController接続時と起動時の接続済みコントローラを0始まり番号で全ゴーストへ通知。実機未確認 |
| [`OnGamepadDisconnected`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnGamepadDisconnected) | ✅ | GameController切断時に割当済みパッド番号を全ゴーストへ通知。実機未確認 |

## バルーンイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnBalloonBreak`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBalloonBreak) | ✅ | 通常トークを別のトークが置き換える時にスクリプト・scope・表示文字位置を通知。生SakuraScriptのバイト位置とは一致しない場合あり |
| [`OnBalloonClose`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBalloonClose) | ✅ | 再生完了後にユーザーがバルーンをクリックして閉じた時、表示スクリプトをReference0へ通知。Playerテストで確認 |
| [`OnBalloonTimeout`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBalloonTimeout) | ✅ | 選択肢のないバルーンが表示期限で閉じる時、スクリプトと残り時間0を通知。Playerテストで確認 |

## トレイバルーンイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnTrayBalloonClick`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnTrayBalloonClick) | ✅ | set,trayballoonをmacOSのメニューバーポップオーバーとして表示し、ポップオーバーまたはステータスアイコンのクリック時にタイトルと本文を通知 |
| [`OnTrayBalloonTimeout`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnTrayBalloonTimeout) | ✅ | メニューバーポップオーバーが指定時間で閉じた時にタイトルと本文を通知。指定時間はSSP互換で10〜30秒に制限 |

## インストールイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnInstallBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnInstallBegin) | ✅ | NARインストール開始前にReferenceなしで発行。実機でのゴースト応答は未確認 |
| [`OnInstallComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnInstallComplete) | ✅ | 各NARの`OnInstallCompleteEx`に応答がない場合、識別子・主項目名・同梱項目名をReference0〜2へ入れて発行。実機応答は未確認 |
| [`OnInstallCompleteEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnInstallCompleteEx) | ✅ | 各NARのインストール後、識別子・名前・インストール先絶対パスをバイト値1区切りでReference0〜2へ通知。実機応答は未確認 |
| [`OnInstallCompleteAll`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnInstallCompleteAll) | ✅ | 複数NARがすべて成功した場合、各完了通知の後に全項目をバイト値1区切りで通知。実機応答は未確認 |
| [`OnInstallFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnInstallFailure) | ✅ | 静的照合ではNARインストール失敗理由をReference0へ通知。実行経路は未確認 |
| [`OnInstallRefuse`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnInstallRefuse) | ✅ | `install.txt`のaccept対象が起動していない場合、対象名・識別子・項目名をReference0〜2へ通知して拒否。実機応答は未確認 |
| [`OnInstallReroute`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnInstallReroute) | ✅ | accept対象が呼び出しゴーストとして起動中なら元ゴーストへ通知し、以降の完了イベントを対象へ転送。実機応答は未確認 |

## ファイルドロップイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnFileDropping`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnFileDropping) | ✅ | ファイルドラッグ進入時に先頭ファイルのパスとscopeをReference0〜1へ通知。サーフェス入力からの経路とイベント生成をテスト済み |
| [`OnFileDropped`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnFileDropped) | ➖ | 旧仕様のため対象外。複数項目とMIME typeを扱えるOnFileDrop2を発行 |
| [`OnFileDrop`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnFileDrop) | ➖ | 旧仕様のため対象外。複数項目とMIME typeを扱えるOnFileDrop2を発行 |
| [`OnFileDropEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnFileDropEx) | ➖ | 旧仕様のため対象外。複数項目とMIME typeを扱えるOnFileDrop2を発行 |
| [`OnFileDrop2`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnFileDrop2) | ✅ | 全ファイル／ディレクトリのパスとMIME typeをバイト値1区切りでReference0・2へ、scopeをReference1へ通知。複数項目の順序とMIME判定をテスト済み |
| [`OnMediaPlayerOpen`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMediaPlayerOpen) | ✅ | `OnFileDrop2`未応答の音声・動画を既定アプリで開いた後、同じReferenceで通知。実機応答は未確認 |
| [`OnPictureViewerOpen`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnPictureViewerOpen) | ✅ | `OnFileDrop2`未応答の画像を既定アプリで開いた後、同じReferenceで通知。実機応答は未確認 |
| [`OnArchiveViewerOpen`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnArchiveViewerOpen) | ✅ | `OnFileDrop2`未応答の一般アーカイブを既定アプリで開いた後、同じReferenceで通知。NARはインストールを優先。実機応答は未確認 |
| [`OnOtherObjectDropping`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherObjectDropping) | ➖ | Windows Shellの仮想オブジェクトを表すイベント。macOSのファイル・URL・テキストDnDは各専用イベントで処理 |
| [`OnOtherObjectDropped`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherObjectDropped) | ➖ | Windows Shellの仮想オブジェクトを表すイベント。macOSのファイル・URL・テキストDnDは各専用イベントで処理 |
| [`OnDirectoryDrop`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDirectoryDrop) | ✅ | ドロップされた各ディレクトリについてパスとscopeをReference0〜1へ個別通知。混在する複数項目をテスト済み |
| [`OnWallpaperChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnWallpaperChange) | ✅ | 画像をサーフェスへドロップして全macOS画面の壁紙変更に成功した時に画像パスを通知 |
| [`OnUpdatedataCreating`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdatedataCreating) | ✅ | `createupdatedata`による`updates2.dau`生成の直前にReferenceなしで通知。フォルダD&Dからの作成UIは未実装 |
| [`OnUpdatedataCreated`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdatedataCreated) | ✅ | `updates2.dau`生成成功後にReferenceなしで通知。実機応答は未確認 |
| [`OnNarCreating`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNarCreating) | ✅ | `createnar`実行直前にinstall.txt由来の名前、出力絶対パス、識別子をReference0〜2へ通知。フォルダD&Dからの作成UIは未実装 |
| [`OnNarCreated`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNarCreated) | ✅ | NAR作成成功後に同じReference0〜2を通知。実機応答は未確認 |

## URLドロップイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnURLDragDropping`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnURLDragDropping) | ✅ | Web URLがサーフェスへ重なった時にURLとscopeを通知。受入可否の詳細判定は未実装 |
| [`OnURLDropping`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnURLDropping) | ✅ | Web URLがサーフェスへドロップされた時にURLとscopeを通知。後続のダウンロード機能は未実装 |
| [`OnURLDropped`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnURLDropped) | ✅ | NARのダウンロード完了後・インストール直前にローカルパス・元URL・scopeを通知。実ネットワークでの確認は未実施 |
| [`OnURLDropFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnURLDropFailure) | ✅ | NAR取得失敗時に空のローカルパス、timeout・HTTP status・fileio、元URL、scopeをReference0〜3へ通知。実ネットワークでの確認は未実施 |
| [`OnURLQuery`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnURLQuery) | ✅ | URL・scope・推定MIME type・nar/unknownを通知し、スクリプト応答時は標準処理を中止。feed・homeurl判定は未対応 |
| [`OnXUkagakaLinkOpen`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnXUkagakaLinkOpen) | ✅ | `x-ukagaka-link`をOSへ登録。eventはghost指定を本体名・キャラクター名と照合し、URLデコード済みinfoをメイン／呼び出しゴーストへ通知。installはNAR取得、homeurlは更新定義取得後のインストールへ接続 |

## ネットワーク更新イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnUpdateProcessExec`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateProcessExec) | ✅ | 更新指示時にmanual・auto・scriptを通知し、応答スクリプトがあれば標準更新を中止。イベント生成テストで確認 |
| [`OnUpdateBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateBegin) | ✅ | ゴースト名・フルパス・ghost・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認 |
| [`OnUpdateReady`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateReady) | ✅ | 更新対象の最終番号・ファイル名一覧・ghost・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認 |
| [`OnUpdateComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateComplete) | ✅ | none／changed・変更ファイル一覧・ghost・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認 |
| [`OnUpdateFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateFailure) | ✅ | 分類した失敗理由・失敗ファイル・ghost・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認 |
| [`OnUpdate.OnDownloadBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdate.OnDownloadBegin) | ✅ | 取得前にファイル名・0始まり番号・最終番号・ghost・更新理由をReference0〜4へ通知。イベント生成テストで確認 |
| [`OnUpdate.OnMD5CompareBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdate.OnMD5CompareBegin) | ✅ | 照合前にファイル名・期待値・実測MD5・ghost・更新理由をReference0〜4へ通知。イベント生成テストで確認 |
| [`OnUpdate.OnMD5CompareComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdate.OnMD5CompareComplete) | ✅ | MD5一致時にファイル名・期待値・実測値・ghost・更新理由をReference0〜4へ通知。イベント生成テストで確認 |
| [`OnUpdate.OnMD5CompareFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdate.OnMD5CompareFailure) | ✅ | MD5不一致時にファイル名・期待値・実測値・ghost・更新理由をReference0〜4へ通知して更新を中断。イベント生成テストで確認 |
| [`OnUpdateOtherBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateOtherBegin) | ✅ | ゴースト以外の更新開始時に名前・フルパス・対象種別・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認 |
| [`OnUpdateOtherReady`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateOtherReady) | ✅ | 更新対象の最終番号・ファイル名一覧・対象種別・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認 |
| [`OnUpdateOtherComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateOtherComplete) | ✅ | none／changed・変更ファイル一覧・対象種別・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認 |
| [`OnUpdateOtherFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateOtherFailure) | ✅ | 分類した失敗理由・失敗ファイル・対象種別・更新理由をReference0・1・3・4へ通知。イベント生成テストで確認 |
| [`OnUpdateOther.OnDownloadBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateOther.OnDownloadBegin) | ✅ | 取得前にファイル名・0始まり番号・最終番号・対象種別・更新理由をReference0〜4へ通知。イベント生成テストで確認 |
| [`OnUpdateOther.OnMD5CompareBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateOther.OnMD5CompareBegin) | ✅ | 照合前にファイル名・期待値・実測MD5・対象種別・更新理由をReference0〜4へ通知。イベント生成テストで確認 |
| [`OnUpdateOther.OnMD5CompareComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateOther.OnMD5CompareComplete) | ✅ | MD5一致時に期待値・実測値・対象種別・更新理由をReference1〜4へ通知。イベント生成テストで確認 |
| [`OnUpdateOther.OnMD5CompareFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateOther.OnMD5CompareFailure) | ✅ | MD5不一致時に期待値・実測値・対象種別・更新理由をReference1〜4へ通知して更新を中断。イベント生成テストで確認 |
| [`OnUpdateCheckComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateCheckComplete) | ✅ | 更新チェック成功時にnone／changed・対象ファイル一覧・対象種別・Reference4=scriptを通知。イベント生成テストで確認 |
| [`OnUpdateCheckFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateCheckFailure) | ✅ | 更新チェック失敗時に分類した失敗理由とReference4=scriptを通知。イベント生成テストで確認 |
| [`OnUpdateResult`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateResult) | ✅ | 複数対象の名前・種別・成否・件数または失敗理由・失敗パスを順番どおりReference0以降へ集約し、Exが無応答の時に通知。イベント生成テストで確認 |
| [`OnUpdateResultEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateResultEx) | ✅ | 複数対象の名前・種別・成否・件数または失敗理由・失敗パスを順番どおりReference0以降へ集約して通知。イベント生成テストで確認 |
| [`OnUpdateCheckResult`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateCheckResult) | ✅ | 複数対象の更新チェック結果を順番どおりReference0以降へ集約し、Exが無応答の時に通知。イベント生成テストで確認 |
| [`OnUpdateCheckResultEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateCheckResultEx) | ✅ | 複数対象の更新チェック結果を順番どおりReference0以降へ集約して通知。イベント生成テストで確認 |
| [`OnUpdateResultExplorer`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnUpdateResultExplorer) | ✅ | コンテンツエクスプローラからの単体・一括更新と修復の結果を旧形式でReference0以降へ集約して通知。イベント生成テストで確認 |

## 時計合わせイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnSNTPBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSNTPBegin) | ✅ | 時計合わせ開始時に接続先サーバをReference0へ通知。共通イベント生成をテスト済み |
| [`OnSNTPCompareEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSNTPCompareEx) | ✅ | 取得時刻・ローカル時刻・符号付き秒差／ミリ秒差をReference0〜4へ通知。時刻比較とイベント生成をテスト済み |
| [`OnSNTPCompare`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSNTPCompare) | ✅ | CompareExが無応答の時に従来形式へフォールバックし、絶対値の秒差／ミリ秒差を通知。時刻比較とイベント生成をテスト済み |
| [`OnSNTPCorrectEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSNTPCorrectEx) | ✅ | `\6`と成功時の通知経路を実装。通常権限ではシステム時刻を変更できないため標準補正器は未接続 |
| [`OnSNTPCorrect`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSNTPCorrect) | ✅ | CorrectExが204の時の従来形式フォールバックを実装。実補正成功時のみ通知します |
| [`OnSNTPFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSNTPFailure) | ✅ | HTTP接続・応答・Date解析の失敗時に接続先サーバをReference0へ通知。共通イベント生成をテスト済み |

## メールチェックイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnBIFFBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBIFFBegin) | ✅ | biffコマンドによるPOP3メールチェック開始時に設定アカウント名を通知 |
| [`OnBIFFComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBIFFComplete) | ✅ | POP3 STAT成功時に通数・総バイト数・アカウント名・前回との差分を通知。LIST・UIDL・ヘッダ一覧は空欄 |
| [`OnBIFF2Complete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBIFF2Complete) | ✅ | 新着がありOnBIFFCompleteが無応答だった場合に通数・総バイト数・アカウント名を通知 |
| [`OnBIFFFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBIFFFailure) | ✅ | POP3設定不足・接続・認証・応答解析失敗を理由とアカウント名付きで通知 |

## ヘッドライン/RSSセンスイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnHeadlinesenseBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnHeadlinesenseBegin) | ✅ | HEADLINE取得開始時にサイト名とURLをReference0〜1へ通知。イベント生成をテスト済み |
| [`OnHeadlinesense.OnFind`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnHeadlinesense.OnFind) | ✅ | 取得項目ごとにサイト名・URL・phase・サニタイズ済み見出しをReference0〜3へ通知。イベント生成をテスト済み |
| [`OnHeadlinesenseComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnHeadlinesenseComplete) | ✅ | 取得成功かつ更新なしの場合にReference0=no updateを通知。イベント生成をテスト済み |
| [`OnHeadlinesenseFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnHeadlinesenseFailure) | ✅ | 取得失敗時はcan't download、解析失敗時はcan't analyzeをReference0へ通知。イベント生成をテスト済み |
| [`OnRSSBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnRSSBegin) | ✅ | サイト名・URLを通知し、無応答時はOnHeadlinesenseBeginへフォールバック。イベント生成をテスト済み |
| [`OnRSSComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnRSSComplete) | ✅ | フィード情報とSSP形式日時を通知。同一内容の再取得はReference0=no updateとし、無応答時はOnHeadlinesense.OnFind／Completeへフォールバック。指紋判定をテスト済み |
| [`OnRSSFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnRSSFailure) | ✅ | can't download／can't analyzeを通知し、無応答時はOnHeadlinesenseFailureへフォールバック。イベント生成をテスト済み |

## カレンダーイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnScheduleTodayNotify`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnScheduleTodayNotify) | ✅ | 予定の追加・編集・削除・取り込みや日付変更で今日の予定が変化した時、全起動ゴーストへNOTIFY |
| [`OnSchedule5MinutesToGo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSchedule5MinutesToGo) | ✅ | 時刻指定予定の5分前にReference0〜3へtype/caption/subtitle/scriptを通知。アプリが停止中だった期間の追跡はしません |
| [`OnScheduleRead`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnScheduleRead) | ✅ | カレンダー詳細の「予定を読む」からReference0〜3を通知。スキンアイコンのホバー読み上げは未実装 |
| [`OnSchedulesenseBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSchedulesenseBegin) | ✅ | 内蔵iCalendarセンサの読み込み開始時にReference0へファイル名、Reference1へURLを全起動ゴーストへ通知。外部calendar pluginは未対応 |
| [`OnSchedulesenseComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSchedulesenseComplete) | ✅ | iCalendar読み込み完了時にReference0へ名前、Reference1へ件数を通知 |
| [`OnSchedulesenseFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSchedulesenseFailure) | ✅ | iCalendarの解析・ファイル入出力失敗時にcan't analyzeまたはcan't downloadをReference0、センサ名をReference1へ全起動ゴーストへ通知 |
| [`OnSchedulepostBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSchedulepostBegin) | ✅ | iCalendar書き出し開始時にReference0=iCalendarで通知 |
| [`OnSchedulepostComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSchedulepostComplete) | ✅ | iCalendar書き出し成功時にReference0=iCalendarで通知。キャンセル・失敗時は完了イベントを発行しません |

## SSTPイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnSSTPBreak`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSSTPBreak) | ✅ | nobreakなしの新しいSSTPが再生中SSTPを中断する際に発行。Reference0は中断スクリプト、Reference1は0。Reference2は現在0固定 |
| [`OnSSTPBlacklisting`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSSTPBlacklisting) | ➖ | UKADOCではMateria専用の送信元ブラックリストイベントであり、SSP互換対象外 |

## その他通信イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnExecuteHTTPComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteHTTPComplete) | ✅ | 取得成功時に小文字のメソッド・識別ID・URL・本文または保存先・HTTPコード・Cookie・全ヘッダをReference0〜6へ通知。標準／独自イベントIDをテスト済み |
| [`OnExecuteHTTPFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteHTTPFailure) | ✅ | HTTPステータス、timeout、fileio、artificial、toomanyredirect等をReference4へ入れ、Completeと同じReference0〜6で通知。イベント生成をテスト済み |
| [`OnExecuteHTTPProgress`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteHTTPProgress) | ✅ | progress-notify指定時に受信済みバイト数と期待総量をデータ受信ごとに通知 |
| [`OnExecuteHTTPStreaming`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteHTTPStreaming) | ✅ | streaming指定時に改行単位の受信データを通知 |
| [`OnExecuteHTTPSSLInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteHTTPSSLInfo) | ✅ | HTTPS通信のTLSバージョン・暗号スイート・証明書概要をURLSession metricsから通知。証明書日時は空欄 |
| [`OnExecuteICalComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteICalComplete) | ✅ | ical-get／ical-postで取得したiCalendarを解析し、カレンダー情報とVEVENTをReference列へ通知。主要フィールドと件数制限に対応 |
| [`OnExecuteICalFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteICalFailure) | ✅ | iCalendarの通信・HTTP・解析失敗をHTTP系と同じReference形式で通知 |
| [`OnExecuteICalProgress`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteICalProgress) | ✅ | --progress-notify指定時にiCalendar取得の進捗を通知 |
| [`OnExecuteICal_SSLInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteICal_SSLInfo) | ✅ | HTTPSでiCalendarを取得した時にTLS情報を通知 |
| [`OnExecuteRSSComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteRSSComplete) | ✅ | RSS各項目をタイトル・URL・SSP形式日時・作者・要約のバイト値1区切りでReference0以降へ通知。標準／独自イベントIDをテスト済み |
| [`OnExecuteRSSFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteRSSFailure) | ✅ | 解析失敗はReference4=parse、通信失敗はHTTPと同じReference0〜6で通知。標準／独自イベントIDをテスト済み |
| [`OnExecuteRSS_SSLInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteRSS_SSLInfo) | ✅ | HTTPSのRSS取得時にHTTPと同じTLS情報を通知。証明書日時は空欄 |
| [`OnExecuteScheduleComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteScheduleComplete) | ✅ | schedule-add／schedule-deleteで共有予定表への登録・削除が完了した時に操作種別とUIDを通知 |
| [`OnExecuteScheduleFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteScheduleFailure) | ✅ | schedule-add／schedule-deleteの入力不正・対象なしを理由とUID付きで通知 |
| [`OnExecuteScheduleGetComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteScheduleGetComplete) | ✅ | schedule-getで共有予定表をiCalendarと同じReference形式で通知 |
| [`OnExecuteFileWatchChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteFileWatchChange) | ✅ | filewatchで指定したファイルまたはディレクトリの作成・更新・削除をdebounce後に通知 |
| [`OnExecuteFileWatchFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteFileWatchFailure) | ✅ | filewatchの監視先ディレクトリがない場合や監視を継続できない場合に理由を通知 |
| [`OnExecuteWebSocketOpen`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteWebSocketOpen) | ✅ | HTTP 101成立後にReference0〜2を発行 |
| [`OnExecuteWebSocketReceive`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteWebSocketReceive) | ✅ | text/binary opcodeと本文またはBase64をReference0〜3へ発行 |
| [`OnExecuteWebSocketReconnect`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteWebSocketReconnect) | ✅ | WebSocket受信失敗後の自動再接続を最大5回行い、試行回数を通知 |
| [`OnExecuteWebSocketClose`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteWebSocketClose) | ✅ | 正常終了、明示的なclose、ユーザー中断時にclose codeまたはuserbreakを通知。異常切断時は再接続へ移行 |
| [`OnExecuteWebSocketFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteWebSocketFailure) | ✅ | 接続・受信エラーから最大5回の自動再接続に失敗した時にreconnect failedを通知 |
| [`OnExecuteWebSocket_SSLInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExecuteWebSocket_SSLInfo) | ✅ | wss接続のTLSバージョンと暗号スイートを通知。証明書subject・issuerは空欄 |
| [`OnPingComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnPingComplete) | ✅ | ping完了を通知するがReference1の送信元アドレスとReference2以降の1応答1Reference構造が未対応 |
| [`OnPingProgress`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnPingProgress) | ✅ | pingの応答行ごとに指定イベントID・ホスト・応答番号・解析した遅延を通知 |
| [`OnNSLookupComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNSLookupComplete) | ✅ | nslookup成功時に指定イベント名・ホスト・lookup/reverse・結果をReference0〜3へ通知。executeタグのコマンド解析とイベント生成をテスト済み |
| [`OnNSLookupFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNSLookupFailure) | ✅ | nslookup失敗時に指定イベント名・ホスト・lookup/reverseをReference0〜2へ通知し、不要なReference3は付けない。イベント生成をテスト済み |

## イベント送信失敗イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnRaisePluginFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnRaisePluginFailure) | ✅ | raisepluginの対象未発見・無効・非200・実行例外時に、理由・対象・イベント・元Referenceを通知し、応答スクリプトを反映 |
| [`OnNotifyPluginFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifyPluginFailure) | ✅ | notifypluginの対象未発見・無効・非200・実行例外時に、理由・対象・イベント・元ReferenceをNOTIFY相当で通知 |
| [`OnRaiseOtherFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnRaiseOtherFailure) | ✅ | raiseotherの宛先がない時はnotfound、宛先SHIORIが204の時は204をReference0へ入れ、宛先・イベントID・元Referenceとともに送信元へ通知。全ゴースト宛ての複数結果列挙は未対応 |
| [`OnNotifyOtherFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifyOtherFailure) | ✅ | notifyotherの宛先がない時にnotfoundをReference0へ入れ、宛先・イベントID・元Referenceとともに送信元へ通知。全ゴースト宛ての複数結果列挙は未対応 |

## 見切れ・重なりイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnOverlap`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOverlap) | ✅ | 同一ゴースト内の表示中サーフェス同士の重なり状態が変化した時、現在と直前のscope組を通知 |
| [`OnOtherOverlap`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherOverlap) | ✅ | 呼び出しゴーストを含む全表示サーフェスの重なり状態が変化した時、現在と直前のSakura名/scope組を通知 |
| [`OnOffscreen`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOffscreen) | ✅ | サーフェスが全画面の作業領域内に収まるかを1秒ごとに確認し、状態変化時に現在と直前のscope一覧を通知 |
| [`OnOtherOffscreen`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherOffscreen) | ✅ | 呼び出しゴーストを含む見切れ状態の変化時、現在と直前のSakura名/scope一覧を通知 |

## ネットワーク状態イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnNetworkHeavy`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNetworkHeavy) | ✅ | SakuraScriptのHTTP/RSS要求が設定時間でタイムアウトした時、設定秒数と経過秒数を通知。HEADLINEや更新通信は未接続 |
| [`OnNetworkStatusChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNetworkStatusChange) | ✅ | Network.frameworkで起動時と接続状態変化時にonline/offline・IP一覧・wifi/ethernet/cellular等・従量制状態を通知。通信速度は0 |

## OS状態イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnScreenSaverStart`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnScreenSaverStart) | ✅ | macOS分散通知でスクリーンセーバ開始を検出。名称は固定、実行ファイルと待ち時間は空欄 |
| [`OnScreenSaverEnd`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnScreenSaverEnd) | ✅ | macOS分散通知でスクリーンセーバ終了を検出。名称は固定、実行ファイルと待ち時間は空欄 |
| [`OnSessionLock`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSessionLock) | ✅ | macOSユーザーセッションが非アクティブになった時に通知。実機ロックでの実動未確認 |
| [`OnSessionUnlock`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSessionUnlock) | ✅ | macOSユーザーセッションが再びアクティブになった時に通知。実機ロック解除での実動未確認 |
| [`OnSessionDisconnect`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSessionDisconnect) | ✅ | macOSユーザーセッションが非アクティブになった時にLockと併せて通知。簡易ユーザー切替と画面ロックを区別しません |
| [`OnSessionReconnect`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSessionReconnect) | ✅ | macOSユーザーセッションがアクティブへ戻った時にUnlockと併せて通知。簡易ユーザー切替と画面ロックを区別しません |
| [`OnCPULoadHigh`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnCPULoadHigh) | ✅ | OS全体のCPU使用率が80%以上で5秒間隔3回続いた時に現在率をReference0へ通知。状態遷移テストで確認 |
| [`OnCPULoadLow`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnCPULoadLow) | ✅ | CPU High通知後に使用率が60%未満へ戻った時、現在率をReference0へ通知。状態遷移テストで確認 |
| [`OnMemoryLoadHigh`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMemoryLoadHigh) | ✅ | VM統計のメモリ使用率が80%以上で5秒間隔3回続いた時に現在率をReference0へ通知。状態遷移テストで確認 |
| [`OnMemoryLoadLow`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMemoryLoadLow) | ✅ | Memory High通知後に使用率が60%未満へ戻った時、現在率をReference0へ通知。状態遷移テストで確認 |
| [`OnDisplayChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDisplayChange) | ✅ | 画面構成変更時にプライマリ画面のbpp・幅・高さをReference0〜2へ通知。起動時NOTIFYは未対応 |
| [`OnDisplayHandover`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDisplayHandover) | ✅ | シェル位置の初期化時と別スクリーンへの移動時に、scopeと移動前後の画面座標・色深度・主画面フラグを通知 |
| [`OnDisplayChangeEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDisplayChangeEx) | ✅ | 画面構成変更時にupdateと全画面の矩形・色深度・プライマリ判定を通知。macOSにはタスクバーがないため末尾はunknown,0。起動時initは未対応 |
| [`OnDisplayPowerStatus`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDisplayPowerStatus) | ✅ | macOSのスリープ直前に0、復帰時に1を通知。単独ディスプレイの電源断は検出しません |
| [`OnBatteryNotify`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBatteryNotify) | ✅ | 起動時と30秒ごとの状態変化時に残量・残り分数・給電状態・状態フラグを通知。バッテリーなしもno_batteryとして通知 |
| [`OnBatteryLow`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBatteryLow) | ✅ | 残量が33%以下へ遷移した時にOnBatteryNotifyと同じReferenceを通知 |
| [`OnBatteryCritical`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBatteryCritical) | ✅ | 残量が5%以下へ遷移した時にOnBatteryNotifyと同じReferenceを通知 |
| [`OnBatteryChargingStart`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBatteryChargingStart) | ✅ | 充電状態への遷移時にOnBatteryNotifyと同じReferenceを通知 |
| [`OnBatteryChargingStop`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBatteryChargingStop) | ✅ | 非充電状態への遷移時にOnBatteryNotifyと同じReferenceを通知 |
| [`OnDeviceArrival`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDeviceArrival) | ✅ | macOSでボリュームがマウントされた時、volume・名前・空の製造者・パスをバイト値1区切りで通知。一般USB機器は対象外 |
| [`OnDeviceRemove`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDeviceRemove) | ✅ | macOSでボリュームがアンマウントされた時、OnDeviceArrivalと同形式で通知。一般USB機器は対象外 |
| [`OnTabletMode`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnTabletMode) | ➖ | macOSに対応するタブレットモードがないため対象外 |
| [`OnDarkTheme`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDarkTheme) | ✅ | 起動時とアプリ再アクティブ化時にmacOSのダークモード状態をReference0〜1へ通知。非アクティブ中の変更は復帰時通知 |
| [`OnDesktopWallpaperChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnDesktopWallpaperChange) | ✅ | 起動時はNOTIFY、macOSの壁紙変更時はGETで、画面・画像パス・表示方法・背景色を通知。状態遷移とReferenceを自動テスト済み |
| [`OnWindowModeChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnWindowModeChange) | ✅ | 起動時とウインドウモード切替時に現在・直前のモードを通知し、切替時はOnDisplayChangeも発行 |
| [`OnOSUpdateInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOSUpdateInfo) | ✅ | macOSのsystem_profilerインストール履歴から直近20件の名称・版・導入日を起動時に通知。Windows固有項目は空欄 |
| [`OnRecycleBinEmpty`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnRecycleBinEmpty) | ✅ | emptyrecyclebinでユーザーの~/.Trashを空にし、前後の件数・容量と成否を通知 |
| [`OnRecycleBinEmptyFromOther`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnRecycleBinEmptyFromOther) | ✅ | 他ゴーストがemptyrecyclebinを実行した時に同じ結果を通知 |
| [`OnRecycleBinStatusUpdate`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnRecycleBinStatusUpdate) | ✅ | 起動時と5秒ごとの変化時にmacOSゴミ箱内の通常ファイル数・合計サイズ・直前との差を通知。外部ボリュームのゴミ箱と隠しファイルは対象外 |

## 選択領域モードイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnSelectModeBegin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSelectModeBegin) | ✅ | enter,selectrectで全画面の矩形選択オーバーレイを開始して通知 |
| [`OnSelectModeCancel`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSelectModeCancel) | ✅ | selectrectをEscまたは選択未完了で終了した時に通知 |
| [`OnSelectModeComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSelectModeComplete) | ✅ | leave,selectrectで選択矩形の画面座標を通知 |
| [`OnSelectModeMouseDown`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSelectModeMouseDown) | ✅ | 矩形選択開始点をクリックした時にscope・モード・画面座標を通知 |
| [`OnSelectModeMouseUp`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSelectModeMouseUp) | ✅ | 矩形選択終了点でボタンを離した時にscope・モード・画面座標を通知 |

## 音声認識・合成イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnSpeechSynthesisStatus`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSpeechSynthesisStatus) | ✅ | 起動時と音声合成のON/OFF時に有効状態を通知 |
| [`OnVoiceRecognitionStatus`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnVoiceRecognitionStatus) | ✅ | 起動時とmacOS音声認識のON/OFF時に有効状態を通知 |
| [`OnVoiceRecognitionWord`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnVoiceRecognitionWord) | ✅ | 確定した認識結果だけを通知。キャラクター名と完全一致した場合は対応scopeをReference0に設定 |

## その他イベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`OnKeyPress`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnKeyPress) | ✅ | Utataneがアクティブな時のkeyDownを文字・macOS keyCode・repeat・scope・修飾キーで通知。Reference1はWin32仮想キーコードではありません |
| [`OnRecommendsiteChoice`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnRecommendsiteChoice) | ✅ | おすすめ・ポータルメニュー選択時にサイト名・URL・バナー・種別・選択scope・0始まりの位置をReference0〜5へ通知。イベント生成テストで確認 |
| [`OnTranslate`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnTranslate) | ✅ | イベント応答の再生前に元スクリプト・イベントID・Reference等で同じSHIORIを再呼出しし、応答があれば置換 |
| [`OnAITalk`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnAITalk) | ✅ | \a・手動ランダムトークからGETで発行。Referenceなし |
| [`OnOtherGhostTalk`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnOtherGhostTalk) | ✅ | set,otherghosttalkでopt-inしたゴーストへ他ゴーストの再生前または再生後のスクリプトと発生元情報を通知 |
| [`OnEmbryoExist`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnEmbryoExist) | ➖ | Windows用Materiaの同時起動検出イベントでありmacOS版では対象外 |
| [`OnNekodorifExist`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNekodorifExist) | ➖ | Windows用猫どりふの同時起動検出イベントでありmacOS版では対象外 |
| [`OnSoundStop`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSoundStop) | ✅ | SakuraScript音声の自然終了とstop操作でファイル名・end/closeを通知。ループ終了など全経路は未確認 |
| [`OnSoundLoop`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSoundLoop) | ✅ | SakuraScriptのループ音声が末尾から次の周回へ入るたびにファイル名をReference0へ通知。周回・終了・失敗の判定を自動テスト済み |
| [`OnSoundError`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnSoundError) | ✅ | 音声ファイル解決・AVAudioPlayer生成・再生終了失敗時にplay・エラーコード・ファイル・説明を通知。実動未確認 |
| [`OnMusicPlayEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMusicPlayEx) | ✅ | 設定有効時、ブラウザ以外の曲変更を検出して通知。無反応ならOnMusicPlayへフォールバック。判定不能な再生元もこちらへ送る。実アプリでの通知は未確認 |
| [`OnMusicPlay`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnMusicPlay) | ✅ | 拡張イベントへの無反応時にタイトル・アーティストを通知。SSTP/1.1のSongヘッダ経路も対応 |
| [`OnVideoPlayEx`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnVideoPlayEx) | ✅ | MediaRemoteの親アプリまたは再生クライアントのbundle IDから主要ブラウザを判定し、動画・音楽を共通Referenceで通知。メイン・呼び出しゴーストの両経路へ接続済み。実ブラウザでの通知は未確認 |
| [`OnTextDrop`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnTextDrop) | ✅ | サーフェスへのテキストDnDで改行をバイト値1に変換し本文とscopeを通知。イベント生成テストで確認 |
| [`OnShellScaling`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnShellScaling) | ✅ | 設定でシェル倍率が変わった時に新旧の縦横パーセントをReference0〜3へ通知。縦横個別設定は未実装 |
| [`OnBalloonScaling`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnBalloonScaling) | ✅ | 設定でバルーン倍率が変わった時に新旧の縦横パーセントをReference0〜3へ通知。縦横個別設定は未実装 |
| [`OnLanguageChange`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnLanguageChange) | ✅ | 起動時に現在の言語名とLocale IDをReference0〜1へ通知。実行中の言語変更監視とUtatane言語フォルダ・ヘルプURLは未対応 |
| [`OnResetWindowPos`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnResetWindowPos) | ✅ | コンテキストメニューのウインドウ位置初期化で通知してからシェル・バルーン位置を初期化。無応答時のみ実行する制御は未対応 |
| [`OnExtractArchiveComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExtractArchiveComplete) | ✅ | 実際のZIP展開成功後に書庫・出力先・形式・ユーザーIDをReference0〜3へ通知。展開処理とイベント生成をテスト済み |
| [`OnExtractArchiveFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnExtractArchiveFailure) | ✅ | ZIP展開失敗時に対象書庫とエラー内容をReference0〜1へ通知。失敗経路とイベント生成をテスト済み |
| [`OnCompressArchiveComplete`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnCompressArchiveComplete) | ✅ | 実際のZIP圧縮成功後にファイル・出力先・形式・ユーザーIDをReference0〜3へ通知。圧縮処理とイベント生成をテスト済み |
| [`OnCompressArchiveFailure`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnCompressArchiveFailure) | ✅ | ZIP圧縮失敗時に対象ファイルとエラー内容をReference0〜1へ通知。失敗経路とイベント生成をテスト済み |
| [`property.get`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#property.get) | ✅ | activeghostlist.extの対象ゴーストへ拡張プロパティ取得を中継 |
| [`property.set`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#property.set) | ✅ | activeghostlist.extの対象ゴーストへ拡張プロパティ設定を中継 |

## Notifyイベント

| イベント | 状況 | Utataneの挙動・差分 |
| --- | --- | --- |
| [`basewareversion`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#basewareversion) | ✅ | 起動時にUtataneの表示バージョン・本体名・ビルド番号をNOTIFY。SSPの数値形式との完全一致は未確認 |
| [`hwnd`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#hwnd) | ✅ | 起動時に各scopeのNSWindow番号をバイト値1区切りでNOTIFY。macOSのwindowNumberでありWindows HWNDではなく、未生成バルーンは空欄 |
| [`uniqueid`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#uniqueid) | ✅ | 起動時にゴーストのインストールディレクトリ名を一意IDとしてNOTIFY。SSTPでの利用は未確認 |
| [`capability`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#capability) | ✅ | 起動時にUtataneが扱う主要SHIORIリクエスト・レスポンスヘッダをNOTIFY。拡張ヘッダの網羅は未対応 |
| [`ownerghostname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#ownerghostname) | ✅ | 起動時に現在のゴースト名をReference0へNOTIFY |
| [`otherghostname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#otherghostname) | ✅ | 起動時に呼び出し起動中の他ゴースト名とscope 0/1のsurface番号をバイト値1区切りでNOTIFY。通常起動側から見える呼出ゴーストのみ |
| [`installedsakuraname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#installedsakuraname) | ✅ | 起動時に全インストール済みゴーストのscope 0名を同一順序のReference列へNOTIFY |
| [`installedkeroname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#installedkeroname) | ✅ | 起動時に全インストール済みゴーストのscope 1名を同一順序のReference列へNOTIFY |
| [`installedghostname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#installedghostname) | ✅ | 起動時に全インストール済みゴースト名をReference列へNOTIFY |
| [`installedshellname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#installedshellname) | ✅ | 起動中ゴーストにインストールされたシェル名をReference列へNOTIFY。他ゴーストのシェルは含めません |
| [`installedballoonname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#installedballoonname) | ✅ | 起動時に全インストール済みバルーン名をReference列へNOTIFY |
| [`installedheadlinename`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#installedheadlinename) | ✅ | 起動時に全インストール済みRSS・ヘッドライン名をReference列へNOTIFY |
| [`installedcalendarskinname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#installedcalendarskinname) | ✅ | 起動時に利用可能なカレンダースキン名をReference列へNOTIFY |
| [`installedcalendarpluginname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#installedcalendarpluginname) | ✅ | 起動時に空のNOTIFYを送り、利用可能な外部カレンダープラグインがない状態を通知 |
| [`installedplugin`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#installedplugin) | ✅ | 起動時に認識済みプラグインの「名前、ID」をバイト値1で結合し、Reference列へNOTIFY。ネイティブSHIORI型のロード、定期イベント、メニュー・SakuraScript明示呼び出しを接続 |
| [`configuredbiffname`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#configuredbiffname) | ✅ | 起動時に本体設定で利用可能なPOP3アカウント名をNOTIFY。パスワードはmacOS Keychainへ保存 |
| [`ghostpathlist`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#ghostpathlist) | ✅ | 起動時に有効な全ゴーストフォルダの絶対パスを優先順でNOTIFY。DebugではBundledも含みます |
| [`balloonpathlist`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#balloonpathlist) | ✅ | 起動時に有効な全バルーンフォルダの絶対パスを優先順でNOTIFY。DebugではBundledも含みます |
| [`headlinepathlist`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#headlinepathlist) | ✅ | 起動時に有効な全ヘッドラインフォルダの絶対パスを優先順でNOTIFY |
| [`pluginpathlist`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#pluginpathlist) | ✅ | 起動時に有効な全プラグインフォルダの絶対パスを優先順でNOTIFY。DebugではLocalも含みます |
| [`calendarskinpathlist`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#calendarskinpathlist) | ✅ | 起動時にカレンダースキン格納パスをNOTIFY |
| [`calendarpluginpathlist`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#calendarpluginpathlist) | ✅ | 起動時にカレンダープラグイン格納パスをNOTIFY |
| [`rateofusegraph`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#rateofusegraph) | ✅ | 起動中ゴーストをboot状態の1レコードとしてNOTIFY。起動回数・時間・割合は0固定で履歴集計は未実装 |
| [`enable_log`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#enable_log) | ✅ | 起動時にUtataneのアプリ内ログが有効であることをReference0=1でNOTIFY。SSP開発パレット相当の切替UIは未実装 |
| [`enable_debug`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#enable_debug) | ✅ | 起動時にDebugビルドなら1、Releaseなら0をReference0へNOTIFY。実行中の切替UIは未実装 |
| [`OnNotifySelfInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifySelfInfo) | ✅ | 起動時にゴースト・キャラクター・シェル・バルーンの名前と絶対パスをReference0〜6へNOTIFY |
| [`OnNotifyBalloonInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifyBalloonInfo) | ✅ | 起動時にバルーン名・絶対パス・検出したsakura/kero画像番号を通知。追加キャラクター用画像番号は未対応 |
| [`OnNotifyShellInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifyShellInfo) | ✅ | 起動時にシェル名・絶対パス・定義済みsurface番号一覧をReference0〜2へNOTIFY |
| [`OnNotifyDressupInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifyDressupInfo) | ✅ | bind変更後に全着せ替え情報をバイト値1区切りで通知。起動時NOTIFYとuser操作GETは未対応 |
| [`OnNotifyUserInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifyUserInfo) | ✅ | 起動時にmacOSアカウント名とフルネームを通知。誕生日は空、性別はundef固定 |
| [`OnNotifyOSInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifyOSInfo) | ✅ | 起動時にmacOS・CPUコア数・物理メモリ・uptimeをReference0〜3へNOTIFY。CPUクロックと仮想メモリは概算値 |
| [`OnNotifyFontInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifyFontInfo) | ✅ | 起動時にmacOSで利用可能なフォント名をReference列へNOTIFY。フォント変更の動的再通知は未対応 |
| [`OnNotifyInternationalInfo`](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html#OnNotifyInternationalInfo) | ✅ | 起動時にUTC時差・夏時間・国・言語コードをReference0〜3へNOTIFY。Locale未設定時は空欄 |

## 更新ルール

- 実装または調査時に、発生条件・Reference・GET/NOTIFY・応答利用の4点を確認します。
- ✅へ変更する場合は、テストまたは実機確認の根拠を備考に残します。
- UKADOC側の増減確認には生成スクリプトを使い、既存の手動判定を上書きしないよう差分を確認します。
- 外部からのSHIORI EventとSHIORI Resourceは、この表とは分けて管理します。
