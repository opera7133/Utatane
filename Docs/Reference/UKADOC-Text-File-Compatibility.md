# UKADOC テキストファイル互換状況

ゴーストの設定や配布に使うテキストファイルについて、Utataneが読み取る項目と、実際の動作に使う項目をまとめています。項目の基準はUKADOCです。

調査日: 2026-09-21
調査対象: [UKADOC](https://ssp.shillest.net/ukadoc/manual/)とUtatane本番Swiftコード・テスト

## 判定

| 記号 | 意味 |
| --- | --- |
| ✅ | UKADOCにある構文・項目を一通り読み込み、対応する機能で利用します |
| 🟡 | ファイルは読み込むが、未使用の項目・構文・挙動が残ります |
| ❌ | ファイルまたは対応する本体機能が未実装 |

設定を読み取るだけでは「対応」にしません。その値が表示や動作に反映されることを判定の基準にしています。

## 全体

| ファイル | 状況 | 現在の実装 | 主な不足 |
| --- | --- | --- | --- |
| Ghost `descript.txt` | 🟡 | UTF-8／Shift_JIS、基本情報、SHIORI名、キャラクター名、既定surface・shell・balloon、初期配置、MenuBarアイコン、shell側キャラクター名の上書き可否、SSTPの無指定送信・COMMUNICATE受信制御、更新URL、README | 74項目中、SSTP常時変換、SHIORI詳細設定、カーソル、メニュー、最小化アイコン、推奨balloon等が未反映 |
| Shell `descript.txt` | 🟡 | UTF-8／Shift_JIS、名前、`seriko.use_self_alpha`（`full`を含む）、bindgroup／bindoption、着せ替えmenuitem、初期位置・上下配置、z-order、sticky-window、balloonのoffset／alignment／dontmove／syncscale | 102項目中、画像ベース座標の全用途、オーナードローメニュー装飾、DPI、透過・crossfade等が未反映 |
| Balloon `descript.txt` | 🟡 | UTF-8／Shift_JIS、名前・type、文字領域、折返し、基本フォント、装飾・shadow、scroll arrow／clickwaitmarker／online marker／SSTP marker／number、cursor／anchor／anchor.visited、透過方式、windowposition、入力欄 | 162項目中、blendmethod、recommended ghost等が未反映 |
| Plugin `descript.txt` | 🟡 | UTF-8／Shift_JIS／ASCII、name、id、filename、type、charset、作者、更新URL、README、secondchangeinterval、otherghosttalkを読み込み、SHIORI／dylib／Windows DLLへ分類。Utatane拡張の`filename.macos`でmacOS用モジュールを優先指定可能。メニューから実行、README表示、ネットワーク更新が可能。ネイティブSHIORI型は実体をロードし、OnSecondChange・OnMenuExec・raiseplugin／notifypluginを配送。AKARIの`_create_thread`は独立評価ワーカーで実行し、変更されたグローバル変数を完了時に反映。YAYA製wallet_of_unyuとAKARI製sudohaikuyuは実ファイルでOnMenuExecを確認。macOS dylibは標準`loadu/load`・`unload`・`request`を優先 | dylib実物とWine DLL、AKARIワーカー内の外部通信を伴う長時間処理は未確認 |
| Headline `descript.txt` | 🟡 | UTF-8／Shift_JIS／ASCII、名前、DLL名、URL、open URL、homeurl、charset、alwaysdisplay、readme、readme.charset。RSS用`type`・`feed`拡張も利用 | UKADOC掲載項目は保持・利用。Windows DLL実行は実行環境依存 |
| `install.txt` | 🟡 | UTF-8／Shift_JIS、name、type、directory、accept、複数インストールpackage、bootghost、Ghost／Shell同梱の複数balloon・headline・plugin・calendar.skin・calendar.plugin、安全な新規インストールに加え、refreshとrefreshundeletemaskをバックアップ付き置換で実装 | supplement・languageは未対応 |
| `delete.txt` | ✅ | UTF-8／Shift_JIS、charset行、Windows区切りの相対ファイル・ディレクトリを事前検証し、更新ファイルの置換と同じロールバック境界で安全に削除 | — |
| `developer_options.txt` | 🟡 | `noupdate`／`nonar`に加え、`.narignore`／`.updateignore`／`.narinclude`／`.updateinclude`の主要gitignore構文と`include:`を各生成処理へ反映 | 文字クラス・エスケープ等、gitignoreの全細則は未対応 |
| `surfaces.txt`／`surfaces*.txt` | 🟡 | 複数ファイルをファイル名順に読み、各ファイルのdescript設定を分離。surface selector、append、alias、PNG／APNG／GIF／WebPのelement、rect／ellipse／circle／polygon／region collision、主要animationとoption | 保持だけのsurface属性が未対応 |
| `surfaces2.txt` | ✅ | 他の`surfaces*.txt`と同様にファイル名順で読み、先行定義への追記・上書きを反映 | — |
| `alias.txt` | 🟡 | surfaces文書として追加読込し、sakura／kero／char scope aliasを利用 | alias以外の互換挙動は未照合 |
| `surfacetable.txt` | ✅ | charset、version、option、group、scope、surface IDと名前を解析。`DisableNoDefineSurfaces`、`__disabled`、`__parts`も利用 | 実機UIでの全表示差は未確認 |
| `updates2.dau` | 🟡 | path・MD5・size・date・charsetを解析し、取得・サイズ／MD5検証・`delete.txt`を含むロールバック更新。生成はCRLFで拡張フィールドも出力 | date・charsetは保持のみ |
| `updates.txt` | 🟡 | `charset,`と`file,`行、path・MD5・拡張フィールド、未知行の無視に対応 | Version 3形式の生成は未対応 |
| `readme.txt`／`readme.md` | 🟡 | Ghost／選択中Shell／Balloon／Headlineのdescript.txtにあるreadme指定と既定候補を安全に解決し、macOSの関連アプリで開きます。readme.charsetも保持 | Markdownの独自表示はせず、文字コードの最終的な解釈は関連アプリに依存 |

現状は ✅ 3 / 🟡 12 / ❌ 0。

## Ghost descript.txt

UKADOC掲載は74項目。汎用パーサーはコメントと空行を除いた`key,value`を保持するが、実際に利用するのは次の項目群。

| 状況 | 項目 |
| --- | --- |
| 利用 | `name`、`shiori`、`balloon`、`sakura.name`、`kero.name`、`char*.name` |
| Utatane拡張 | `shiori.macos`で汎用macOS SHIORIまたはSHIOLINKを優先指定。指定がなければ従来の`shiori`を使用（[開発者向けガイド](../Creators/SHIORI-Development.md)） |
| 利用 | `sakura.seriko.defaultsurface`、`kero.seriko.defaultsurface`、`char*.seriko.defaultsurface` |
| 利用 | `balloon.defaultsurface`、scope別`balloon.defaultsurface` |
| 利用 | `seriko.defaultsurfacedirectoryname`。指定したディレクトリが存在しない場合は`master`へフォールバック |
| 利用 | `seriko.alignmenttodesktop`、scope別`seriko.alignmenttodesktop`、`defaultleft`／`defaulttop`。Ghost全体＜Ghost scope別＜Shell全体＜Shell scope別の順で優先し、利用者が保存した位置があれば保存値を優先 |
| 保持 | scope別`defaultx`／`defaulty`。画像ベース座標を使う機能には未接続 |
| 利用 | `balloon.dontmove`／`balloon.syncscale`。Shell側にscope別指定があればShellの値を優先 |
| 利用 | `icon`。Ghost master配下の画像をMenuBarアイコンとして使い、読めない場合はUtatane標準アイコンへフォールバック |
| 利用 | `name.allowoverride`。0の場合はShell側の`sakura.name`／`kero.name`／`sakura.name2`で名前を上書きしない |
| 利用 | `sstp.allowunspecifiedsend`、`sstp.allowcommunicate`。前者が0なら対象名のないSSTPを受けず、後者が0ならCOMMUNICATEを拒否 |
| 別経路で利用 | `homeurl`、`readme`、`readme.charset` |
| 未反映 | charset宣言、作者・ID・title、`sstp.alwaystranslate`、SHIORI version/cache/encoding、イベント抑制、カーソル、`icon.minimize`、メニュー、推奨balloon関連 |

項目名は大文字小文字を区別しません。文字コードはファイル内`charset`ではなく、UTF-8を試してからShift_JISへフォールバックするため、宣言と実際の文字コードが違っていても読み込めます。

## Shell descript.txt

UKADOC掲載は102項目。現在利用するのはかなり限定的。

| 状況 | 項目 |
| --- | --- |
| 利用 | `name`、`seriko.use_self_alpha`（`1`／`true`／`full`）、`seriko.zorder`、`seriko.sticky-window`、`seriko.alignmenttodesktop` |
| 利用 | scope別`bindgroup*.name/default/addid` |
| 利用 | scope別`bindoption*.group`の`mustselect`・`multiple` |
| 利用 | scope別`menuitem*`／`menuitemex*`の着せ替え順序・区切り・表示名、`menu,hidden` |
| 利用 | scope別`seriko.alignmenttodesktop`、`defaultleft/top`、balloonの`offsetx/y/xl/xr/yl/yr`・`alignment`・`dontmove`・`syncscale` |
| 保持 | scope別`defaultx/defaulty` |
| 別経路で利用 | `readme`、`readme.charset` |
| macOS代替 | menuのフォント・色・背景・サイドバー画像は、アクセシビリティとOSテーマに従うmacOS標準メニューを使用するためオーナードローしません |
| 未反映 | 基本メタデータ、名前上書き、画像ベース座標の全用途、DPI、透過・crossfade、アイコン枠色 |

保存済みの利用者位置がある場合はそちらを優先し、未保存時だけShell `descript.txt`の初期位置を使います。

## Balloon descript.txt

UKADOC掲載は162項目。現在の実利用項目は以下。

| 状況 | 項目 |
| --- | --- |
| 利用 | `type`、`name`、`origin.x/y`、`validrect.left/top/right/bottom`、`wordwrappoint.x/y`、`vertical` |
| 利用 | `font.name`、`font.height`、`font.color.r/g/b`、`font.shadowcolor.r/g/b`、`font.shadowstyle` |
| 利用 | `font.bold`、`font.italic`、`font.underline`、`font.strike`、`font.outline`、`arrow0.x/y`、`arrow1.x/y`、`clickwaitmarker.x/y` |
| 利用 | `onlinemarker.x/y`、`onlinemarker.interval`。`online0.png`から始まる連番画像を`onlinemode`中にアニメーション表示 |
| 利用 | `sstpmarker.x/y`、`sstpmessage.font.name/height/color`、`sstpmessage.x/y/xr/yb`。SSTP受信トークでmarker画像とSenderを表示 |
| 利用 | `number.font.name/height/color`、`number.xr/y`、`use_self_alpha`（`full`を含む）、`windowposition.x`、`windowposition.y`、`windowposition.limit` |
| 利用 | `communicatebox.font.name/height/color`、`communicatebox.background.color`、`communicatebox.x`、`communicatebox.y`、`communicatebox.width`、`communicatebox.height` |
| 画像として利用 | `balloonc1.png`／`balloonc2.png`／`balloonc3.png`と対応する`balloonc*s.txt`を、communicatebox／teachbox／inputboxのネイティブ入力パネルへ反映 |
| 利用 | cursor、cursor.notselect、anchor、anchor.notselect、anchor.visitedの`style`、font／pen／brush RGB。訪問済みアンカーはゴーストの実行中にID単位で保持 |
| 画像として利用 | balloon画像、marker画像、clickwaitmarker／arrow／online／SSTP marker画像。`balloons*s.txt`等のサーフェス別上書きと`marker.filename`／`clickwaitmarker.filename`／`arrow.filename`／`onlinemarker.filename`／`sstpmarker.filename`を反映 |
| 別経路で利用 | `readme`、`readme.charset` |
| 未反映 | disable.font、blendmethod、入力画像上のボタン自体のオーナードロー、recommended ghost |

`origin`が0または未定義なら横書きは`validrect.left/top`、縦書きは`validrect.right/top`へフォールバックします。縦書きでは`wordwrappoint.y`（未定義時は`validrect.bottom`）で下端を決め、文字を上から下、列を右から左へ配置します。入力欄は従来どおり横書き。

## Headline descript.txt

UKADOC掲載9項目のうち、`charset`、`name`、`dllname`、`url`、`openurl`、`alwaysdisplay`をカタログで利用します。`homeurl`は共通のネットワーク更新URL探索で利用し、`readme`と`readme.charset`は設定画面のREADME表示導線で利用します。

RSS型についてはUKADOCのHEADLINE DLL項目に加え、`type,rss`と`feed,URL`をUtatane拡張として扱います。

## install.txt

UKADOC掲載の主要15項目・構文に対する状況。

| 項目・構文 | 状況 | 備考 |
| --- | --- | --- |
| charset | 🟡 | 宣言値は参照せずUTF-8→Shift_JISで判定 |
| name | ✅ | インストール結果の表示名に利用 |
| type | 🟡 | ghost、shell、balloon、headline、packageに対応。他種別は拒否 |
| directory | ✅ | 1階層の安全な名前に限定して利用 |
| accept | 🟡 | 起動中の本体側名・キャラクター名を照合し、対象不在時は拒否、呼び出しゴーストなら完了通知を転送。実機確認は未実施 |
| bootghost | ✅ | package内で指定されたディレクトリのゴーストを、全オブジェクトのインストール完了後に選択・起動 |
| refresh | ✅ | `1`の場合のみ既存内容をバックアップして置換し、失敗時は旧内容へ復元 |
| refreshundeletemask | ✅ | コロン区切りのファイル名を全階層で保持。NAR側に同名の新ファイルがある場合は新内容を優先 |
| `*.directory`／`*.source.directory` | 🟡 | Ghost／Shell同梱のballoon・headlineと、末尾番号による複数同梱に対応 |
| `*.refresh`／`*.refreshundeletemask` | ✅ | 同梱balloon・headline・plugin・calendar.skin・calendar.pluginの各項目に対応 |
| developer_optionsの相対パス規則 | ✅ | `noupdate`／`nonar`のファイル・フォルダ・glob指定を各生成処理へ反映 |

アーカイブについてはWindows式バックスラッシュを区切りとして安全に正規化してから、パストラバーサル、絶対パス、正規化後の衝突、シンボリックリンク、特殊ファイル、過大な件数・容量を拒否し、途中失敗時は作成済み項目を戻します。これはUKADOC互換とは別の安全策。

## surfaces.txt・alias.txt

UKADOCの定義項目・キーワードは137。現在の対応範囲は次の通り。

| 分類 | 状況 | 対応内容 |
| --- | --- | --- |
| surface選択 | ✅ | 単一ID、範囲、列挙、`!`による除外、`surface.append`を解析し、定義の追加・上書きへ反映 |
| alias | ✅ | sakura、kero、char scopeの名前からsurface ID候補を選び、`\s[識別子]`の解決に利用 |
| element | ✅ | PNG／APNG／GIF／WebPとPNA、base・overlay系・asisに対応。elementでは適用外の描画メソッドをSSP同様overlayとして扱います。`seriko.use_self_alpha,1`ではアルファチャンネルのない画像を左上色透過へフォールバックし、`full`では全面を不透明として扱います。アニメーション画像はフレーム時間・合成・破棄方式を含めて再生し、PNA適用後、element合成後、異なるフレーム周期を持つ画像同士の合成後も再生情報を維持します |
| collision | ✅ | 矩形とcollisionex rect／ellipse／circle／polygon／regionを実際のマウス判定に利用。regionはShell内の画像にある指定RGB色、または反転指定時は指定色以外の画素を判定領域にします |
| animation基本 | 🟡 | name、interval文字列、pattern、wait、座標。複数animationを独立したTaskとレイヤー状態で並行再生し、base・overlay系・asis・moveと各種制御を反映 |
| interval | 🟡 | runonce、sometimes、rarely、random、periodic、always、talk（文字数指定を含む）、starttalk、endtalk、yen-e、bindを実行。neverは自動実行しない定義として機能 |
| pattern method | 🟡 | base、overlay、overlay-fast、replace、interpolate、reduce、bind、add、auto、asis、move、scaling、insert、start／stop、alternative／parallel系、APNG／GIF／WebPのimportに加え、multiply／screen／overlay／add／soft-light／hard-light／color-dodge／color-burn／color／luminosity／hue／saturation／darken／lighten／difference／exclusion系と旧名・fast名を実装。alternative／parallelの括弧・角括弧とカンマ・ピリオド区切り、scalingの小数倍率に対応。`overlaymultiply`／`blend-multiply-fast`はベースの不透明度でクリップ。AppKitに同一演算がないvivid-light等の一部は近似 |
| animation option／collision | ✅ | exclusive（全体・対象ID指定）、background、shared-indexを再生へ反映。animation固有のrect／ellipse／circle／polygon／region collisionをbind中・アニメーション実行中のマウス判定に利用。bindとexclusiveの併用はUKADOC同様に未定義 |
| surface属性 | 🟡 | surface nameは`\s[名前]`の解決に利用し、共通／sakura／kero balloon offsetは倍率を含め実配置へ反映。collision-sortは当たり判定優先順、animation-sortは初期合成順へ反映。basepos pointはサーフェス切替・拡縮時の位置維持と位置保存に、icon.rectは発話履歴の正方形サムネイル切り抜きに利用。center／kinoko.center pointとmaxwidthは解析・保持だけで、対応機能へ接続していません |
| cursor定義 | 🟡 | sakura／kero／char scopeのmouseup、mousedown、mouserightdown、mousewheel、mousehoverをcollision名ごとに反映。system cursor 10種と、AppKitで画像として読めるカーソルファイルに対応。system:wait／move／helpはmacOSの近似表示 |
| tooltip定義 | ✅ | sakura／kero／char scopeのcollision別テキストをmacOS標準ツールチップとして表示 |

`surfaces*.txt`は全てファイル名順に読みます。同じIDのelement・collision・animationなどは後の定義で上書きし、`surface.append`は先に存在するsurfaceへ追記します。各ファイルの`descript`ブレスはそのファイルで定義・追記するsurfaceにだけ適用するため、別ファイルのcollision-sort／animation-sortを巻き込みません。

## surfacetable.txt

UKADOC掲載6構文（charset、version、option、group、scope、surface ID行）は全て解析対象。UI用のgroupと名前、未定義surface非表示、disabled group、parts表示をモデルへ保持するため、この一覧では✅としました。

## 更新定義

読み込みでは`updates2.dau`を先に試し、取得できなければ`updates.txt`へフォールバックします。pathと32桁MD5を検証し、変更ファイルだけを一時領域へ取得してから置換します。

size／date／charset拡張フィールドとVersion 3の`charset,`・未知行を解析し、sizeとMD5はダウンロード結果の検証にも使います。生成するVersion 2はsize／date、先頭行のcharset、CRLFを出力します。

`delete.txt`はcharset行・コメントを除いたWindows区切りの相対パスを読み、更新後にファイルまたはディレクトリを削除します。絶対パス・空要素・`.`・`..`は拒否し、更新済みファイルの置換と削除処理を同じロールバック境界で扱います。

更新定義生成は`noupdate`とupdate ignore／include、NAR生成は`nonar`とnar ignore／includeを反映します。否定、`*`／`**`／`?`、ルート・フォルダ指定、`include:`に対応するが、文字クラスやエスケープ等のgitignore全細則は今後の課題。

## 優先度

1. pattern methodの近似描画を実画像で比較し、互換差が大きい演算を優先して補正します。
2. Balloon `descript.txt`のblendmethodと入力画像上のボタン描画を実装します。
