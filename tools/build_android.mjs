import {spawn} from 'node:child_process';
import {existsSync,mkdirSync,writeFileSync,copyFileSync,cpSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {assertAnimationRelease} from './release_gate.mjs';
const root=process.cwd(),sdk=process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT;
const version=JSON.parse(readFileSync(path.join(root,'package.json'),'utf8')).version;
const candidate=process.argv.includes('--candidate');console.log(JSON.stringify(assertAnimationRelease(root,candidate)));
if(!sdk || !existsSync(sdk))throw new Error('Set ANDROID_HOME to the installed Android SDK.');
let buildRoot=root;
if(process.platform==='win32' && /[^\x00-\x7F]/.test(root)){
  buildRoot=path.join(tmpdir(),'epoch-rush-android-'+createHash('sha256').update(root+version).update(readFileSync(path.join(root,'dist/index.html'))).digest('hex').slice(0,10));
  mkdirSync(buildRoot,{recursive:true});
  cpSync(path.join(root,'android'),path.join(buildRoot,'android'),{recursive:true,filter:source=>!['.gradle','build','local.properties'].includes(path.basename(source))});
  for(const module of ['android','app','haptics','filesystem','share'])cpSync(path.join(root,'node_modules/@capacitor',module),path.join(buildRoot,'node_modules/@capacitor',module),{recursive:true,filter:source=>!['build','.gradle'].includes(path.basename(source))});
  writeFileSync(path.join(buildRoot,'build-source.json'),JSON.stringify({source:root,createdAt:new Date().toISOString()},null,2));
  console.log('Android build staging: '+buildRoot);
}
writeFileSync(path.join(buildRoot,'android/local.properties'),'sdk.dir='+sdk.replaceAll('\\','/')+'\n');
const gradle=spawn(process.platform==='win32' ? 'gradlew.bat' : './gradlew',['--no-daemon','assembleDebug','assembleRelease'],{cwd:path.join(buildRoot,'android'),stdio:'inherit',shell:process.platform==='win32',windowsHide:true});
gradle.on('exit',code=>{
  if(code!==0){process.exitCode=code || 1;return;}
  const out=path.join(root,candidate ? `output/releases/candidates/v${version}/android` : 'output/releases/android');mkdirSync(out,{recursive:true});
  for(const [suffix,source] of [['debug','debug/app-debug.apk'],['release-unsigned','release/app-release-unsigned.apk']])copyFileSync(path.join(buildRoot,'android/app/build/outputs/apk',source),path.join(out,`Epoch-Rush-${version}-${candidate ? 'Candidate-' : ''}Android-${suffix}.apk`));
});
