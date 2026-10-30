// Uses the existing local playwright-core and installed Chrome; no downloads.
const fs = require('fs');
const path = require('path');
const {pathToFileURL}=require('url');
const base = path.resolve(__dirname,'..');
const workspace = path.resolve(base,'..','..');
const {chromium}=require(path.join(workspace,'tools/agent-runtime/node_modules/playwright-core'));
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--disable-gpu']});
 const results=[];
 for (const file of fs.readdirSync(path.join(base,'target')).filter(f=>f.endsWith('.svg'))) {
  const h=Number(fs.readFileSync(path.join(base,'target',file),'utf8').match(/<svg[^>]* height="(\d+)"/)[1]);
  const page=await browser.newPage({viewport:{width:1920,height:h},deviceScaleFactor:2});
  await page.setContent('<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0;overflow:hidden}svg{display:block}</style></head><body>'+fs.readFileSync(path.join(base,'target',file),'utf8')+'</body></html>');
  await page.evaluate(()=>document.fonts.ready);
  const audit=await page.evaluate(()=>{
   const texts=[...document.querySelectorAll('text')];
   const clipped=texts.filter(t=>{let r=t.getBBox();return r.x<0||r.y<0||r.x+r.width>1920||r.y+r.height>Number(document.querySelector('svg').getAttribute('height'))}).map(t=>t.textContent);
   const panelOverflow=[...document.querySelectorAll('g[data-panel]')].flatMap(g=>{const r=g.querySelector('rect').getBBox();return [...g.querySelectorAll('text')].filter(t=>{const b=t.getBBox();return b.x<r.x||b.x+b.width>r.x+r.width-12||b.y<r.y||b.y+b.height>r.y+r.height}).map(t=>({panel:g.dataset.panel,text:t.textContent}));});
   return {textCount:texts.length,clipped,panelOverflow};
  });
  await page.screenshot({path:path.join(base,'target',file.replace('.svg','.png')),clip:{x:0,y:0,width:1920,height:h},timeout:60000});
  results.push({file,...audit,pixels:[3840,h*2]});await page.close();
 }
 await browser.close();
 fs.writeFileSync(path.join(base,'evidence','layout-check.json'),JSON.stringify(results,null,2));
 console.log(JSON.stringify(results,null,2));
 if(results.some(r=>r.clipped.length||r.panelOverflow.length))process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1});
