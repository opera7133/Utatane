// Run: node Scripts/test-website.cjs
// Dependency-free script/markup checks; not a replacement for browser or live API tests.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync(path.join(__dirname, '../website/utatane-modern.html'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, '../website/utatane-modern.css'), 'utf8');
const script = fs.readFileSync(path.join(__dirname, '../website/utatane-modern.js'), 'utf8');
const base = 'https://github.com/opera7133/Utatane/releases';
const release = (tag, date, extra = {}) => ({tag_name:tag, published_at:date, html_url:base+'/tag/'+tag, prerelease:true, assets:[{name:'Utatane-macOS.zip', browser_download_url:base+'/download/'+tag+'/Utatane-macOS.zip', size:10485760}], ...extra});
function element(dataset={}) { return {dataset, textContent:'', attrs:{}, hidden:true, classList:{values:new Set(),add(v){this.values.add(v);},toggle(v,on){on?this.values.add(v):this.values.delete(v);},contains(v){return this.values.has(v);}}, getAttribute(k){return this.attrs[k.toLowerCase()];}, setAttribute(k,v){this.attrs[k]=v;}, removeAttribute(k){delete this.attrs[k];}, addEventListener(k,v){this[k]=v;}}; }
async function run(data, options={}) {
  const ids = Object.fromEntries(['release-status','release-link','download-link','download-label','release-kind','motion-toggle','title'].map(id=>[id,element()]));
  const document = {documentElement:{lang:options.pageLanguage || 'ja'},getElementById:id=>ids[id]};
  let abort;
  const context = {document, URL, Intl, Date, AbortController, setTimeout(fn){abort=fn;return 1;},clearTimeout(){},fetch:async(url,{signal})=>{
    assert.match(url,/api.github.com/);
    if(options.timeout) { abort(); assert.equal(signal.aborted,true); throw Error('aborted'); }
    if(options.reject) throw Error('network');
    return {ok:!options.httpError,json:async()=>data};
  }};
  vm.runInNewContext(script,context);
  await new Promise(resolve=>setImmediate(resolve));
  return {ids,document};
}
(async()=>{
  let r=await run([release('old','2026-08-01'),release('new','2026-08-27'),release('draft','2026-08-28',{draft:true})]);
  assert.equal(r.ids['release-link'].textContent,'new');
  assert.match(r.ids['download-link'].href,/download\/new\/Utatane-macOS.zip$/);
  assert.match(r.ids['release-status'].textContent,/10 MB/);
  assert.equal(r.ids['download-label'].textContent,'macOS版をダウンロード');
  assert.equal(r.ids['release-kind'].textContent,' / 開発版');
  console.log('PASS: newest non-draft prerelease, exact asset and size');
  for (const [label,data,options] of [
    ['HTTP failure',[],{httpError:true}],['network failure',[],{reject:true}],['timeout',[],{timeout:true}],['empty list',[],{}],['invalid response',{},{}],['unsafe URL',[release('bad','2026-08-01',{html_url:'https://evil.example/tag/x'})],{}]
  ]) {
    r=await run(data,options); assert.equal(r.ids['download-link'].href,base); assert.match(r.ids['release-status'].textContent,/取得できません/); console.log('PASS: '+label+' fallback');
  }
  r=await run([release('noasset','2026-08-01',{assets:[{name:'other.zip',browser_download_url:base+'/download/x/other.zip'}]})]);
  assert.equal(r.ids['download-link'].href,base+'/tag/noasset');
  assert.equal(r.ids['download-label'].textContent,'配布ページを開く');
  console.log('PASS: missing macOS asset links to release, never arbitrary ZIP');
  r=await run([release('x','bad date',{assets:[{name:'Utatane-macOS.zip',browser_download_url:'javascript:alert(1)'}],prerelease:false})],{pageLanguage:'en'});
  assert.equal(r.ids['download-link'].href,base+'/tag/x'); assert.equal(r.ids['release-kind'].textContent,' / Regular release');
  console.log('PASS: unsafe asset, invalid date and static-page locale');
  const idsInHTML=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]); assert.equal(new Set(idsInHTML).size,idsInHTML.length);
  for(const [,id] of html.matchAll(/href="#([^"]+)"/g)) assert.ok(idsInHTML.includes(id),id);
  assert.ok(!html.includes('fetchLatestVersion() {\n    const versionEl'));
  console.log('PASS: unique IDs and all section links resolve');
  for (const code of ['ja','en','zh-Hans','zh-Hant','ko']) {
    r=await run([release('v1','2026-08-27')],{pageLanguage:code});
    assert.ok(r.ids['release-status'].textContent);
    assert.ok(r.ids['download-label'].textContent);
    assert.ok(r.ids['motion-toggle'].textContent);
    r.ids['motion-toggle'].click();
    assert.equal(r.ids['motion-toggle'].attrs['aria-pressed'],'true');
    assert.ok(r.ids.title.classList.contains('is-paused'));
    r.ids['motion-toggle'].click();
    assert.equal(r.ids['motion-toggle'].attrs['aria-pressed'],'false');
  }
  console.log('PASS: all five static-page locales, release and motion labels, pause/resume');
  assert.match(css,/@media\(prefers-reduced-motion:reduce\)[^\n]+animation:none/);
  assert.match(html,/aria-label="Utatane \/ 転寝"/);
  assert.ok(!html.includes('noindex'));
  assert.ok(!html.includes('Design preview'));
  assert.ok(!html.includes('ローカル試作'));
  const localeFiles = {
    en:['en','A little company for your desktop.'],
    'zh-hans':['zh-Hans','为熟悉的桌面，添一位聊天伙伴。'],
    'zh-hant':['zh-Hant','為熟悉的桌面，添一位聊天夥伴。'],
    ko:['ko','익숙한 데스크톱에, 말동무를.'],
  };
  for (const [directory,[lang,lead]] of Object.entries(localeFiles)) {
    const localized=fs.readFileSync(path.join(__dirname,'../website',directory,'utatane-modern.html'),'utf8');
    assert.ok(localized.includes(`<html lang="${lang}">`));
    assert.ok(localized.includes(lead));
    assert.ok(localized.includes(`https://dl.wmsci.com/${directory}/utatane-modern.html`));
    assert.ok(localized.includes('hreflang="ja"'));
    assert.ok(localized.includes('hreflang="x-default"'));
    assert.ok(localized.includes('href="../utatane-modern.css"'));
    assert.ok(localized.includes('src="../utatane-modern.js"'));
  }
  for (const lang of ['ja','en','zh-Hans','zh-Hant','ko','x-default']) assert.ok(html.includes(`hreflang="${lang}"`));
  const sitemap=fs.readFileSync(path.join(__dirname,'../website/sitemap.xml'),'utf8');
  for (const directory of Object.keys(localeFiles)) assert.ok(sitemap.includes(`/${directory}/utatane-modern.html`));
  assert.ok(html.includes('"@type":"SoftwareApplication"'));
  const legacy=fs.readFileSync(path.join(__dirname,'../website/utatane.html'),'utf8');
  const deploy=fs.readFileSync(path.join(__dirname,'../.github/workflows/deploy-website.yml'),'utf8');
  assert.ok(legacy.includes('./utatane-modern.html'));
  assert.ok(legacy.includes('安定性を保証する区分ではありません'));
  assert.ok(!legacy.includes('最新のpre-release'));
  for (const name of ['utatane.html','utatane-modern.html','utatane-modern.css','utatane-modern.js','robots.txt','sitemap.xml']) {
    assert.ok(deploy.includes('"website/'+name+'"'));
    assert.ok(deploy.includes('put -O "$WEBSITE_DEPLOY_PATH" website/'+name));
  }
  for (const directory of Object.keys(localeFiles)) {
    assert.ok(deploy.includes(`"website/${directory}/utatane-modern.html"`));
    assert.ok(deploy.includes(`put -O "$WEBSITE_DEPLOY_PATH/${directory}" website/${directory}/utatane-modern.html`));
  }
  assert.ok(html.includes('href="./utatane-modern.css"'));
  assert.ok(html.includes('src="./utatane-modern.js"'));
  for (const name of ['utatane-icon.webp','utatane-screenshot.webp']) {
    assert.ok(html.includes('srcset="./assets/'+name+'"'));
    assert.ok(deploy.includes('"website/assets/'+name+'"'));
    assert.ok(deploy.includes('put -O "$WEBSITE_DEPLOY_PATH/assets" website/assets/'+name));
  }
  assert.match(html,/utatane-screenshot\.png" width="700" height="447"[^>]+fetchpriority="high"/);
  assert.ok(html.includes('そもそも伺かって何？'));
  assert.ok(html.includes('Utataneだけで動く'));
  for (const label of [' / Stable',' / 安定版',' / 稳定版',' / 穩定版',' / 안정 버전']) assert.ok(!html.includes(label));
  assert.ok(html.includes('通常リリースを小刻みに公開します'));
  console.log('PASS: reduced-motion rule, release label, public metadata, links and deploy entries');

})();
