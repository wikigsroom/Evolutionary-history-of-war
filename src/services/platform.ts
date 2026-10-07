import {Capacitor} from '@capacitor/core';
import {App} from '@capacitor/app';
import {Haptics,ImpactStyle} from '@capacitor/haptics';
import {Filesystem,Directory,Encoding} from '@capacitor/filesystem';
import {Share} from '@capacitor/share';
export const native=Capacitor.isNativePlatform();
export async function watchLifecycle(pause:()=>void,back:()=>void) {
  if(!native)return;
  await App.addListener('appStateChange',state=>{if(!state.isActive)pause();});
  if(Capacitor.getPlatform()==='android')await App.addListener('backButton',()=>back());
}
let lastHaptic=0;
export function haptic() {
  if(!native || performance.now()-lastHaptic<100)return;lastHaptic=performance.now();void Haptics.impact({style:ImpactStyle.Light}).catch(()=>undefined);
}
export async function exportFile(data:unknown,name:string) {
  const payload=JSON.stringify(data,null,2);
  if(native){const file=await Filesystem.writeFile({path:name,data:payload,directory:Directory.Cache,encoding:Encoding.UTF8});await Share.share({title:'一线万年 · 档案',url:file.uri,dialogTitle:'保存或分享游戏档案'});return;}
  const blob=new Blob([payload],{type:'application/json'}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),2000);
}
