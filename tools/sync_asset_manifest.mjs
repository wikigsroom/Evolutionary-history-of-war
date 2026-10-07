import {copyFileSync,mkdirSync} from 'node:fs';
import path from 'node:path';
const root=process.cwd();
mkdirSync(path.join(root,'src/content'),{recursive:true});
copyFileSync(path.join(root,'public/assets/manifest.json'),path.join(root,'src/content/runtime-manifest.json'));
