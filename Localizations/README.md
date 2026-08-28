# Localizations

Japanese strings in the Swift source are the source language and string-catalog keys.
Translations are maintained as one compact JSON object per language in this directory.

To add a language, copy `en.json` to a file named with its language code, translate every
value, then generate the Xcode string catalog:

```sh
mise run localization-generate
```

Do not edit `apps/Utatane/Resources/Localizable.xcstrings` directly. `mise run check`
verifies that it matches these files and that every language has the same keys and format
placeholders as the Japanese source strings.

The check also detects Japanese literal UI keys missing from the JSON files in the app
and macOS platform sources. Interpolated strings and dynamically built labels still need
manual review. RealtimeVoice.html receives translated public UI strings from the native
controller before its script runs; it uses the app language, not the browser language.
Run `node --test Scripts/test-realtime-voice.cjs` to check the page in all five languages.
