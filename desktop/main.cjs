const {app,BrowserWindow,protocol,net,Menu}=require('electron');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
protocol.registerSchemesAsPrivileged([{scheme:'epoch',privileges:{standard:true,secure:true,supportFetchAPI:true,stream:true}}]);
const isQa=process.argv.includes('--qa');
if(isQa) app.setPath('userData',path.join(app.getPath('temp'),'epoch-rush-desktop-qa'));
let window;
async function createWindow(){
  const root=path.resolve(__dirname,'../dist');
  protocol.handle('epoch',request=>{
    const url=new URL(request.url),pathname=decodeURIComponent(url.pathname);
    const file=path.resolve(root,'.'+pathname);
    if(url.hostname!=='app' || file!==root && !file.startsWith(root+path.sep))return new Response('Not found',{status:404});
    return net.fetch(pathToFileURL(file===root ? path.join(root,'index.html') : file).toString());
  });
  Menu.setApplicationMenu(null);
  window=new BrowserWindow({width:1440,height:900,minWidth:800,minHeight:520,backgroundColor:'#102333',title:'一线万年：文明冲锋',show:false,icon:path.join(root,'app-icon.png'),webPreferences:{contextIsolation:true,nodeIntegration:false,sandbox:true,webSecurity:true,backgroundThrottling:!isQa}});
  window.webContents.setWindowOpenHandler(()=>({action:'deny'}));
  window.webContents.on('will-navigate',(event,url)=>{if(!url.startsWith('epoch://app/'))event.preventDefault();});
  window.on('blur',()=>window.webContents.send('app-paused'));
  window.once('ready-to-show',()=>{if(!isQa)window.show();});
  window.webContents.on('console-message',details=>{if(details.level==='error')console.error(details.message);});
  await window.loadURL('epoch://app/index.html');
  if(isQa){
    const fs=require('node:fs/promises');
    const screenshot=process.argv.find(argument=>argument.startsWith('--screenshot='))?.slice(13);
    const started=Date.now();
    const inspect=async()=>{
      const snapshot=await window.webContents.executeJavaScript("({title:document.title,text:document.querySelector('#interface').innerText,canvas:!!document.querySelector('canvas'),engineReady:document.querySelector('canvas')?.dataset.engineReady==='true',menuReady:!!document.querySelector('.start-button:not(:disabled)'),images:[...document.images].filter(i=>!i.complete||i.naturalWidth===0).map(i=>i.src),indexedDB:!!window.indexedDB,secureContext:window.isSecureContext})");
      if((!snapshot.engineReady || !snapshot.menuReady || snapshot.images.length) && Date.now()-started<25000){setTimeout(inspect,500);return;}
      console.log(JSON.stringify({desktopQa:snapshot}));
      if(screenshot){await fs.mkdir(path.dirname(screenshot),{recursive:true});await window.webContents.capturePage();await new Promise(resolve=>setTimeout(resolve,250));await fs.writeFile(screenshot,(await window.webContents.capturePage()).toPNG());}
      app.exit(snapshot.engineReady && snapshot.menuReady && snapshot.secureContext && snapshot.indexedDB && !snapshot.images.length ? 0 : 1);
    };
    setTimeout(()=>{void inspect();},500);
  }
}
app.whenReady().then(createWindow);
app.on('window-all-closed',()=>app.quit());
