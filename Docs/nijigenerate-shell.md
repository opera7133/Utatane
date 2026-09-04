# nijigenerateシェル拡張

Utataneでは、通常の伺かシェルと一緒にnijigenerateのパペットを任意で使用できます。
ほかのベースウェアでもシェルを使用できるよう、通常の`surface*.png`は残したまま、
次のファイルをシェルのディレクトリへ配置します。

- `puppet.inp`: nijigenerateから書き出したパペット
- `nijigenerate.json`: 表示範囲、サーフェス対応、マウス反応の設定

一通りの設定を含む
[`nijigenerate.sample.json`](nijigenerate.sample.json)を雛形として利用できます。
パペットと同じ場所へコピーし、`nijigenerate.json`へ改名してください。

スコープ0では、`puppet.inp`とnicxliveランタイムの両方が見つかった場合に
nijigenerateレンダラーを使用します。どちらかがなければ通常のシェル表示へ
フォールバックします。

パペットに`Body::Roll`と`Body::Breath`が存在する場合、待機中の揺れと呼吸を
Utataneが自動で動かします。設定ファイル、サーフェス対応、マウス反応で明示した
値は自動値より優先されます。

## 設定

```json
{
  "viewport": {
    "width": 420,
    "height": 720,
    "contentScale": 0.96,
    "contentOffsetX": 0,
    "contentOffsetY": 0,
    "interactionOffsetX": 0,
    "interactionOffsetY": 0,
    "interactionScaleX": 1,
    "interactionScaleY": 1
  },
  "pointer": {
    "xParameter": "Interaction::LookX",
    "yParameter": "Interaction::LookY",
    "centerX": 171,
    "centerY": 155,
    "rangeX": 150,
    "rangeY": 145,
    "response": 0.35,
    "restoreMilliseconds": 180
  },
  "parameters": {
    "Expression::Smile": 0
  },
  "surfaces": {
    "105": {
      "Expression::Smile": 1
    }
  },
  "reactions": [
    {
      "event": "doubleClick",
      "region": "Head",
      "button": 0,
      "transitionMilliseconds": 140,
      "durationMilliseconds": 2500,
      "restoreMilliseconds": 280,
      "parameters": {
        "Expression::Smile": 1
      }
    }
  ]
}
```

`viewport.width`と`viewport.height`は、拡大・縮小前のウィンドウサイズを
ポイント単位で指定します。`viewport.contentScale`は、変形時に制作用キャンバスの
外へ出るパーツのための余白です。`contentOffsetX`はパペットを右へ、
`contentOffsetY`は下へ移動します。既定値は順に420、720、0.96、0、0です。

`interactionOffsetX`と`interactionOffsetY`では、通常シェルの当たり判定を
パペットへ個別に位置合わせできます。省略した場合は対応する`contentOffset`を
引き継ぎます。`interactionScaleX`と`interactionScaleY`は、通常シェルの
キャンバス左上を基準として当たり判定を拡大・縮小してからオフセットを適用します。
どちらの既定値も1です。

`pointer`は、通常シェルの元座標におけるカーソル位置をnijigenerateの2つの
パラメータへ対応させます。`centerX`と`centerY`の位置が値0になり、そこから
`rangeX`と`rangeY`だけ離れると-1または1になります。Yの正方向は上です。
`response`はマウス移動ごとの追従の滑らかさ、`restoreMilliseconds`はカーソルが
外れたあと正面へ戻る時間です。

`drag`は、指定した`region`内から始まる左ドラッグを、2次元の`parameter`へ
渡します。そのドラッグ中はウィンドウを移動しません。`rangeX`と`rangeY`は、
パラメータ値が1になるまでの移動距離と向きを通常シェルの元座標で指定します。
左または上へ引いたときに値を増やす場合は負数にします。マウスを離すと
`restoreMilliseconds`で指定した時間をかけて(0, 0)へ戻ります。

`parameters`には通常状態の値を指定します。`surfaces`の数値キーは、
SakuraScriptのサーフェスIDをパラメータ値へ対応させます。

`reactions`で使用できる`event`は、`down`、`up`、`click`、`doubleClick`、
`multipleClick:N`、`enter`、`leave`、`hover`、`move`、`dragStart`、`dragEnd`です。
`move`は、同じ当たり判定上をカーソルで撫でている間に発生します。`region`は
通常シェルの当たり判定名と大文字・小文字を区別せずに照合します。省略した場合は
すべての領域に一致します。`button`はAppKitのマウスボタン番号で、省略も可能です。

## パペットの作成

Utataneが操作できるのは、書き出したパペットに存在するパラメータだけです。
待機用の2つを除き、パラメータ名は設定ファイルで変更できます。最小構成として、
次のパラメータがあると便利です。

- `Body::Roll`: 範囲-1〜1。待機中の左右の揺れ
- `Body::Breath`: 範囲0〜1。待機中の呼吸
- `Interaction::Pet`: 範囲0〜1。当たり判定を撫でたときの変形
- `Interaction::Cheek`: 2次元で範囲0〜1。頬を引っぱったときの変形
- 表情用パラメータ: 範囲0〜1。サーフェス対応やマウス反応に使用
- 任意で`Interaction::LookX`と`Interaction::LookY`: 範囲-1〜1。視線追従

アニメーションを作ったあとでパーツを別ノードへ分離した場合、必要に応じて
元の親と同じ`Body::Roll`および`Body::Breath`の割り当てを追加してください。
たとえば前髪だけを分離して割り当てを直さないと、待機アニメーション中に頭から
ずれて見えます。

簡単な髪撫で反応では、`Interaction::Pet = 1`に前髪の小さな変形を割り当て、
`move`反応から表情と一緒に有効化します。指定した通常シェルの当たり判定内で
カーソルを動かし続けると反応が維持され、動きを止めると通常状態へ戻ります。

## ローカルでの確認

nicxliveをビルドまたはインストールし、書き出したパペットの隣へ設定ファイルを
配置します。外部パペットはシェルへコピーせず、次のように確認できます。

```sh
UTATANE_NIJIGENERATE_PUPPET=/absolute/path/to/puppet.inp \
UTATANE_NICXLIVE_LIBRARY=/absolute/path/to/libnicxlive.dylib \
/absolute/path/to/Utatane.app/Contents/MacOS/Utatane
```

外部パペットを指定した場合も、当たり判定とフォールバック表示には選択中の
ゴーストの通常シェルを使用します。反応を調整する前に、Utataneの当たり判定表示を
使って`interactionOffsetX`、`interactionOffsetY`、`interactionScaleX`、
`interactionScaleY`を合わせてください。

`pointer`ブロックは任意です。視線や顔をカーソルへ追従させない場合は、設定から
削除できます。髪撫でなど、当たり判定を使った反応はそのまま動作します。
