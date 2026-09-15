# 音声合成・音声認識

Utataneはゴーストの発話を音声合成で読み上げ、macOSの音声認識結果をゴーストへ通知できます。本体と相方には別の音声エンジン・話者を指定できます。

## 音声合成を設定する

「本体設定」→「音声」で「ゴーストの発話を読み上げる」を有効にし、スコープごとに音声エンジンを選びます。外部エンジンはUtataneに同梱されないため、別途インストールして起動してください。

### macOS標準

追加のアプリは不要です。macOSにインストールされている声から選べます。

### VOICEVOX互換API

[VOICEVOX](https://voicevox.hiroshiba.jp/)と、VOICEVOX Nemo、SHAREVOX、AivisSpeechなど同じAPIを実装するエンジンに対応します。エンジンを起動してAPI URLを入力し、「話者一覧を取得」から話者を選びます。VOICEVOXの既定値は`http://127.0.0.1:50021`です。

### COEIROINK v2

[COEIROINK](https://coeiroink.com/)を起動し、API URL、話者UUID、スタイルIDを設定します。既定値は`http://127.0.0.1:50032`です。「話者一覧を取得」から組み合わせを選ぶこともできます。

### VOICEPEAK

[VOICEPEAK](https://www.ah-soft.com/voice/)の実行ファイルとナレーター名を指定します。標準の実行ファイルは`/Applications/voicepeak.app/Contents/MacOS/voicepeak`です。「話者一覧を取得」には、インストール済みナレーターだけが表示されます。

VOICEPEAKのコマンドラインAPIには入力文字数の制限があるため、長い発話は読み上げに失敗する場合があります。

### VoiSona Talk

[VoiSona TalkのREST API](https://manual.voisona.com/ja/talk/pc/2b6e9bc7efb180ea86ccc6c7347e9ca6)を有効にしてから、次の項目を設定します。

1. API URL。既定値は`http://127.0.0.1:32766/api/talk/v1`
2. APIユーザー名。VoiSona Talkへログインしているメールアドレス
3. VoiSona TalkのAPI設定で作成したAPI用パスワード
4. 「話者一覧を取得」でボイス、バージョン、言語を選択

API用パスワードはログイン用パスワードとは別にできます。認証情報はmacOSのKeychainへスコープごとに保存され、Utataneの設定JSONには書き込みません。また、認証情報の送信先はlocalhostとループバックIPアドレスだけに制限しています。

### OpenAI互換ローカルAPI

OpenAIの`POST /v1/audio/speech`と互換性のある、macOS上のローカル音声合成サーバーに対応します。API URL、モデル名、声を設定してください。必要なサーバーではBearerトークンも設定できます。

[Irodori-TTS](https://github.com/Aratako/Irodori-TTS)はmacOSのCPU/MPS経路を持ち、[Irodori-TTS-Server](https://github.com/Aratako/Irodori-TTS-Server)を使うとこの方式で接続できます。既定値はAPI URLが`http://127.0.0.1:8088/v1`、モデルが`irodori-tts`です。リファレンス音声を登録している場合は、そのIDを「声」へ入力します。

接続先はlocalhostとループバックIPアドレスだけに制限しています。BearerトークンはmacOSのKeychainへスコープごとに保存します。

### OpenAI

[OpenAIの音声生成API](https://developers.openai.com/api/reference/cli/resources/audio/subresources/speech/methods/create)を使って発話を読み上げます。OpenAI APIキー、モデル、声を設定してください。既定のモデルは`gpt-4o-mini-tts`です。対応するモデルでは「話し方の指示」も送信できます。

発話テキストはOpenAIへ送信され、APIの利用量に応じて料金が発生する場合があります。APIキーはmacOSのKeychainへスコープごとに保存され、設定JSONには書き込みません。APIキーの送信先は`https://api.openai.com`だけに制限しています。

## SakuraScriptから読み上げを調整する

`\__v[disable]`以降は読み上げず、`\__v[alternate,テキスト]`を使うと画面表示とは別の読みを指定できます。引数なしの`\__v`で通常の読み上げに戻ります。詳しくは[SakuraScript互換状況](UKADOC-SakuraScript-Compatibility.md)を参照してください。

## 音声認識を設定する

「本体設定」→「音声」で「マイクから音声を認識する」を有効にします。初回はmacOSからマイクと音声認識の許可を求められます。確定した認識結果は`OnVoiceRecognitionWord`でゴーストへ通知されます。

利用できる環境ではオンデバイス認識を選べますが、選択した言語やmacOSの状態によっては利用できません。
