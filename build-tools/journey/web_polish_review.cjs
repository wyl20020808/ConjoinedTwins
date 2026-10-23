// 任务独占 headless 浏览器；不连接或操控用户浏览器。
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'evidence/polish');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--use-angle=metal','--enable-gpu']});
 try {
  const page=await browser.newPage({viewport:{width:1280,height:720}}),errors=[],shots=[];
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('console',m=>{if(/SCRIPT ERROR|ERROR:|shader.*error/i.test(m.text()))errors.push(m.text());});
  await page.goto('http://127.0.0.1:8766/polish-review/');
  const deadline=Date.now()+180000;let done=false;
  while(Date.now()<deadline){
   const state=await page.evaluate(()=>({shot:window.__polishShot,done:window.__polishDone}));
   if(state.shot&&!shots.some(s=>s.name===state.shot.name)){
    await page.screenshot({path:path.join(out,state.shot.name+'.png')});shots.push(state.shot);console.log(JSON.stringify(state.shot));
   }
   if(state.done){done=true;break;}if(errors.length)break;
   await page.waitForTimeout(100);
  }
  fs.writeFileSync(path.join(out,'visual-review.json'),JSON.stringify({done,shots,errors},null,2));
  if(!done||shots.length!==9||errors.length)throw Error(JSON.stringify({done,shots:shots.length,errors}));
  console.log('POLISH VISUAL PASS');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
