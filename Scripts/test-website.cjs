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
  const buttons = ['ja','en','zh-Hans','zh-Hant','ko'].map(language=>element({language}));
  const translated = [...html.matchAll(/<[^>]+data-ja="[^"]*"[^>]*>/g)].map(([tag]) => {
    const el = element();
    for (const [,key,value] of tag.matchAll(/(data-[\w-]+)="([^"]*)"/g)) el.attrs[key]=value;
    el.dataset.ja=el.attrs['data-ja'];
    return el;
  });
  const languages = element();
  assert.equal(translated.length, 79, 'All translated content should be exercised');
  let saved = options.saved;
  const document = {documentElement:{lang:'ja'},getElementById:id=>ids[id],querySelector:()=>languages,querySelectorAll:q=>q==='[data-language]'?buttons:q==='[data-ja][data-en]'?translated:[]};
  let abort;
  const context = {document, navigator:{language:options.language || 'ja',languages:options.languages}, URL, Intl, Date, AbortController, localStorage:{getItem(){if(options.storageError)throw Error();return saved;},setItem(k,v){if(options.storageError)throw Error();saved=v;}}, setTimeout(fn){abort=fn;return 1;},clearTimeout(){},fetch:async(url,{signal})=>{
    assert.match(url,/api.github.com/);
    if(options.timeout) { abort(); assert.equal(signal.aborted,true); throw Error('aborted'); }
    if(options.reject) throw Error('network');
    return {ok:!options.httpError,json:async()=>data};
  }};
  vm.runInNewContext(script,context);
  await new Promise(resolve=>setImmediate(resolve));
  return {ids,buttons,translated,document,languages,getSaved:()=>saved};
}
(async()=>{
  let r=await run([release('old','2026-08-01'),release('new','2026-08-27'),release('draft','2026-08-28',{draft:true})]);
  assert.equal(r.ids['release-link'].textContent,'new');
  assert.match(r.ids['download-link'].href,/download\/new\/Utatane-macOS.zip$/);
  assert.match(r.ids['release-status'].textContent,/10 MB/);
  r.buttons[1].click();
  assert.equal(r.document.documentElement.lang,'en');
  assert.equal(r.translated[0].textContent,'Experience');
  assert.equal(r.ids['download-label'].textContent,'Download for macOS');
  assert.equal(r.ids['release-kind'].textContent,' / Pre-release');
  assert.equal(r.getSaved(),'en');
  assert.equal(r.languages.hidden,false);
  console.log('PASS: newest non-draft prerelease, exact asset, size, language switching and persistence');
  for (const [label,data,options] of [
    ['HTTP failure',[],{httpError:true}],['network failure',[],{reject:true}],['timeout',[],{timeout:true}],['empty list',[],{}],['invalid response',{},{}],['unsafe URL',[release('bad','2026-08-01',{html_url:'https://evil.example/tag/x'})],{}]
  ]) {
    r=await run(data,options); assert.equal(r.ids['download-link'].href,base); assert.match(r.ids['release-status'].textContent,/取得できません/); console.log('PASS: '+label+' fallback');
  }
  r=await run([release('noasset','2026-08-01',{assets:[{name:'other.zip',browser_download_url:base+'/download/x/other.zip'}]})]);
  assert.equal(r.ids['download-link'].href,base+'/tag/noasset');
  assert.equal(r.ids['download-label'].textContent,'配布ページを開く');
  console.log('PASS: missing macOS asset links to release, never arbitrary ZIP');
  r=await run([release('x','bad date',{assets:[{name:'Utatane-macOS.zip',browser_download_url:'javascript:alert(1)'}],prerelease:false})],{saved:'en',storageError:true,language:'en-US'});
  assert.equal(r.document.documentElement.lang,'en'); assert.equal(r.ids['download-link'].href,base+'/tag/x'); assert.equal(r.ids['release-kind'].textContent,' / Regular release'); r.buttons[0].click();
  console.log('PASS: unsafe asset, invalid date, regular release label, unavailable storage');
  r=await run([],{saved:'en'}); assert.equal(r.document.documentElement.lang,'en');
  console.log('PASS: saved language overrides browser language');
  const idsInHTML=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]); assert.equal(new Set(idsInHTML).size,idsInHTML.length);
  for(const [,id] of html.matchAll(/href="#([^"]+)"/g)) assert.ok(idsInHTML.includes(id),id);
  assert.ok(!html.includes('fetchLatestVersion() {\n    const versionEl'));
  console.log('PASS: unique IDs and all section links resolve');
  for (const code of ['ja','en','zh-Hans','zh-Hant','ko']) {
    r=await run([release('v1','2026-08-27')],{saved:code});
    assert.equal(r.document.documentElement.lang,code);
    for(const el of r.translated) {
      assert.ok(el.attrs['data-'+code.toLowerCase()]);
      assert.equal(el.textContent,el.attrs['data-'+code.toLowerCase()]);
    }
    assert.ok(r.ids['release-status'].textContent);
    assert.ok(r.ids['download-label'].textContent);
    assert.ok(r.ids['motion-toggle'].textContent);
    r.ids['motion-toggle'].click();
    assert.equal(r.ids['motion-toggle'].attrs['aria-pressed'],'true');
    assert.ok(r.ids.title.classList.contains('is-paused'));
    r.ids['motion-toggle'].click();
    assert.equal(r.ids['motion-toggle'].attrs['aria-pressed'],'false');
  }
  console.log('PASS: all five locales, complete translations, release and motion labels, pause/resume');
  for(const [language,expected] of [['zh-TW','zh-Hant'],['zh-HK','zh-Hant'],['zh-MO','zh-Hant'],['zh-CN','zh-Hans'],['zh-SG','zh-Hans'],['zh-Hans-TW','zh-Hans'],['zh-Hant-CN','zh-Hant'],['ko-KR','ko'],['fr','ja']]) {
    r=await run([],{language}); assert.equal(r.document.documentElement.lang,expected);
  }
  r=await run([],{languages:['fr','ko-KR','en']}); assert.equal(r.document.documentElement.lang,'ko');
  console.log('PASS: regional Chinese variants, explicit script priority, browser preference order');
  assert.match(css,/@media\(prefers-reduced-motion:reduce\)[^\n]+animation:none/);
  assert.match(html,/aria-label="Utatane \/ 転寝"/);
  assert.ok(!html.includes('noindex'));
  assert.ok(!html.includes('Design preview'));
  assert.ok(!html.includes('ローカル試作'));
  const legacy=fs.readFileSync(path.join(__dirname,'../website/utatane.html'),'utf8');
  const deploy=fs.readFileSync(path.join(__dirname,'../.github/workflows/deploy-website.yml'),'utf8');
  assert.ok(legacy.includes('./utatane-modern.html'));
  assert.ok(legacy.includes('安定性を保証する区分ではありません'));
  assert.ok(!legacy.includes('最新のpre-release'));
  for (const name of ['utatane.html','utatane-modern.html','utatane-modern.css','utatane-modern.js']) {
    assert.ok(deploy.includes('"website/'+name+'"'));
    assert.ok(deploy.includes('put -O "$WEBSITE_DEPLOY_PATH" website/'+name));
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
