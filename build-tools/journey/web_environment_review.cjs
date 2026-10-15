// 独立 headless 浏览器展示层巡检，不连接用户浏览器，也不把观察位置跳转当作通关。
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
const fs=require('fs'),path=require('path');
const output=path.resolve(__dirname,'evidence/environment'+(process.env.ENVIRONMENT_MOBILE==='1'?'/mobile':''));fs.mkdirSync(output,{recursive:true});let browser;
(async()=>{
 browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--use-angle=metal','--enable-gpu','--disable-background-timer-throttling','--disable-renderer-backgrounding']});
 const mobile=process.env.ENVIRONMENT_MOBILE==='1';
 const page=await browser.newPage({viewport:{width:1280,height:720},hasTouch:mobile,isMobile:mobile});const errors=[];
 page.on('crash',()=>errors.push('PAGE CRASH'));
 page.on('pageerror',e=>errors.push(String(e)));
 page.on('console',m=>{if(/SCRIPT ERROR|ERROR:|shader.*error/i.test(m.text())){errors.push(m.text());console.error(m.text())}});
 await page.goto('http://127.0.0.1:8766/environment-review/',{waitUntil:'domcontentloaded'});
 let last=-1;const shots=new Set();const deadline=Date.now()+300000;
 while(Date.now()<deadline){
  const state=await page.evaluate(()=>({current:window.__ctReview,done:window.__ctReviewDone}));
  if(state.current&&state.current.index!==last){
   const r=state.current;last=r.index;console.log(JSON.stringify(r));
   if(r.lap===0&&[0,240,360,520,800,1080,1200,1400,1720].includes(r.meters)&&!shots.has(r.meters)){
    await page.screenshot({path:path.join(output,'scene-'+r.meters+'.png')});shots.add(r.meters);
   }
  }
  if(state.done){fs.writeFileSync(path.join(output,'browser-lifetime.json'),JSON.stringify({records:state.done,errors},null,2));if(errors.length)throw Error(errors.join('\n'));console.log('WEB ENVIRONMENT LIFETIME PASS',state.done.length);await browser.close();return;}
  if(errors.length)throw Error(errors.join('\n'));
  await page.waitForTimeout(100);
 }
 throw Error('Timed out');
})().catch(async e=>{console.error(e);if(browser)await browser.close();process.exitCode=1});
