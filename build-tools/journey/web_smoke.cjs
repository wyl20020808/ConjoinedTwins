// Fresh headless browser profile only; never attaches to the user's browser.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
const fs=require('fs');const path=require('path');
const out=path.resolve(__dirname,'evidence/web-update');
let browser;
(async()=>{
 browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--use-angle=metal','--enable-gpu','--disable-background-timer-throttling','--disable-renderer-backgrounding']});
 const page=await browser.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1});const logs=[];const errors=[];
 page.on('console',msg=>{logs.push(msg.text());if(msg.text().includes('SCRIPT ERROR')||msg.text().includes('ERROR:'))errors.push(msg.text());if(msg.type()==='error')console.error('BROWSER',msg.text())});page.on('pageerror',e=>errors.push(String(e)));
 await page.goto((process.env.JOURNEY_URL||'http://127.0.0.1:8765/')+'?verify=1',{waitUntil:'domcontentloaded'});
 await page.waitForFunction(()=>window.__ctJourney,{timeout:180000});
 let state=await page.evaluate(()=>window.__ctJourney);console.log('READY',JSON.stringify(state));
 await page.screenshot({path:path.join(out,'web-start.png')});
 const rect=state.controls.primary;await page.mouse.click(rect[0]+rect[2]/2,rect[1]+rect[3]/2);
 await page.waitForFunction(()=>window.__ctJourney?.state==='running',{timeout:30000});
 await page.keyboard.down('w');await page.waitForFunction(()=>window.__ctJourney?.a[1]>40&&window.__ctJourney?.b[1]>20,{timeout:30000});await page.keyboard.up('w');
 await page.keyboard.press('Space');await page.waitForTimeout(1200);
 state=await page.evaluate(()=>window.__ctJourney);console.log('MOVED',JSON.stringify(state));
 await page.screenshot({path:path.join(out,'web-solo-running.png')});
 await page.keyboard.press('Escape');await page.waitForFunction(()=>window.__ctJourney?.state==='paused',{timeout:10000});
 const before=await page.evaluate(()=>window.__ctJourney.a[1]);await page.waitForTimeout(750);const after=await page.evaluate(()=>window.__ctJourney.a[1]);
 if(before!==after)throw Error('Paused player moved');if(state.mode!=='solo'||state.b[1]<=0)throw Error('Solo AI did not follow');
 fs.writeFileSync(path.join(out,'browser.json'),JSON.stringify({state,errors,paused_stable:before===after},null,2));fs.writeFileSync(path.join(out,'browser.log'),logs.join('\n'));
 await browser.close();if(errors.length)throw Error(errors.join('\n'));console.log('WASM SOLO SMOKE PASS');
})().catch(async e=>{console.error(e);if(browser)await browser.close();process.exitCode=1});
