import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { root, pages } from './content.mjs';
import { origin, base, siteURL } from '../src/site.mjs';
import { locales, localeCodes, localePath } from '../src/i18n.mjs';

const output = path.join(root, 'website/dist');
const walk = directory => readdirSync(directory).flatMap(name => {
  const file = path.join(directory, name);
  return statSync(file).isDirectory() ? walk(file) : [file];
});
const htmlFiles = walk(path.join(output, base)).filter(file => file.endsWith('.html'));
const ids = html => new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]));
let checked = 0;
for (const file of htmlFiles) {
  const html = readFileSync(file, 'utf8');
  const relative = path.relative(output, file).split(path.sep).join('/');
  const pageURL = `${origin}/${relative.replace(/index\.html$/, '')}`;
  for (const [, raw] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
    if (/^(?:mailto:|data:|javascript:|tel:)/.test(raw)) continue;
    const url = new URL(raw.replaceAll('&amp;', '&'), pageURL);
    if (url.origin !== origin) continue;
    // The download-center root is deployed separately from this product site.
    if (base && !url.pathname.startsWith(`/${base}/`)) continue;
    // Starlight's default 404 metadata uses /404/ while the host serves 404.html.
    if (path.basename(file) === '404.html' && url.href === siteURL('404/')) continue;
    let target = path.join(output, decodeURIComponent(url.pathname));
    if (existsSync(target) && statSync(target).isDirectory()) target = path.join(target, 'index.html');
    assert.ok(existsSync(target), `${relative}: missing local target ${raw}`);
    if (url.hash && target.endsWith('.html')) {
      assert.ok(ids(readFileSync(target, 'utf8')).has(decodeURIComponent(url.hash.slice(1))), `${relative}: missing anchor ${raw}`);
    }
    checked++;
  }
}
for (const page of pages) {
  const target = path.join(output, base, 'docs', page.slug, 'index.html');
  assert.ok(existsSync(target), `Missing documentation page ${page.slug}`);
  const html = readFileSync(target, 'utf8');
  assert.ok(html.includes(siteURL(`docs/${page.slug}/`)), `Missing canonical URL: ${page.slug}`);
  assert.ok(html.includes('data-doc-skin-select'), `Missing style switcher: ${page.slug}`);
  assert.ok(!html.includes('src/content/docs/'), `Generated source path leaked into ${page.slug}`);
}
assert.ok(existsSync(path.join(output, base, 'pagefind/pagefind.js')), 'Search index was not generated');
const help = readFileSync(path.join(root, 'apps/Utatane/Resources/UtataneHelp.html'), 'utf8');
const helpIDs = [...help.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(helpIDs).size, helpIDs.length, 'Duplicate bundled-help anchor');
for (const [, anchor] of help.matchAll(/href="#([^"]+)"/g)) assert.ok(helpIDs.includes(decodeURIComponent(anchor)), `Missing offline anchor #${anchor}`);
assert.equal([...help.matchAll(/class="chapter"/g)].length, pages.filter(page => page.help).length);
assert.ok(!/<(?:script|link|img)[^>]+(?:src|href)="https?:\/\//.test(help), 'Offline help loads remote resources');
assert.ok(!/fetch\(|import\(/.test(help), 'Offline help requires module or network loading');
const sitemap = readFileSync(path.join(output, 'sitemap.xml'), 'utf8');
for (const page of pages) assert.ok(sitemap.includes(siteURL(`docs/${page.slug}/`)), `Page missing from sitemap: ${page.slug}`);
const escapeText = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
for (const code of localeCodes) {
  const { meta, home: copy, guide: guideCopy } = locales[code];
  for (const guide of [false, true]) {
    const route = guide ? 'getting-started/' : '';
    const filename = path.join(output, base, meta.directory, route, 'index.html');
    const html = readFileSync(filename, 'utf8');
    const canonical = origin + localePath(code, route);
    assert.ok(html.includes(`<html lang="${meta.htmlLang}">`), `${code}: wrong HTML language`);
    assert.ok(html.includes(`rel="canonical" href="${canonical}"`), `${code}: wrong canonical URL`);
    for (const alternate of localeCodes) assert.ok(html.includes(`hreflang="${locales[alternate].meta.htmlLang}" href="${origin + localePath(alternate, route)}"`), `${code}: missing language alternate ${alternate}`);
    assert.ok(html.includes('hreflang="x-default"'), `${code}: missing x-default`);
    assert.ok(html.includes(`property="og:image" content="${siteURL('assets/utatane-icon.png')}"`), `${code}: wrong OGP asset`);
    const json = JSON.parse(html.match(/<script type="application\/ld\+json">(.*?)<\/script>/s)[1]);
    assert.equal(json['@type'], guide ? 'WebPage' : 'SoftwareApplication');
    assert.equal(json.inLanguage, meta.htmlLang);
    assert.equal(json.url, canonical);
    assert.equal(json.description, guide ? guideCopy.description : meta.description);
    assert.ok(html.includes('aria-current="page"'), `${code}: missing current language`);
    assert.ok(!html.includes('data-ja='), `${code}: legacy translation attributes remain`);
    if (guide) {
      for (const [, heading] of guideCopy.sections) assert.ok(html.includes(escapeText(heading)), `${code}: missing guide section ${heading}`);
      for (const id of ['tab-beginner', 'tab-veteran', 'panel-beginner', 'panel-veteran']) assert.ok(ids(html).has(id), `${code}: missing guide tab ${id}`);
    } else {
      // Translations are rendered into HTML even when JavaScript is unavailable.
      for (const [key, text] of Object.entries(copy)) {
        if (['experience', 'guide', 'docs', 'download'].includes(key) || key.includes('ria-the-bundled-ghost')) continue;
        assert.ok(html.includes(escapeText(text)), `${code}: missing server-rendered translation ${key}`);
      }
      assert.equal(json.image, siteURL('assets/utatane-icon.png'));
      assert.equal(json.offers.priceCurrency, 'JPY');
      assert.ok(html.includes('id="motion-toggle"'), `${code}: missing motion control`);
      assert.ok(html.includes('fetchpriority="high"'), `${code}: missing screenshot priority`);
    }
    assert.ok(sitemap.includes(`<loc>${canonical}</loc>`), `${code}: page missing from sitemap`);
  }
}
const simple = readFileSync(path.join(output, base, 'simple.html'), 'utf8');
assert.ok(simple.includes('name="robots" content="noindex,follow"'), 'Simple page must keep noindex');
assert.ok(simple.includes(`rel="canonical" href="${siteURL('')}"`), 'Simple page canonical must point to the overview');
const screenshots = path.join(root, 'website/public/assets/screenshots');
for (const file of walk(screenshots).filter(file => /\.(png|jpe?g|webp)$/i.test(file))) {
  const relative = path.relative(path.join(root, 'website/public'), file);
  const bytes = readFileSync(file);
  assert.deepEqual(readFileSync(path.join(output, base, relative)), bytes, `Screenshot changed during build: ${relative}`);
  assert.ok(help.includes(bytes.toString('base64')), `Screenshot missing from offline help: ${relative}`);
}
console.log(`PASS: ${htmlFiles.length} built pages, ${checked} local targets, search index and ${pages.filter(page => page.help).length} offline chapters.`);
