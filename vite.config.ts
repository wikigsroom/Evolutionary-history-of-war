import { defineConfig, type Plugin } from 'vite';
import { mkdir, writeFile } from 'node:fs/promises';
import { Buffer } from 'node:buffer';
import path from 'node:path';

function motionReviewCapture(): Plugin {
  return { name: 'epoch-motion-review-capture', apply: 'serve', configureServer(server) {
    server.middlewares.use('/__epoch_qa/record', async (request, response) => {
      if (request.method !== 'POST') { response.statusCode = 405; response.end('POST required'); return; }
      try {
        const header = request.headers['x-epoch-qa-context'];
        if (typeof header !== 'string') throw new Error('Recording context missing');
        const metadata = JSON.parse(decodeURIComponent(header));
        if (metadata.kind !== 'epoch_animation_review' || !['A1','A2','A3','A4','A5'].includes(metadata.era) ||
          !['units','heroes','specials'].includes(metadata.group) || ![1,.25].includes(metadata.speed) || ![0,1].includes(metadata.side)) throw new Error('Invalid review context');
        const chunks: Buffer[] = []; let bytes = 0;
        await new Promise<void>((resolve, reject) => {
          request.on('data', (chunk: Buffer) => { bytes += chunk.length; if (bytes > 32*1024*1024) { request.destroy(); reject(new Error('Recording exceeds 32 MB')); } else chunks.push(chunk); });
          request.on('end', resolve); request.on('error', reject);
        });
        if (bytes < 512) throw new Error('Recording is empty');
        const stem = `${metadata.era}-${metadata.group}-${String(metadata.mode).replace(/[^a-z]/g,'')}-side${metadata.side}-${metadata.speed}x-${Date.now()}`;
        const directory = path.join(server.config.root, 'output/qa/v0.3/motion-clips');
        await mkdir(directory, { recursive: true });
        await writeFile(path.join(directory, stem+'.webm'), Buffer.concat(chunks));
        await writeFile(path.join(directory, stem+'.json'), JSON.stringify({ ...metadata, bytes }, null, 2)+'\n');
        response.setHeader('Content-Type','application/json'); response.end(JSON.stringify({ video: `output/qa/v0.3/motion-clips/${stem}.webm` }));
      } catch (error) { response.statusCode = 400; response.end(error instanceof Error ? error.message : String(error)); }
    });
  } };
}

export default defineConfig({
  base: './',
  plugins: [motionReviewCapture()],
  server: { strictPort: true, port: 5173, watch: { ignored: ['**/output/**','**/android/**','**/ios/**'] } },
  build: { target: 'es2022', chunkSizeWarningLimit: 1600 },
});
