const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
const fs=require('fs'),path=require('path');let browser;
const out=path.resolve(__dirname,'evidence/web-update');
async function click(page,name){const state=await page.evaluate(()=>window.__ctJourney);const r=state.controls[name];await page.mouse.click(r[0]+r[2]/2,r[1]+r[3]/2)}
(async()=>{
 browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--use-angle=metal','--enable-gpu','--disable-background-timer-throttling','--disable-renderer-backgrounding']});
 const context=await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});const pages=[],errors=[];
 for(let endpoint=0;endpoint<2;endpoint++){
  const page=await context.newPage();pages.push(page);page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.text().includes('SCRIPT ERROR')||m.text().includes('ERROR:')){errors.push(m.text());console.error(endpoint,m.text())}});
  await page.goto((process.env.JOURNEY_URL||'http://127.0.0.1:8765/')+'?verify=1&server='+encodeURIComponent(process.env.JOURNEY_SERVER||'ws://127.0.0.1:24842'),{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>window.__ctJourney,{timeout:180000});
  await click(page,'online');await page.waitForFunction(()=>window.__ctJourney?.mode==='online');
  // Wait for the container's next layout before using its button rectangle.
  await page.waitForTimeout(700);await click(page,'connect');
 }
 await Promise.all(pages.map(p=>p.waitForFunction(()=>window.__ctJourney?.network,{timeout:60000})));
 await pages[0].screenshot({path:path.join(out,'web-online-lobby.png')});
 await click(pages[0],'primary');await Promise.all(pages.map(p=>p.waitForFunction(()=>window.__ctJourney?.state==='running',{timeout:30000})));
 await pages[0].keyboard.down('w');await pages[1].keyboard.down('w');
 await Promise.all(pages.map(p=>p.waitForFunction(()=>window.__ctJourney?.a[1]>30&&window.__ctJourney?.b[1]>30,{timeout:30000})));
 await pages[0].keyboard.up('w');await pages[1].keyboard.up('w');
 await click(pages[0],'pause');await Promise.all(pages.map(p=>p.waitForFunction(()=>window.__ctJourney?.state==='paused',{timeout:30000})));
 await Promise.all(pages.map(p=>p.waitForFunction(()=>window.__ctJourney?.network_frame>180,{timeout:30000})));
 const snapshots=await Promise.all(pages.map(p=>p.evaluate(()=>window.__ctJourney)));
 if(snapshots.some(s=>s.desynced)||new Set(snapshots.map(s=>s.role)).size!==2)throw Error('Network role/hash validation failed');
 if(errors.length)throw Error(errors.join('\n'));
 fs.writeFileSync(path.join(out,'browser-online.json'),JSON.stringify({snapshots,errors},null,2));console.log('WASM TWO-CLIENT NETWORK PASS',JSON.stringify(snapshots));
 await browser.close();
})().catch(async e=>{console.error(e);if(browser)await browser.close();process.exitCode=1});
