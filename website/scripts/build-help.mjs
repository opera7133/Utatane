import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { root, navigation, pages, renderHelp, htmlEscape } from './content.mjs';
import { siteURL } from '../src/site.mjs';

const included = pages.filter(page => page.help);
const css = readFileSync(path.join(root, 'website/src/styles/help.css'), 'utf8');
const skin = readFileSync(path.join(root, 'website/src/scripts/skin.mjs'), 'utf8').replace('export function', 'function');
const version = readFileSync(path.join(root, 'project.yml'), 'utf8').match(/MARKETING_VERSION: "([^"]+)"/)?.[1] || '開発版';
const menu = navigation.groups.map(group => {
  const members = group.pages.filter(page => page.help);
  return members.length ? `<strong>${htmlEscape(group.label)}</strong><ul>${members.map(page => `<li><a href="#${page.slug.replaceAll('/', '-')}">${htmlEscape(page.title)}</a></li>`).join('')}</ul>` : '';
}).join('\n');
const chapters = included.map(page => `<section class="chapter" id="${page.slug.replaceAll('/', '-')}"><h2>${htmlEscape(page.title)}</h2>${renderHelp(page)}</section>`).join('\n');
const html = `<!doctype html>
<!-- Generated from Docs by website/scripts/build-help.mjs. Edit the Markdown sources. -->
<html lang="ja">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Utatane ヘルプ</title><style>${css}</style></head>
<body>
<a class="skip" href="#main">本文へ</a>
<header><a class="brand" href="#main">Utatane ヘルプ</a><div class="toolbar"><span>同梱版 ${htmlEscape(version)}</span><label>スタイル <select data-doc-skin-select aria-label="ヘルプのスタイル"><option value="paper">標準</option><option value="glass">ガラス</option><option value="classic">クラシック98</option></select></label><a href="${siteURL('docs/')}">Web版</a></div></header>
<div class="layout"><nav aria-label="ヘルプの目次">${menu}</nav>
<main id="main"><h1>Macで、ゴーストと。</h1><p class="lead">導入、日常の操作、設定、困ったときの確認。<br>このヘルプはインターネット接続なしで読めます。</p>
<p>まずは<a href="#start">はじめてのUtatane</a>から。制作ガイドと詳しい仕様の対応表は<a href="${siteURL('docs/create/guide/')}">Web版</a>で読めます。外部サイトへのリンクには通信が必要です。</p>
<div class="search-area" hidden><label for="help-query">ヘルプ内を検索</label><input type="search" id="help-query" placeholder="例：文字サイズ、バックアップ、表示されない" autocomplete="off"><p id="help-search-status" class="search-meta" aria-live="polite"></p><ul id="help-results"></ul></div>
${chapters}
</main></div>
<script>
${skin}
installSkinSelector();
const area = document.querySelector('.search-area');
const chapters = [...document.querySelectorAll('.chapter')].map(chapter => ({id:chapter.id, title:chapter.querySelector('h2').textContent, text:chapter.textContent.normalize('NFKC').toLowerCase()}));
const query = document.querySelector('#help-query');
const results = document.querySelector('#help-results');
const status = document.querySelector('#help-search-status');
area.hidden = false;
query.addEventListener('input', () => {
  results.replaceChildren();
  const terms = query.value.normalize('NFKC').trim().toLowerCase().split(/\\s+/).filter(Boolean);
  if (!terms.length) { status.textContent = ''; return; }
  const hits = chapters.filter(chapter => terms.every(term => chapter.text.includes(term)));
  status.textContent = hits.length ? hits.length + '件の章が見つかりました' : '見つかりませんでした。別の言葉で試してください。';
  for (const hit of hits) { const li = document.createElement('li'); const a = document.createElement('a'); a.href = '#' + hit.id; a.textContent = hit.title; li.append(a); results.append(li); }
});
</script>
</body></html>
`;
const target = path.join(root, 'apps/Utatane/Resources/UtataneHelp.html');
if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== html) throw new Error('Bundled help is stale. Run: cd website && bun run help');
  console.log('Bundled help matches Docs.');
} else {
  writeFileSync(target, html);
  console.log(`Generated offline help with ${included.length} chapters.`);
}
