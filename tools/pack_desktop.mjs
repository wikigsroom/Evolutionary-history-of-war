import {spawn} from 'node:child_process';
import {mkdirSync,cpSync,writeFileSync,readFileSync,copyFileSync,readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {assertAnimationRelease} from './release_gate.mjs';

const root=process.cwd(),source=JSON.parse(readFileSync(path.join(root,'package.json'),'utf8'));
const candidate=process.argv.includes('--candidate');console.log(JSON.stringify(assertAnimationRelease(root,candidate)));
const fingerprint=createHash('sha256').update(root+source.version).update(readFileSync(path.join(root,'dist/index.html'))).digest('hex').slice(0,10);
const stage=path.join(tmpdir(),'epoch-rush-desktop-'+fingerprint);
const app=path.join(stage,'app');mkdirSync(app,{recursive:true});
cpSync(path.join(root,'dist'),path.join(app,'dist'),{recursive:true});
cpSync(path.join(root,'desktop'),path.join(app,'desktop'),{recursive:true});
writeFileSync(path.join(app,'package.json'),JSON.stringify({name:source.name,version:source.version,main:source.main,description:source.description,author:source.author},null,2));
writeFileSync(path.join(stage,'package.json'),JSON.stringify({name:source.name+'-builder',version:source.version,private:true}));
// Reuse the already verified runtime directory; avoid the Windows streaming-unzip rename failure.
const config={...source.build,electronVersion:source.devDependencies.electron,electronDist:path.join(root,'node_modules/electron/dist'),directories:{app,output:path.join(stage,'releases')},win:{...source.build.win,icon:path.join(root,'public/app-icon.ico')}};
if(candidate)config.portable={...config.portable,artifactName:`Epoch-Rush-${source.version}-Candidate-Windows-x64.exe`};
const configFile=path.join(stage,'builder.json');writeFileSync(configFile,JSON.stringify(config,null,2));
writeFileSync(path.join(stage,'build-source.json'),JSON.stringify({source:root,createdAt:new Date().toISOString()},null,2));
console.log('Windows package staging: '+stage);
const child=spawn(process.execPath,[path.join(root,'node_modules/electron-builder/out/cli/cli.js'),'--projectDir',stage,'--config',configFile,'--win','portable','--x64'],{cwd:stage,stdio:'inherit',windowsHide:true});
child.on('exit',code=>{
  if(code!==0){process.exitCode=code || 1;return;}
  const out=path.join(root,candidate ? `output/releases/candidates/v${source.version}/windows` : 'output/releases/windows');mkdirSync(out,{recursive:true});
  for(const name of readdirSync(config.directories.output))if(name.startsWith('Epoch-Rush-'+source.version+'-') && (name.endsWith('.exe') || name.endsWith('.blockmap')))copyFileSync(path.join(config.directories.output,name),path.join(out,name));
});
