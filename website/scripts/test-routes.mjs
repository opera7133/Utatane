import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { dev, preview } from 'astro';
import { root } from './content.mjs';
import { sitePath } from '../src/site.mjs';

// Test the router itself: checking files in dist cannot detect a dev-only 404.
const cache = mkdtempSync(path.join(tmpdir(), 'utatane-route-check-'));
const options = {
  root: path.join(root, 'website/'),
  cacheDir: cache,
  logLevel: 'silent',
  server: { host: '127.0.0.1', port: 0 },
  vite: { cacheDir: path.join(cache, 'vite') }
};
try {
  for (const [mode, start] of [['dev', dev], ['preview', preview]]) {
    const server = await start(options);
    try {
      const origin = `http://127.0.0.1:${server.address?.port ?? server.port}`;
      const response = await fetch(origin + sitePath('simple.html'), { signal: AbortSignal.timeout(20000) });
      assert.equal(response.status, 200, `${mode}: simple.html returned ${response.status}`);
      assert.match(await response.text(), /<title>Utatane - Download Center<\/title>/, `${mode}: simple.html resolved to the wrong page`);
      const overview = await fetch(origin + sitePath(''), { signal: AbortSignal.timeout(20000) });
      assert.equal(overview.status, 200, `${mode}: overview is unavailable`);
      assert.ok((await overview.text()).includes(`href="${sitePath('simple.html')}"`), `${mode}: overview does not link to simple.html`);
      const screenshot = await fetch(origin + sitePath('assets/screenshots/settings-general.png'), { signal: AbortSignal.timeout(20000) });
      assert.equal(screenshot.status, 200, `${mode}: screenshot is unavailable`);
      assert.match(screenshot.headers.get('content-type'), /image\/png/, `${mode}: screenshot URL resolved to HTML`);
      console.log(`PASS: ${mode} serves simple.html, the overview link and screenshot assets.`);
    } finally {
      await server.stop();
    }
  }
} finally {
  rmSync(cache, { recursive: true, force: true });
}
