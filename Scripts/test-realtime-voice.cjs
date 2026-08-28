const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'apps/Utatane/Resources/RealtimeVoice.html'), 'utf8');
const swift = fs.readFileSync(path.join(root, 'apps/Utatane/Sources/RealtimeVoiceWindowController.swift'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const injectedKeys = [...swift.matchAll(/"([^"]+)": String\(localized: "[^"]+"\)/g)].map((match) => match[1]);

for (const language of ['ja', 'en', 'zh-Hans', 'zh-Hant', 'ko']) {
  test(`realtime page translates initial and dynamic UI in ${language}`, async () => {
    const catalog = language === 'ja' ? {} : JSON.parse(fs.readFileSync(path.join(root, `Localizations/${language}.json`), 'utf8'));
    const strings = Object.fromEntries(injectedKeys.map((key) => [key, language === 'ja' ? key : catalog[key]]));
    for (const value of Object.values(strings)) assert.equal(typeof value, 'string');
    const element = (key) => ({ textContent: key ?? '', dataset: { i18n: key }, value: '250', addEventListener() {} });
    const staticElements = [...html.matchAll(/data-i18n="([^"]+)"/g)].map((match) => element(match[1]));
    const elements = new Map();
    const messages = [];
    const document = {
      documentElement: {},
      querySelectorAll: () => staticElements,
      querySelector: (selector) => {
        if (!elements.has(selector)) elements.set(selector, element());
        return elements.get(selector);
      },
    };
    const window = {
      utataneRealtimeLocalization: { language, strings },
      webkit: { messageHandlers: { realtime: { postMessage: (value) => messages.push(value) } } },
      addEventListener() {},
    };
    vm.runInNewContext(script, { window, document, cancelAnimationFrame() {}, clearInterval() {} });
    assert.equal(document.documentElement.lang, language);
    for (const entry of staticElements) assert.equal(entry.textContent, strings[entry.dataset.i18n]);
    assert.equal(elements.get('#inputDb').textContent, `−∞ dBFS (${strings['小さい']})`);
    assert.equal(elements.get('#latency').textContent, `${strings['応答遅延']}: — / WebRTC RTT: —`);
    await window.utataneRealtime.receiveAnswer({ sdp: '' });
    assert.equal(messages[0].type, 'error');
    assert.equal(messages[0].message, `Error: ${strings['接続はすでに閉じられている']}`);
    assert.equal(elements.get('#status').textContent, strings['切断済み']);
    // External error details remain intact in both the log and native event path.
    window.utataneRealtime.receiveError({ message: 'provider diagnostic 123' });
    assert.equal(messages.at(-1).message, 'provider diagnostic 123');
    assert.match(elements.get('#events').textContent, /provider diagnostic 123/);
  });
}
