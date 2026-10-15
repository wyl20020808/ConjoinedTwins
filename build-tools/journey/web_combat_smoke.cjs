// 独立 headless 浏览器，使用真实 WebAssembly 和触屏事件，不连接用户浏览器。
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'evidence/combat-web');
fs.mkdirSync(out,{recursive:true});
let browser,lastPage;
(async()=>{
 browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--use-angle=metal','--enable-gpu','--disable-background-timer-throttling','--disable-renderer-backgrounding']});
 const context=await browser.newContext({viewport:{width:844,height:390},deviceScaleFactor:1,isMobile:true,hasTouch:true});
 const page=await context.newPage(),errors=[];lastPage=page;
 page.on('pageerror',e=>errors.push(String(e)));
 page.on('console',m=>{if(m.text().includes('SCRIPT ERROR')||m.text().includes('ERROR:')){errors.push(m.text());console.error(m.text())}});
 await page.goto((process.env.JOURNEY_URL||'http://127.0.0.1:8766/')+'?verify=1',{waitUntil:'domcontentloaded'});
 await page.waitForFunction(()=>window.__ctJourney?.build==='journey-combat-loading-20261015',{timeout:180000});
 // 启动页异步创建菜单后，等待布局和首轮资源预热完成再读取按钮坐标。
 await page.waitForFunction(()=>window.__ctJourney?.fps>5);
 await page.waitForTimeout(1000);
 let state=await page.evaluate(()=>window.__ctJourney);
 console.log('MENU',JSON.stringify(state));
 await page.screenshot({path:path.join(out,'mobile-menu.png')});
 const canvas=await page.locator('canvas').boundingBox();
 function point(x,y){const scale=Math.min(canvas.width/state.viewport[0],canvas.height/state.viewport[1]);return {x:canvas.x+(canvas.width-state.viewport[0]*scale)/2+x*scale,y:canvas.y+(canvas.height-state.viewport[1]*scale)/2+y*scale}}
 const training=state.controls.training;
 if(training[0]<0||training[1]<0||training[0]+training[2]>state.viewport[0]||training[1]+training[3]>state.viewport[1])throw Error('Training button outside viewport');
 const start=point(training[0]+training[2]/2,training[1]+training[3]/2);
 await page.touchscreen.tap(start.x,start.y);
 await page.waitForFunction(()=>window.__ctJourney?.state==='running'&&window.__ctJourney?.combat.training,{timeout:30000});
 state=await page.evaluate(()=>window.__ctJourney);
 console.log('TRAINING READY',JSON.stringify(state),JSON.stringify(canvas));
 const cdp=await context.newCDPSession(page),fingers=new Map();
 async function send(type){await cdp.send('Input.dispatchTouchEvent',{type,touchPoints:[...fingers].map(([id,p])=>({id,x:p.x,y:p.y,radiusX:5,radiusY:5,force:1}))})}
 async function press(id,p){fingers.set(id,p);await send('touchStart')}
 async function release(id){fingers.delete(id);await send('touchEnd')}
 const joystick=point(state.viewport[0]*0.18,state.viewport[1]*0.75);
 await press(0,joystick);
 fingers.set(0,point(state.viewport[0]*0.18,state.viewport[1]*0.45));await send('touchMove');
 await page.waitForFunction(()=>window.__ctJourney?.combat.weapon.ammo===24,{timeout:30000});
 state=await page.evaluate(()=>window.__ctJourney);
 function action(name){const c=state.combat.buttons[name];return point(c[0],c[1])}
 await press(1,action('fire'));
 await press(2,action('jump'));
 await page.waitForFunction(()=>window.__ctJourney?.combat.weapon.ammo<24&&window.__ctJourney?.height[0]>0,{timeout:10000});
 await release(2);await release(1);await release(0);
 await page.screenshot({path:path.join(out,'mobile-combat-landscape.png')});
 await press(3,action('reload'));await release(3);
 await page.waitForFunction(()=>window.__ctJourney?.combat.weapon.reload>0,{timeout:10000});
 await page.waitForFunction(()=>window.__ctJourney?.combat.weapon.reload===0&&window.__ctJourney?.combat.weapon.ammo===24,{timeout:10000});
 await press(4,action('drop'));await release(4);
 await page.waitForFunction(()=>Object.keys(window.__ctJourney?.combat.weapon||{}).length===0,{timeout:10000});
 state=await page.evaluate(()=>window.__ctJourney);
 if(!state.combat.touch)throw Error('Touch device not detected');
 if(errors.length)throw Error(errors.join('\n'));
 fs.writeFileSync(path.join(out,'browser.json'),JSON.stringify({passed:true,state,errors},null,2));
 console.log('WASM MOBILE COMBAT PASS',JSON.stringify(state));
 await browser.close();
})().catch(async e=>{console.error(e);if(lastPage){console.error('LAST STATE',JSON.stringify(await lastPage.evaluate(()=>window.__ctJourney)));await lastPage.screenshot({path:path.join(out,'failure.png')})}if(browser)await browser.close();process.exitCode=1});
