export class MouseTransport {
  constructor(send, onError) {
    this.send = send; this.onError = onError; this.queue = []; this.closed = false; this.busy = false;
    this.session = Array.from(crypto.getRandomValues(new Uint8Array(16)), b => b.toString(16).padStart(2, '0')).join('');
  }
  add(action, x = 0, y = 0) {
    if (this.closed) return;
    const limit = action === 'wheel' ? 1200 : 512;
    x = Math.max(-limit, Math.min(limit, x)); y = Math.max(-512, Math.min(512, y));
    const last = this.queue.at(-1);
    if (['move', 'wheel'].includes(action) && last?.action === action) {
      last.x = Math.max(-limit, Math.min(limit, last.x + x)); last.y = Math.max(-512, Math.min(512, last.y + y));
    } else {
      if (this.queue.length >= 24) { this.fail(); return; }
      this.queue.push({ action, x, y });
    }
    this.timer ??= setTimeout(() => { this.timer = null; void this.drain(); }, 25);
  }
  hold(value) {
    clearInterval(this.heartbeat); this.add(value ? 'down' : 'up');
    if (value) this.heartbeat = setInterval(() => this.add('hold'), 500);
  }
  release() { clearInterval(this.heartbeat); this.queue = []; this.add('up'); }
  fail() { clearInterval(this.heartbeat); this.queue = []; this.send(`mouse:${this.session}:up`).catch(() => {}); if (!this.closed) this.onError(); }
  async drain() {
    if (this.busy) return; this.busy = true;
    try {
      while (this.queue.length) {
        const e = this.queue.shift();
        const tail = e.action === 'move' ? `move:${Math.round(e.x)}:${Math.round(e.y)}` : e.action === 'wheel' ? `wheel:${Math.max(-1200, Math.min(1200, Math.round(e.x)))}` : e.action;
        if (await this.send(`mouse:${this.session}:${tail}`) !== 'input_ok') { this.fail(); break; }
      }
    } catch { this.fail(); } finally { this.busy = false; }
  }
  dispose() { this.release(); this.closed = true; }
}
