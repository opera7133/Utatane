// Generate crawlable static locale pages from website/utatane-modern.html.
// Run: node Scripts/generate-website-locales.cjs [--check]
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.join(__dirname, '..');
const sourcePath = path.join(root, 'website/utatane-modern.html');
const source = fs.readFileSync(sourcePath, 'utf8');
const check = process.argv.includes('--check');
const origin = 'https://dl.wmsci.com';

const locales = {
  ja: {
    directory: '', htmlLang: 'ja', ogLocale: 'ja_JP',
    title: 'Utatane — macOSで伺かを',
    description: 'Utatane — macOSで伺かを楽しむための本体アプリ。',
  },
  en: {
    directory: 'en', htmlLang: 'en', ogLocale: 'en_US',
    title: 'Utatane — Ukagaka for macOS',
    description: 'Utatane is a native macOS baseware for enjoying Ukagaka ghosts, dialogue, shells, balloons, and animations.',
  },
  'zh-Hans': {
    directory: 'zh-hans', htmlLang: 'zh-Hans', ogLocale: 'zh_CN',
    title: 'Utatane — 在 macOS 上使用伺か',
    description: 'Utatane 是面向 macOS 的伺か本体应用，可体验人格对话、外壳、对话框与动画。',
  },
  'zh-Hant': {
    directory: 'zh-hant', htmlLang: 'zh-Hant', ogLocale: 'zh_TW',
    title: 'Utatane — 在 macOS 上使用伺か',
    description: 'Utatane 是面向 macOS 的伺か本體應用程式，可體驗人格對話、外殼、對話框與動畫。',
  },
  ko: {
    directory: 'ko', htmlLang: 'ko', ogLocale: 'ko_KR',
    title: 'Utatane — macOS에서 우카가카를',
    description: 'Utatane는 macOS에서 우카가카 고스트의 대화, 셸, 말풍선, 애니메이션을 즐길 수 있는 베이스웨어예요.',
  },
};

function render(code, locale) {
  const localePath = locale.directory ? `${locale.directory}/` : '';
  const localeURL = `${origin}/utatane/${localePath}`;
  let html = source
    .replace('<html lang="ja">', `<html lang="${locale.htmlLang}">`)
    .replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${locale.description}">`)
    .replace(/<title>[^<]*<\/title>/, `<title>${locale.title}</title>`)
    .replace('<link rel="canonical" href="https://dl.wmsci.com/utatane-modern.html">', `<link rel="canonical" href="${localeURL}">`)
    .replace('<meta property="og:locale" content="ja_JP">', `<meta property="og:locale" content="${locale.ogLocale}">`)
    .replace(/<meta property="og:title" content="[^"]*">/, `<meta property="og:title" content="${locale.title}">`)
    .replace(/<meta property="og:description" content="[^"]*">/, `<meta property="og:description" content="${locale.description}">`)
    .replace('<meta property="og:url" content="https://dl.wmsci.com/utatane-modern.html">', `<meta property="og:url" content="${localeURL}">`)
    .replace('"url":"https://dl.wmsci.com/utatane-modern.html"', `"url":"${localeURL}"`)
    .replace(/<link rel="alternate" hreflang="ja"[^>]*>[\s\S]*?<link rel="alternate" hreflang="x-default"[^>]*>/, alternateLinks());

  let translated = 0;
  const attribute = `data-${code.toLowerCase()}`;
  html = html.replace(/(<([a-z][a-z0-9]*)\b[^>]*\bdata-ja="[^"]*"[^>]*>)([^<]*)(<\/\2>)/gi, (whole, open, tag, text, close) => {
    const match = open.match(new RegExp(`${attribute}="([^"]*)"`, 'i'));
    assert.ok(match, `Missing ${attribute}: ${open}`);
    translated += 1;
    return `${open}${match[1]}${close}`;
  });
  assert.equal(translated, 75, `${code} translated element count`);

  html = html.replace(/<img\b[^>]*\bdata-alt-ja="[^"]*"[^>]*>/gi, whole => {
    const match = whole.match(new RegExp(`data-alt-${code}="([^"]*)"`, 'i'));
    assert.ok(match, `Missing image alt for ${code}`);
    return whole.replace(/\balt="[^"]*"/, `alt="${match[1]}"`);
  });

  html = html
    .replace(/<div class="languages"[\s\S]*?<\/div>/, languageLinks(code))
    .replaceAll('href="./utatane.html"', 'href="./simple.html"');
  if (locale.directory) {
    html = html
      .replaceAll('href="./utatane-modern.css"', 'href="../utatane-modern.css"')
      .replaceAll('src="./utatane-modern.js"', 'src="../utatane-modern.js"')
      .replaceAll('src="./assets/', 'src="../assets/')
      .replaceAll('srcset="./assets/', 'srcset="../assets/')
      .replaceAll('href="./assets/', 'href="../assets/')
      .replaceAll('href="./simple.html"', 'href="../simple.html"');
  }
  return html;
}

function alternateLinks() {
  return [
    ['ja', `${origin}/utatane/`],
    ['en', `${origin}/utatane/en/`],
    ['zh-Hans', `${origin}/utatane/zh-hans/`],
    ['zh-Hant', `${origin}/utatane/zh-hant/`],
    ['ko', `${origin}/utatane/ko/`],
    ['x-default', `${origin}/utatane/`],
  ].map(([lang, href]) => `<link rel="alternate" hreflang="${lang}" href="${href}">`).join('\n');
}

function languageLinks(current) {
  const links = [
    ['ja', 'ja', '/utatane/', '日本語'],
    ['en', 'en', '/utatane/en/', 'EN'],
    ['zh-Hans', 'zh-Hans', '/utatane/zh-hans/', '简体'],
    ['zh-Hant', 'zh-Hant', '/utatane/zh-hant/', '繁體'],
    ['ko', 'ko', '/utatane/ko/', '한국어'],
  ].map(([code, lang, href, label]) => `<a lang="${lang}" hreflang="${lang}" href="${href}"${code === current ? ' aria-current="page"' : ''}>${label}</a>`).join('\n');
  return `<div class="languages" aria-label="Language / 言語">\n${links}\n</div>`;
}

for (const [code, locale] of Object.entries(locales)) {
  const outputPath = path.join(root, 'website/utatane', locale.directory, 'index.html');
  const output = render(code, locale);
  if (check) {
    assert.equal(fs.readFileSync(outputPath, 'utf8'), output, `${path.relative(root, outputPath)} is stale`);
  } else {
    fs.mkdirSync(path.dirname(outputPath), {recursive: true});
    fs.writeFileSync(outputPath, output);
  }
}

const simpleSource = fs.readFileSync(path.join(root, 'website/utatane.html'), 'utf8');
const simpleOutput = simpleSource
  .replace('<link rel="canonical" href="https://dl.wmsci.com/utatane.html" />', '<link rel="canonical" href="https://dl.wmsci.com/utatane/" />\n    <meta name="robots" content="noindex,follow" />')
  .replace('href="./index.html"', 'href="../index.html"')
  .replace('href="./utatane-modern.html"', 'href="./"')
  .replaceAll('src="./assets/', 'src="./assets/')
  .replaceAll('href="./assets/', 'href="./assets/');
const simplePath = path.join(root, 'website/utatane/simple.html');
if (check) {
  assert.equal(fs.readFileSync(simplePath, 'utf8'), simpleOutput, 'website/utatane/simple.html is stale');
} else {
  fs.mkdirSync(path.dirname(simplePath), {recursive: true});
  fs.writeFileSync(simplePath, simpleOutput);
}

console.log(check ? 'PASS: localized website files are current' : 'Generated localized website files');
