# UKADOC テキストファイル互換状況

UKADOCに掲載されているゴースト関連の設定・配布用テキストファイルと、Utataneの読み込み・利用状況をまとめる。

調査日: 2026-08-24  
調査対象: ローカルの `/Users/wamo/ws/ukadoc/manual` とUtatane本番Swiftコード

## 判定

| 記号 | 意味 |
| --- | --- |
| ✅ | UKADOCにある構文・項目を一通り読み込み、対応する機能で利用する |
| 🟡 | ファイルは読み込むが、未使用の項目・構文・挙動が残る |
| ❌ | ファイルまたは対応する本体機能が未実装 |

単にカンマ区切りを辞書へ格納できるだけでは対応扱いにしない。値がモデルや実行時の挙動へ反映されることを基準にした。

## 全体

| ファイル | 状況 | 現在の実装 | 主な不足 |
| --- | --- | --- | --- |
| Ghost `descript.txt` | 🟡 | UTF-8／Shift_JIS、基本情報、SHIORI名、キャラクター名、既定surface・balloon、更新URL、README、推奨balloon | 74項目中、配置、SSTP制御、SHIORI詳細設定、カーソル、メニュー、アイコン等が未反映 |
| Shell `descript.txt` | 🟡 | UTF-8／Shift_JIS、名前、`seriko.use_self_alpha`、bindgroup／bindoption | 102項目中、初期配置、balloon offset、メニュー装飾、z-order、sticky-window等が未反映 |
| Balloon `descript.txt` | 🟡 | UTF-8／Shift_JIS、名前・type、文字領域、折返し、基本フォント、装飾・shadow、arrow座標、cursor／anchorのstyle・色 | 162項目中、visited、marker配置、入力欄、透過方式、ウインドウ位置等が未反映 |
| Plugin `descript.txt` | 🟡 | UTF-8／Shift_JIS／ASCII、name、id、filename、type、charset、作者、更新URL、README、secondchangeinterval、otherghosttalkを読み込み、SHIORI／dylib／Windows DLLへ分類。メニューから実行、README表示、ネットワーク更新が可能。ネイティブSHIORI型は実体をロードし、OnSecondChange・OnMenuExec・raiseplugin／notifypluginを配送。AKARIの`_create_thread`は独立評価ワーカーで実行し、変更されたグローバル変数を完了時に反映。YAYA製wallet_of_unyuとAKARI製sudohaikuyuは実ファイルでOnMenuExecを確認。macOS dylibは標準`loadu/load`・`unload`・`request`を優先 | dylib実物とWine DLL、AKARIワーカー内の外部通信を伴う長時間処理は未確認 |
| Headline `descript.txt` | 🟡 | UTF-8／Shift_JIS／ASCII、名前、DLL名、URL、open URL、homeurl、charset、alwaysdisplay、readme、readme.charset。RSS用`type`・`feed`拡張も利用 | UKADOC掲載項目は保持・利用。Windows DLL実行は実行環境依存 |
| `install.txt` | 🟡 | UTF-8／Shift_JIS、name、type、directory、accept、複数インストールpackage、bootghost、Ghost／Shell同梱の複数balloon・headline・plugin・calendar.skin・calendar.plugin、安全な新規インストールに加え、refreshとrefreshundeletemaskをバックアップ付き置換で実装 | supplement・languageは未対応 |
| `delete.txt` | 🟡 | UTF-8／Shift_JIS、charset行、Windows区切りの相対ファイル・ディレクトリを更新後に安全確認して削除 | 更新本体と削除を合わせた完全なロールバックは未対応 |
| `developer_options.txt` | 🟡 | `noupdate`／`nonar`に加え、`.narignore`／`.updateignore`／`.narinclude`／`.updateinclude`の主要gitignore構文と`include:`を各生成処理へ反映 | 文字クラス・エスケープ等、gitignoreの全細則は未対応 |
| `surfaces.txt`／`surfaces*.txt` | 🟡 | 複数ファイル結合、surface selector、append、alias、element、rect／polygon collision、主要animation | 後述のSERIKO構文・描画メソッド・surface属性が多数未対応 |
| `surfaces2.txt` | 🟡 | `surfaces`で始まるため読み込む | SSP用上書きではなく、他のsurfacesファイルとファイル名順で単純結合する |
| `alias.txt` | 🟡 | surfaces文書として追加読込し、sakura／kero／char scope aliasを利用 | alias以外の互換挙動は未照合 |
| `surfacetable.txt` | ✅ | charset、version、option、group、scope、surface IDと名前を解析。`DisableNoDefineSurfaces`、`__disabled`、`__parts`も利用 | 実機UIでの全表示差は未確認 |
| `updates2.dau` | 🟡 | path・MD5・size・date・charsetを解析し、取得・サイズ／MD5検証・ロールバック更新。生成はCRLFで拡張フィールドも出力 | date・charsetは保持のみ。削除を含めた完全なトランザクションは未対応 |
| `updates.txt` | 🟡 | `charset,`と`file,`行、path・MD5・拡張フィールド、未知行の無視に対応 | Version 3形式の生成は未対応 |
| `readme.txt`／`readme.md` | 🟡 | Ghost／選択中Shell／Balloon／Headlineのdescript.txtにあるreadme指定と既定候補を安全に解決し、macOSの関連アプリで開く。readme.charsetも保持 | Markdownの独自表示はせず、文字コードの最終的な解釈は関連アプリに依存 |

現状は ✅ 1 / 🟡 13 / ❌ 1。

## Ghost descript.txt

UKADOC掲載は74項目。汎用パーサーはコメントと空行を除いた`key,value`を保持するが、実際に利用するのは次の項目群。

| 状況 | 項目 |
| --- | --- |
| 利用 | `name`、`shiori`、`balloon`、`sakura.name`、`kero.name`、`char*.name` |
| 利用 | `sakura.seriko.defaultsurface`、`kero.seriko.defaultsurface`、`char*.seriko.defaultsurface` |
| 利用 | `balloon.defaultsurface`、scope別`balloon.defaultsurface` |
| 別経路で利用 | `homeurl`、`readme`、`readme.charset` |
| 未反映 | charset宣言、作者・ID・title、配置・alignment、SSTP設定、SHIORI version/cache/encoding、イベント抑制、カーソル、メニュー、アイコン、推奨balloon関連 |

文字コードはファイル内`charset`ではなく、UTF-8を試してからShift_JISへフォールバックする。

## Shell descript.txt

UKADOC掲載は102項目。現在利用するのはかなり限定的。

| 状況 | 項目 |
| --- | --- |
| 利用 | `name`、`seriko.use_self_alpha` |
| 利用 | scope別`bindgroup*.name/default/addid` |
| 利用 | scope別`bindoption*.group`の`mustselect`・`multiple` |
| 別経路で利用 | `readme`、`readme.charset` |
| 未反映 | 基本メタデータ、menu表示、名前上書き、z-order、sticky-window、DPI、初期配置、balloon offset/alignment/dontmove/syncscale、menuitem、全メニュー装飾、透過・crossfade、アイコン枠色 |

SakuraScriptからのz-orderやsticky-window操作は実装済みだが、Shell `descript.txt`の初期値は読んでいない。

## Balloon descript.txt

UKADOC掲載は162項目。現在の実利用項目は以下。

| 状況 | 項目 |
| --- | --- |
| 利用 | `type`、`name`、`origin.x/y`、`validrect.left/top/right/bottom`、`wordwrappoint.x/y`、`vertical` |
| 利用 | `font.name`、`font.height`、`font.color.r/g/b`、`font.shadowcolor.r/g/b`、`font.shadowstyle` |
| 利用 | `font.bold`、`font.italic`、`font.underline`、`font.strike`、`font.outline`、`arrow0.x/y`、`arrow1.x/y` |
| 利用 | cursor、cursor.notselect、anchor、anchor.notselectの`style`、font／pen／brush RGB |
| 画像として利用 | balloon画像、marker画像、arrow画像。ただしfilename指定ではなく既定ファイル名を探索 |
| 別経路で利用 | `readme`、`readme.charset` |
| 未反映 | disable.font、blendmethod、visited anchor、各marker座標・間隔・文字、number書式、communicatebox、透過方式、windowposition、filename差替え、recommended ghost |

`origin`が0または未定義なら横書きは`validrect.left/top`、縦書きは`validrect.right/top`へフォールバックする。縦書きでは`wordwrappoint.y`（未定義時は`validrect.bottom`）で下端を決め、文字を上から下、列を右から左へ配置する。入力欄は従来どおり横書き。

## Headline descript.txt

UKADOC掲載9項目のうち、`charset`、`name`、`dllname`、`url`、`openurl`、`alwaysdisplay`をカタログで利用する。`homeurl`は共通のネットワーク更新URL探索で利用し、`readme`と`readme.charset`は設定画面のREADME表示導線で利用する。

RSS型についてはUKADOCのHEADLINE DLL項目に加え、`type,rss`と`feed,URL`をUtatane拡張として扱う。

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

アーカイブについてはWindows式バックスラッシュを区切りとして安全に正規化してから、パストラバーサル、絶対パス、正規化後の衝突、シンボリックリンク、特殊ファイル、過大な件数・容量を拒否し、途中失敗時は作成済み項目を戻す。これはUKADOC互換とは別の安全策。

## surfaces.txt・alias.txt

UKADOCの定義項目・キーワードは137。現在の対応範囲は次の通り。

| 分類 | 状況 | 対応内容 |
| --- | --- | --- |
| surface選択 | 🟡 | 単一ID、範囲、列挙、除外、`surface.append` |
| alias | 🟡 | sakura、kero、char scopeの名前→surface ID候補 |
| element | 🟡 | PNG／APNG拡張子／PNA、base・overlay系。`seriko.use_self_alpha,1`でもアルファチャンネルのないPNGは左上色透過へフォールバック。APNGは現在PNG画像として先頭フレームを表示し、APNG自身の時間アニメーションは未対応。全描画オプションは未網羅 |
| collision | 🟡 | 矩形、collisionex rect／ellipse／circle／polygonを実際のマウス判定に利用 |
| animation基本 | 🟡 | name、interval文字列、pattern、wait、座標 |
| interval | 🟡 | runonce、sometimes、rarely、random、periodic、always、talk（文字数指定を含む）、starttalk、endtalk、yen-e、bindを実行。neverは自動実行しない定義として機能。複数animationの完全な並行実行は未対応 |
| pattern method | 🟡 | base、overlay、overlay-fast、replace、interpolate、reduce、bind、add、auto、move、stopに加え、multiply／screen／overlay／add／soft-light／hard-light／color-dodge／color-burn／color／luminosity／hue／saturation／darken／lighten／difference／exclusion系と旧名・fast名を実装。`overlaymultiply`／`blend-multiply-fast`はベースの不透明度でクリップ。AppKitに同一演算がないvivid-light等の一部は近似。asis、scaling、import、insert、start／parallel系は未実装 |
| animation option／collision | 🟡 | exclusive、background、shared-indexを保持。animation固有のrect／ellipse／circle／polygon collisionをbind中・アニメーション実行中のマウス判定に利用。optionの描画順・インデックス継続・限定exclusiveの完全な挙動は未実装 |
| surface属性 | 🟡 | surface name、共通／sakura／kero balloon offset、center／kinoko.center／basepos point、icon.rect、maxwidthを保持。balloon offsetは倍率を含め実配置へ反映。collision-sortは当たり判定優先順、animation-sortは初期合成順へ反映。maxwidthの表示制約とpoint・offsetの全用途は未対応 |
| cursor定義 | 🟡 | sakura／kero／char scopeのmouseup、mousedown、mouserightdown、mousewheel、mousehoverをcollision名ごとに反映。system cursor 10種と、AppKitで画像として読めるカーソルファイルに対応。system:wait／move／helpはmacOSの近似表示 |
| tooltip定義 | ✅ | sakura／kero／char scopeのcollision別テキストをmacOS標準ツールチップとして表示 |

`surfaces*.txt`は全てファイル名順に連結する。`surfaces2.txt`の「SSPだけへ上書き」という優先規則は専用実装していない。

## surfacetable.txt

UKADOC掲載6構文（charset、version、option、group、scope、surface ID行）は全て解析対象。UI用のgroupと名前、未定義surface非表示、disabled group、parts表示をモデルへ保持するため、この一覧では✅とした。

## 更新定義

読み込みでは`updates2.dau`を先に試し、取得できなければ`updates.txt`へフォールバックする。pathと32桁MD5を検証し、変更ファイルだけを一時領域へ取得してから置換する。

size／date／charset拡張フィールドとVersion 3の`charset,`・未知行を解析し、sizeとMD5はダウンロード結果の検証にも使う。生成するVersion 2はsize／date、先頭行のcharset、CRLFを出力する。

`delete.txt`はcharset行・コメントを除いたWindows区切りの相対パスを読み、更新後にファイルまたはディレクトリを削除する。絶対パス・空要素・`.`・`..`は拒否する。更新済みファイルの置換と削除処理をまとめた完全なロールバックは今後の課題。

更新定義生成は`noupdate`とupdate ignore／include、NAR生成は`nonar`とnar ignore／includeを反映する。否定、`*`／`**`／`?`、ルート・フォルダ指定、`include:`に対応するが、文字クラスやエスケープ等のgitignore全細則は今後の課題。

## 優先度

1. Ghost／Shell descript.txtの配置・balloon offset・alignmentを既存ウインドウ機能へ接続する。
2. `install.txt`のrefresh、複数同梱オブジェクトを実装する。
3. Balloon descript.txtのフォント装飾・marker・visitedを既存描画へ接続する。
4. surfaces.txtのanimation option、surface属性、未対応pattern methodを段階的に追加する。
5. developer_options.txtを更新定義生成と将来のNAR生成で共通利用する。
