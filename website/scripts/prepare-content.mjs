import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { root, pages, webMarkdown, repositoryURL } from './content.mjs';
import { siteURL } from '../src/site.mjs';

const generated = path.join(root, 'website/src/content/docs');
// Changing base paths must not leave the previous deployment tree behind.
if (process.argv.includes('--clean-build')) rmSync(path.join(root, 'website/dist'), { recursive: true, force: true });
// This directory is a generated input, never the Docs source of truth.
rmSync(generated, { recursive: true, force: true });
for (const page of pages) {
  const target = path.join(generated, 'docs', `${page.slug}.md`);
  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, `---\ntitle: ${JSON.stringify(page.title)}\neditUrl: ${JSON.stringify(`${repositoryURL}/edit/main/Docs/${page.file}`)}\n---\n\n${webMarkdown(page)}`);
}
const index = path.join(generated, 'docs/index.md');
writeFileSync(index, `---
title: Utatane ドキュメント
description: Macでゴーストを楽しむための使い方、制作ガイド、対応範囲。
editUrl: ${repositoryURL}/edit/main/Docs/Index.md
---

${webMarkdown({ file: 'Index.md' })}

[公式紹介サイト](${siteURL('')})
`);

// public/ is maintained source, including user-provided screenshots. Never recreate it.
console.log(`Prepared ${pages.length} documentation pages from Docs.`);
