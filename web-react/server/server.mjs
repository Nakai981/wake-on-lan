import http from 'node:http';
import net from 'node:net';
import dgram from 'node:dgram';
import { selectLan, tcpEvidence, discoverHost } from './network.mjs';
export { selectLan } from './network.mjs';
import path from 'node:path';
import { stat } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { WebSocketServer } from 'ws';
import { createReadStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { deviceInfo } from './device-info.mjs';

const root = path.resolve(fileURLToPath(new URL('../dist/', import.meta.url)));
const number = ip => ip.split('.').reduce((n, v) => (n * 256 + Number(v)) >>> 0, 0);
export function lanAddress(ip, lan) {
  return net.isIPv4(ip) && ((number(ip) & number(lan.mask)) >>> 0) ===
    ((number(lan.ip) & number(lan.mask)) >>> 0);
}
export function magicPacket(mac) {
  if (!/^([\da-f]{2}:){5}[\da-f]{2}$/i.test(mac)) throw Error('Invalid MAC');
  const bytes = Buffer.from(mac.replaceAll(':', ''), 'hex');
  if ((bytes[0] & 1) || bytes.every(b => b === 0)) throw Error('Invalid MAC');
  return Buffer.concat([Buffer.alloc(6, 255), ...Array(16).fill(bytes)]);
}
async function wake(body, lan) {
  const { broadcast, port, retries } = body;
  if (!lanAddress(broadcast, lan) || !Number.isInteger(port) || port < 1 || port > 65535 ||
      !Number.isInteger(retries) || retries < 1 || retries > 10) throw Error('Invalid wake target');
  const packet = magicPacket(body.mac);
  const attempts = [];
  const socket = dgram.createSocket('udp4');
  try {
    await new Promise((resolve, reject) => {
      socket.once('error', reject);
      socket.bind(0, lan.ip, () => { socket.setBroadcast(true); resolve(); });
    });
    for (let i = 0; i < retries; i++) {
      const bytes = await new Promise((resolve, reject) => socket.send(packet, port, broadcast,
        (error, sent) => error ? reject(error) : resolve(sent)));
      attempts.push({ attempt: i + 1, bytes, sentAt: new Date().toISOString() });
      if (i + 1 < retries) await new Promise(resolve => setTimeout(resolve, 250));
    }
    return { sent: true, target: { address: broadcast, port }, source: socket.address(),
      packetBytes: packet.length, packetHex: packet.toString('hex').toUpperCase(), attempts };
  } finally { socket.close(); }
}
const types = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.ico': 'image/x-icon', '.ttf': 'font/ttf', '.otf': 'font/otf', '.css': 'text/css' };

export function createBridge({ lan = selectLan(), webRoot = root,
  origin = process.env.PUBLIC_ORIGIN } = {}) {
  const allowed = req => {
    // Exact configured origin also protects against DNS rebinding. No wildcard CORS.
    const expected = origin || `http://localhost:${server.address().port}`;
    return req.headers.host === new URL(expected).host &&
      (!req.headers.origin || req.headers.origin === expected ||
        (process.env.DEV_ORIGIN && req.headers.origin === process.env.DEV_ORIGIN));
  };
  const server = http.createServer(async (req, res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Cache-Control', 'no-cache');
    try {
      if (!allowed(req)) { res.writeHead(403).end(); return; }
      const url = new URL(req.url, 'http://localhost');
      if (url.pathname.startsWith('/api/')) {
        res.setHeader('Cache-Control', 'no-store');
        if (req.method !== 'POST' || req.headers['content-type'] !== 'application/json') {
          res.writeHead(405).end(); return;
        }
        let raw = '';
        for await (const chunk of req) {
          raw += chunk;
          if (raw.length > 4096) { res.writeHead(413).end(); return; }
        }
        const body = JSON.parse(raw || '{}');
        let data;
        if (url.pathname === '/api/network') data = lan;
        else if (url.pathname === '/api/device-info') {
          if (!lanAddress(body.ip, lan)) throw Error('Target outside LAN');
          data = await deviceInfo(body.ip);
        }
        else if (url.pathname === '/api/reachable') {
          if (!lanAddress(body.ip, lan)) throw Error('Target outside LAN');
          data = { reachable: (await tcpEvidence(body.ip)).reachable };
        } else if (url.pathname === '/api/discover') {
          if (!lanAddress(body.ip, lan)) throw Error('Target outside LAN');
          data = body.ip === lan.ip ? { found: true, via: 'bridge' } : await discoverHost(body.ip);
        } else if (url.pathname === '/api/wake') {
          data = await wake(body, lan);
        } else { res.writeHead(404).end(); return; }
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify(data)); return;
      }
      if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405).end(); return; }
      const file = path.resolve(webRoot, '.' + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
      if (!file.startsWith(path.resolve(webRoot) + path.sep)) { res.writeHead(403).end(); return; }
      if (!(await stat(file)).isFile()) { res.writeHead(404).end(); return; }
      res.setHeader('Content-Type', types[path.extname(file)] || (file.endsWith('.webmanifest') ? 'application/manifest+json' : 'application/octet-stream'));
      res.setHeader('Vary', 'Accept-Encoding');
      let source = file;
      const accept = req.headers['accept-encoding'] || '';
      for (const [encoding, suffix] of [['br', '.br'], ['gzip', '.gz']]) {
        if (new RegExp(`(?:^|[, ])${encoding}(?:[, ]|$)`).test(accept)) {
          try { await stat(file + suffix); source = file + suffix; res.setHeader('Content-Encoding', encoding); break; } catch { /* uncompressed fallback */ }
        }
      }
      if (url.pathname.startsWith('/assets/')) res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
      res.setHeader('Content-Length', (await stat(source)).size);
      if (req.method === 'HEAD') res.end(); else await pipeline(createReadStream(source), res);
    } catch (error) {
      if (res.headersSent) { res.destroy(); return; }
      res.writeHead(error.code === 'ENOENT' ? 404 : 400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Bridge request failed. Check LAN settings and target.' }));
    }
  });
  server.requestTimeout = 10000;
  const sockets = new WebSocketServer({ noServer: true, maxPayload: 1024 });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://localhost');
    const ip = url.searchParams.get('ip');
    if (!allowed(req) || !req.headers.origin || url.pathname !== '/api/agent' || !lanAddress(ip, lan)) {
      socket.end('HTTP/1.1 403 Forbidden\r\n\r\n'); return;
    }
    sockets.handleUpgrade(req, socket, head, ws => {
      const tcp = net.connect({ host: ip, port: 47991 });
      tcp.setTimeout(10000, () => tcp.destroy());
      tcp.on('data', data => { if (ws.readyState === 1) ws.send(data.toString('ascii')); });
      ws.on('message', (data, binary) => {
        if (binary || data.length > 1024) { ws.close(1008); return; }
        tcp.write(data);
      });
      tcp.on('error', () => ws.close(1011));
      tcp.on('close', () => ws.close());
      ws.on('close', () => tcp.destroy());
      ws.on('error', () => tcp.destroy());
    });
  });
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const server = createBridge();
  const port = Number(process.env.PORT || 8787);
  server.on('error', error => {
    if (error.code === 'EADDRINUSE') {
      console.error(`Cổng ${port} đang được sử dụng. Nếu Wake My PC đã chạy, mở http://localhost:${port}.`);
      console.error(`Hoặc chọn cổng khác trong PowerShell: $env:PORT = '8788'; npm.cmd start`);
    } else {
      console.error(`Không khởi động được server: ${error.message}`);
    }
    process.exitCode = 1;
  });
  server.listen(port, process.env.HOST || '127.0.0.1', () =>
    { console.log(`Wake My PC: ${process.env.PUBLIC_ORIGIN || `http://localhost:${port}`}`);
      const lan = selectLan(); console.log(`LAN: ${lan.interface} ${lan.ip} / ${lan.mask} (override with LAN_IP)`); });
}
