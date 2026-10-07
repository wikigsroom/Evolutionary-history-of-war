/** Canvas capture for the explicit development gallery, with source hashes in a sidecar. */
export class MotionRecorder {
  private recorder?: MediaRecorder;
  private stream?: MediaStream;
  private chunks: Blob[] = [];
  private context?: Record<string, unknown>;
  private startedAt = 0;
  private timer?: ReturnType<typeof setTimeout>;
  private saving = false;
  constructor(private status: (message: string) => void) {}
  get running() { return this.recorder?.state === 'recording'; }
  get busy() { return this.running || this.saving; }
  progress(context: Record<string, unknown>) { if (this.running) Object.assign(this.context!, context); }
  start(context: Record<string, unknown>) {
    if (this.busy) return;
    const canvas = document.querySelector('canvas');
    if (!canvas || typeof canvas.captureStream !== 'function' || typeof MediaRecorder === 'undefined') {
      this.status('此运行环境不支持画面录制'); return;
    }
    const mimeType = ['video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm'].find(type => MediaRecorder.isTypeSupported(type));
    if (!mimeType) { this.status('此运行环境不支持 WebM 编码'); return; }
    this.context = context; this.startedAt = performance.now(); this.chunks = [];
    this.stream = canvas.captureStream(30);
    this.recorder = new MediaRecorder(this.stream, { mimeType, videoBitsPerSecond: 2500000 });
    this.recorder.ondataavailable = event => { if (event.data.size) this.chunks.push(event.data); };
    this.recorder.onstop = () => { void this.save(); };
    this.recorder.start(500); this.timer = setTimeout(() => this.stop(), 40000);
    this.status(`录制中 · ${context.speed}× · 最长 40 秒`);
  }
  stop() {
    if (!this.running) return;
    if (this.timer) clearTimeout(this.timer);
    this.saving = true;
    this.recorder!.stop();
  }
  private async save() {
    const durationSec = (performance.now() - this.startedAt) / 1000;
    const blob = new Blob(this.chunks, { type: this.recorder!.mimeType });
    this.stream?.getTracks().forEach(track => track.stop());
    const metadata = { ...this.context, kind: 'epoch_animation_review', durationSec, bytes: blob.size, captureFps: 30 };
    this.status('正在保存录像');
    try {
      const response = await fetch('/__epoch_qa/record', { method: 'POST',
        headers: { 'Content-Type': 'video/webm', 'X-Epoch-QA-Context': encodeURIComponent(JSON.stringify(metadata)) }, body: blob });
      if (!response.ok) throw new Error(await response.text());
      const result = await response.json() as { video: string };
      this.status(`录像已保存：${result.video}`);
    } catch (error) { this.status(`录像保存失败：${error instanceof Error ? error.message : String(error)}`); }
    finally { this.saving = false; }
  }
}
