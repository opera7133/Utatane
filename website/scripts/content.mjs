import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { Marked } from 'marked';
import { siteURL, sitePath, repositoryURL } from '../src/site.mjs';
export { repositoryURL };

export const root = fileURLToPath(new URL('../../', import.meta.url));
export const docsRoot = path.join(root, 'Docs');
export const navigation = JSON.parse(readFileSync(path.join(docsRoot, 'navigation.json'), 'utf8'));
export const pages = navigation.groups.flatMap(group => group.pages.map(page => ({ ...page, group: group.label })));
export const htmlEscape = text => String(text).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

const files = new Map(pages.map(page => [path.resolve(docsRoot, page.file), page]));
const slugs = new Set();
for (const page of pages) {
  if (slugs.has(page.slug)) throw new Error(`Duplicate documentation route: ${page.slug}`);
  slugs.add(page.slug);
  readFileSync(path.join(docsRoot, page.file), 'utf8');
}

export function sourceFor(page) {
  return readFileSync(path.join(docsRoot, page.file), 'utf8').replace(/^# [^\n]+\n+/, '');
}

export function resolveLink(href, page, mode = 'web') {
  if (/^(?:[a-z][a-z\d+.-]*:|\/\/)/i.test(href)) return href;
  if (href.startsWith('#')) return mode === 'help' ? `#${page.slug.replaceAll('/', '-')}-${href.slice(1)}` : href;
  const [filename, fragment] = href.split('#');
  const absolute = path.resolve(docsRoot, path.dirname(page.file), decodeURIComponent(filename));
  const publicRoot = path.join(root, 'website/public');
  const asset = path.relative(publicRoot, absolute).split(path.sep).join('/');
  if (asset && !asset.startsWith('../') && !path.isAbsolute(asset)) {
    if (mode === 'help' && /\.(png|jpe?g|webp|svg)$/i.test(asset)) {
      const extension = path.extname(asset).slice(1).toLowerCase();
      const mime = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp', svg: 'image/svg+xml' }[extension];
      return `data:${mime};base64,${readFileSync(absolute).toString('base64')}`;
    }
    return `${mode === 'help' ? siteURL(asset) : sitePath(asset)}${fragment ? `#${fragment}` : ''}`;
  }
  const target = files.get(absolute);
  if (target) {
    if (mode === 'help' && target.help) return `#${target.slug.replaceAll('/', '-')}${fragment ? `-${fragment}` : ''}`;
    return `${mode === 'help' ? siteURL('docs/') : sitePath('docs/')}${target.slug}/${fragment ? `#${fragment}` : ''}`;
  }
  if (['README.md', 'Index.md'].some(file => absolute === path.join(docsRoot, file))) return mode === 'help' ? siteURL('docs/') : sitePath('docs/');
  // Code, root README and examples remain in the repository, rather than becoming broken website paths.
  const relative = path.relative(root, absolute).split(path.sep).join('/');
  if (relative.startsWith('../')) throw new Error(`Link escapes repository: ${href} in ${page.file}`);
  return `${repositoryURL}/blob/main/${relative}${fragment ? `#${fragment}` : ''}`;
}

export function webMarkdown(page) {
  // Protect fenced and inline code; only rewrite Markdown destinations in prose.
  return sourceFor(page).replace(/(```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]+`)|(!?\[[^\]\n]*\]\()([^\s)]+)(\))/g,
    (whole, code, prefix, href, suffix) => code ? code : `${prefix}${resolveLink(href, page)}${suffix}`);
}

export function renderHelp(page) {
  const prefix = page.slug.replaceAll('/', '-');
  const used = new Map();
  const markdown = new Marked({
    gfm: true,
    renderer: {
      heading({ tokens, depth }) {
        const text = this.parser.parseInline(tokens);
        const slug = text.replace(/<[^>]*>/g, '').toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').trim().replace(/\s/g, '-');
        const count = used.get(slug) || 0;
        used.set(slug, count + 1);
        return `<h${depth + 1} id="${htmlEscape(`${prefix}-${slug}${count ? `-${count}` : ''}`)}">${text}</h${depth + 1}>\n`;
      }
    },
    walkTokens(token) {
      if (token.type === 'link' || token.type === 'image') token.href = resolveLink(token.href, page, 'help');
    }
  });
  return markdown.parse(sourceFor(page));
}
