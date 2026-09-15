import { mkdirSync, writeFileSync, readFileSync, renameSync, rmSync } from 'node:fs';
import path from 'node:path';
import { root, pages, htmlEscape } from './content.mjs';
import { origin, base, siteURL } from '../src/site.mjs';
import { localeCodes, languageLabels, localePath } from '../src/i18n.mjs';

const target = path.join(root, 'website/dist');
mkdirSync(target, { recursive: true });
// Astro's directory output treats a .html route as a directory. Preserve the existing public filename.
const simple = path.join(target, base, 'simple.html');
const scratch = path.join(target, base, 'simple.generated.html');
renameSync(path.join(simple, 'index.html'), scratch);
rmSync(simple, { recursive: true });
renameSync(scratch, simple);
const urls = ['', 'en/', 'zh-hans/', 'zh-hant/', 'ko/'].flatMap(locale => [siteURL(locale), siteURL(`${locale}getting-started/`)]);
urls.push(siteURL('docs/'), ...pages.map(page => siteURL(`docs/${page.slug}/`)));
writeFileSync(path.join(target, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map(url => `  <url><loc>${htmlEscape(url)}</loc></url>`).join('\n')}\n</urlset>\n`);
writeFileSync(path.join(target, 'robots.txt'), `User-agent: *\nAllow: /\nSitemap: ${origin}/sitemap.xml\n`);
const llms = readFileSync(path.join(root, 'website/src/data/llms-introduction.md'), 'utf8');
const localizedLinks = route => localeCodes.map(code => `- ${languageLabels[code]}: ${origin}${localePath(code, route)}`).join('\n');
writeFileSync(path.join(target, 'llms.txt'), `${llms}\n## Official pages\n\n${localizedLinks('')}\n\n## Guides\n\n${localizedLinks('getting-started/')}\n\n## Documentation\n\n- [ドキュメント](${siteURL('docs/')}): 使い方・制作・対応範囲\n\nUse the localized pages above as the canonical source for descriptions. The project documentation records tested compatibility; support for an engine does not guarantee every ghost, branch, Windows DLL, or external module.\n`);
console.log('Prepared deployment directory website/dist (including root metadata).');
