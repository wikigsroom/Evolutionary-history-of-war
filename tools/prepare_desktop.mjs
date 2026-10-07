import {mkdirSync,cpSync,writeFileSync,readFileSync} from 'node:fs';
import path from 'node:path';
const root=process.cwd(),stage=path.join(root,'output/desktop-app'),source=JSON.parse(readFileSync('package.json','utf8'));
mkdirSync(stage,{recursive:true});
cpSync(path.join(root,'dist'),path.join(stage,'dist'),{recursive:true});
cpSync(path.join(root,'desktop'),path.join(stage,'desktop'),{recursive:true});
writeFileSync(path.join(stage,'package.json'),JSON.stringify({name:source.name,version:source.version,main:'desktop/main.cjs',description:source.description,author:source.author},null,2));
