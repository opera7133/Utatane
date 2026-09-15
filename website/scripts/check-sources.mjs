import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { locales, localeCodes, localePath } from '../src/i18n.mjs';
import { root, docsRoot, pages, repositoryURL } from './content.mjs';

const walk = directory => readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
  const filename = path.join(directory, entry.name);
  return entry.isDirectory() ? walk(filename) : [filename];
});
const components = walk(path.join(root, 'website/src/components/marketing')).filter(file => file.endsWith('.astro'));
const keys = Object.keys(locales.ja.home).sort();
const routes = new Set();
for (const code of localeCodes) {
  const { meta, home, guide } = locales[code];
  assert.deepEqual(Object.keys(home).sort(), keys, `${code}: translation keys differ`);
  for (const [key, text] of Object.entries(home)) assert.ok(typeof text === 'string' && text.length, `${code}: empty translation ${key}`);
  for (const key of ['title', 'description', 'htmlLang', 'ogLocale']) assert.ok(meta[key], `${code}: missing metadata ${key}`);
  assert.ok(!routes.has(localePath(code)), `Duplicate locale route: ${code}`);
  routes.add(localePath(code));
  assert.ok(guide.sections.length > 3, `${code}: missing guide audience`);
  for (const [number, title, body] of guide.sections) assert.ok(number && title && body, `${code}: incomplete guide section`);
}
for (const filename of components) {
  for (const [, key] of readFileSync(filename, 'utf8').matchAll(/\bt\('([^']+)'\)/g)) {
    for (const code of localeCodes) assert.ok(locales[code].home[key], `Missing ${code}/${key} used by ${filename}`);
  }
}
const registered = new Set(pages.map(page => path.join(docsRoot, page.file)));
const documents = walk(docsRoot).filter(filename => filename.endsWith('.md'));
for (const filename of documents) {
  if (!['README.md', 'Index.md'].includes(path.relative(docsRoot, filename))) assert.ok(registered.has(filename), `Unindexed document: ${filename}`);
  // Skip example code when validating article links.
  const text = readFileSync(filename, 'utf8').replace(/```[\s\S]*?```|~~~[\s\S]*?~~~/g, '');
  for (const [, href] of text.matchAll(/!?\[[^\]\n]*\]\(([^\s)]+)\)/g)) {
    if (/^(?:[a-z][a-z\d+.-]*:|\/\/|#)/i.test(href)) continue;
    const destination = path.resolve(path.dirname(filename), decodeURIComponent(href.split('#')[0]));
    assert.ok(existsSync(destination), `${path.relative(root, filename)}: missing source link ${href}`);
  }
}
// Check published GitHub documentation references in the site and issue templates too.
for (const filename of [...walk(path.join(root, 'website/src/data')), ...components, ...walk(path.join(root, '.github/ISSUE_TEMPLATE'))]) {
  const text = readFileSync(filename, 'utf8');
  const prefix = `${repositoryURL}/blob/main/`;
  for (const match of text.matchAll(/https:\/\/github\.com\/opera7133\/Utatane\/blob\/main\/(Docs\/[^"\\\s<#)]+)/g)) {
    assert.ok(existsSync(path.join(root, match[1])), `${filename}: missing repository document ${prefix}${match[1]}`);
  }
}
console.log(`PASS: ${localeCodes.length} locale dictionaries, ${keys.length} translation keys, ${documents.length} source documents and issue links.`);
