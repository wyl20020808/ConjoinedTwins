// 只启动任务独占 headless Chromium，不连接用户浏览器。
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
const fs=require('fs'),path=require('path');
const mobile=process.env.ENVIRONMENT_MOBILE==='1';
const out=path.resolve(__dirname,'evidence/atmosphere',mobile?'mobile':'desktop');fs.mkdirSync(out,{recursive:true});
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--use-angle=metal','--enable-gpu']});
 try {
  const page=await browser.newPage({viewport:{width:1280,height:720},hasTouch:mobile,isMobile:mobile}),errors=[],shots=[];
  page.on('pageerror',e=>errors.push(String(e)));page.on('crash',()=>errors.push('PAGE CRASH'));
  page.on('console',m=>{if(/SCRIPT ERROR|ERROR:|shader.*error/i.test(m.text()))errors.push(m.text());});
  await page.goto('http://127.0.0.1:8766/atmosphere-review/');
  const deadline=Date.now()+180000;let done=null;
  while(Date.now()<deadline){
   const state=await page.evaluate(()=>({shot:window.__atmosphereShot,done:window.__atmosphereDone}));
   if(state.shot&&state.shot.lap===0&&!shots.includes(state.shot.name)){
    await page.screenshot({path:path.join(out,state.shot.name+'.png')});shots.push(state.shot.name);console.log(JSON.stringify(state.shot));
   }
   if(state.done){done=state.done;break;}if(errors.length)break;
   await page.waitForTimeout(100);
  }
  fs.writeFileSync(path.join(out,'visual-review.json'),JSON.stringify({done,shots,errors},null,2));
  if(!done||done.length!==12||shots.length!==6||errors.length)throw Error(JSON.stringify({done,shots:shots.length,errors}));
  for(let i=0;i<6;i++)if(done[i+6].nodes>done[i].nodes+40||done[i+6].cached_assets>done[i].cached_assets+2)throw Error('Repeated views retain extra scene resources');
  console.log('ATMOSPHERE VISUAL PASS');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
