# Realtime音声会話

Utataneは、OpenAI Realtime APIと、そのWebRTC call作成方式に対応する互換APIへ接続できる。特定の社内endpointはアプリやゴーストへ埋め込まず、利用者がBase URL、model、voice、API keyを設定する。

## 設定

「設定」→「ネットワーク」→「リアルタイム音声会話」で次を設定する。

- プロバイダー: `OpenAI Realtime`または`OpenAI Realtime互換`
- モデル: OpenAIでは`gpt-realtime`等、互換APIでは提供されるmodel ID
- Voice: providerが受け付けるvoice ID
- Base URL: OpenAIでは空欄可。互換APIではサービスのURL
- APIキー: macOS Keychainへ保存し、WebViewやゴーストcontentへ渡さない

設定後、ゴーストの右クリックメニューから「機能」→「リアルタイム音声会話…」を開く。明示的に「会話を開始」を押した時だけマイクを取得する。

## 通信

Utataneは`POST /v1/realtime/calls`へ、`sdp`と`session`をmultipartで送信する。`session`には`type: realtime`、model、audio output voiceを含める。Bearer API keyを付けるHTTP signalingはnative `URLSession`で行うため、providerがBrowser向けCORS headerを返す必要はない。

音声と`oai-events` DataChannelはWKWebViewのWebRTC接続を通る。API keyはWebViewへ渡さない。終了時はcall IDを取得できた場合に`POST /v1/realtime/calls/{call_id}/hangup`を送信する。

## ゴーストとの連携

`response.audio_transcript.delta`または`response.output_audio_transcript.delta`を受信すると、届いた差分を累積して現在のゴーストのバルーンへ逐次表示する。対応する`done`で確定文へ置き換える。文字列はSakuraScriptとして解釈されないようescapeする。

`conversation.item.input_audio_transcription.delta`と`completed`はイベントログと応答遅延の計測に使い、バルーンには表示しない。音声会話画面にはマイク入力レベル、WebRTC RTT、ユーザー発話終了から最初のモデルtranscriptまでの応答遅延を表示する。入力レベルは−25 dBFS以上を「入力あり」と判定する（表示上の目安で、送信音声にはゲートを掛けない）。出力音量はWeb Audio Gainで50〜500%に調整できる。

ゴーストの`ghost/master/realtime.json`に表情を設定すると、`response.created`で`thinking`、音声transcriptの開始で`speaking`へ変更し、応答完了時に元のsurfaceへ戻す。未設定または不正なmanifestでは表情を変更しない。

```json
{
  "version": 1,
  "expressions": {
    "thinking": 9,
    "speaking": 0
  }
}
```

API eventからsurface番号を直接受け取らず、このmanifestに明示された対応だけを使用する。`restore`は設定できず、Utataneが応答開始前のsurfaceを記録して戻す。

## 現在の制限

- OpenAI Realtime API全体の完全互換を要求しない。WebRTC call、audio track、`oai-events`、transcript、hangupを利用する。
- `oai-events`の到着順で表示するため、transcriptは会話ログとして低遅延に見えるが、音声再生位置との厳密な字幕同期は保証しない。
- providerごとのTURN、組織policy、rate limit、課金、音声保存条件はprovider側の設定に従う。
- 自動testとDebug buildはHTTP request生成とアプリへの組み込みを確認するが、実マイク、OpenAI、互換providerへのlive接続は別途確認する。
