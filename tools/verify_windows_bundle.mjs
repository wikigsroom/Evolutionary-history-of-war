import {extractFile} from '@electron/asar';
import {readdirSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import path from 'node:path';
const root=process.cwd(),version=JSON.parse(readFileSync(path.join(root,'package.json'),'utf8')).version;
const fingerprint=createHash('sha256').update(root+version).update(readFileSync(path.join(root,'dist/index.html'))).digest('hex').slice(0,10);
const stage=path.join(tmpdir(),'epoch-rush-desktop-'+fingerprint);
const archive=path.join(stage,'releases/win-unpacked/resources/app.asar');
const sha=buffer=>createHash('sha256').update(buffer).digest('hex');
const files=readdirSync(path.join(root,'dist'),{recursive:true,withFileTypes:true}).filter(entry=>entry.isFile());
const mismatches=[];
for(const entry of files){const file=path.join(entry.parentPath,entry.name),relative=path.relative(root,file);if(sha(readFileSync(file))!==sha(extractFile(archive,relative)))mismatches.push(relative.replaceAll('\\','/'));}
const mainMatches=sha(readFileSync(path.join(root,'desktop/main.cjs')))===sha(extractFile(archive,path.join('desktop','main.cjs')));
const report={version,checkedFiles:files.length,mismatches,desktopMainMatches:mainMatches,passed:!mismatches.length && mainMatches};
const qa=path.join(root,'output/qa/v'+version.split('.').slice(0,2).join('.'));mkdirSync(qa,{recursive:true});
writeFileSync(path.join(qa,`windows-bundle-${process.argv.includes('--candidate') ? 'candidate-' : ''}validation.json`),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));if(!report.passed)process.exitCode=1;
