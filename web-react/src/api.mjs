import { normalizeCode, ipv4Number } from './core.mjs';
export async function api(route, body = {}, signal) {
  try {
    const res = await fetch(`/api/${route}`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body), signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(8000)]) : AbortSignal.timeout(8000) });
    if (!res.ok) throw Error();
    return await res.json();
  } catch (error) {
    if (signal?.aborted) throw error;
    throw Error('Không kết nối được LAN bridge hoặc địa chỉ ngoài subnet. Kiểm tra bridge và mạng LAN.');
  }
}
const hex = data => Array.from(new Uint8Array(data), b => b.toString(16).padStart(2, '0')).join('');
const unhex = text => Uint8Array.from(text.match(/../g), v => parseInt(v, 16));
export async function agentRequest(ip, code, command, { base = globalThis.location?.origin, WebSocketImpl = globalThis.WebSocket } = {}) {
  ipv4Number(ip); normalizeCode(code);
  if (!globalThis.crypto?.subtle) throw Error('Ghép nối Agent cần HTTPS hoặc localhost.');
  const key = await crypto.subtle.importKey('raw', unhex(code), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
  const sign = async text => hex(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(text)));
  const url = new URL('/api/agent', base); url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'; url.searchParams.set('ip', ip);
  return new Promise((resolve, reject) => {
    const ws = new WebSocketImpl(url); let buffer = '', challenge, nonce, processing = false, done = false;
    const finish = (error, result) => { if (done) return; done = true; clearTimeout(timer); ws.close(); error ? reject(error) : resolve(result); };
    const timer = setTimeout(() => finish(Error('Agent không phản hồi. Kiểm tra IP, mã ghép nối và firewall TCP 47991.')), 7000);
    const pump = async () => {
      if (processing || done) return; processing = true;
      try {
        while (buffer.includes('\n') && !done) {
          const i = buffer.indexOf('\n'), line = buffer.slice(0, i); buffer = buffer.slice(i + 1);
          if (!challenge) {
            const parts = /^WMP1 ([a-f0-9]{64})$/.exec(line);
            if (!parts) throw Error('Windows Agent không hợp lệ.');
            challenge = parts[1]; nonce = hex(crypto.getRandomValues(new Uint8Array(32)));
            ws.send(`${command} ${nonce} ${await sign(`request\n${challenge}\n${nonce}\n${command}`)}\n`);
          } else {
            const parts = /^([a-z_]+) ([a-f0-9]{64})$/.exec(line);
            if (!parts || !['online', 'accepted', 'cancelled', 'busy', 'simulated', 'input_ok', 'input_busy', 'input_failed', 'input_expired', 'unsupported'].includes(parts[1])) throw Error('Phản hồi Agent không hợp lệ.');
            const valid = await crypto.subtle.verify('HMAC', key, unhex(parts[2]), new TextEncoder().encode(`response\n${challenge}\n${nonce}\n${command}\n${parts[1]}`));
            if (!valid) throw Error('Không xác thực được phản hồi từ PC.');
            finish(null, parts[1]);
          }
        }
      } catch (error) { finish(error); } finally { processing = false; }
    };
    ws.onmessage = event => {
      if (typeof event.data !== 'string' || /[^\x20-\x7e\n]/.test(event.data)) { finish(Error('Phản hồi Agent không hợp lệ.')); return; }
      buffer += event.data;
      if (buffer.split('\n').some(line => line.length > 512)) { finish(Error('Phản hồi Agent quá dài.')); return; }
      void pump();
    };
    ws.onerror = () => finish(Error('Không kết nối được Windows Agent.'));
    ws.onclose = () => { if (!done && !processing) finish(Error('Sai mã ghép nối hoặc Agent đóng kết nối.')); };
  });
}

// Non-extractable AES key and encrypted pairing codes remain in this origin's IndexedDB.
async function database() {
  if (!crypto.subtle) throw Error('Lưu mã ghép nối cần HTTPS hoặc localhost.');
  return new Promise((resolve, reject) => {
    const req = indexedDB.open('wake-my-pc-vault', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('secrets');
    req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error);
  });
}
async function access(mode, operation) {
  const db = await database();
  try { return await new Promise((resolve, reject) => {
    const tx = db.transaction('secrets', mode), req = operation(tx.objectStore('secrets'));
    tx.oncomplete = () => resolve(req?.result); tx.onerror = () => reject(tx.error); tx.onabort = () => reject(tx.error);
  }); } finally { db.close(); }
}
let vaultKey;
async function encryptionKey() {
  vaultKey ??= (async () => {
    let key = await access('readonly', store => store.get('key'));
    if (!key) {
      key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
      // Serialize initialization with an IndexedDB read-write transaction across tabs.
      const db = await database();
      key = await new Promise((resolve, reject) => {
        const tx = db.transaction('secrets', 'readwrite'), store = tx.objectStore('secrets');
        const req = store.get('key'); let selected;
        req.onsuccess = () => { selected = req.result || key; if (!req.result) store.put(selected, 'key'); };
        tx.oncomplete = () => { db.close(); resolve(selected); }; tx.onerror = () => { db.close(); reject(tx.error); };
      });
    }
    return key;
  })();
  return vaultKey;
}
export async function saveCode(id, code) {
  const key = await encryptionKey(), iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(normalizeCode(code)));
  await access('readwrite', store => store.put({ iv, data }, 'pc.' + id));
}
export async function readCode(id) {
  const item = await access('readonly', store => store.get('pc.' + id));
  if (!item) throw Error('Hãy ghép nối Windows Agent trước.');
  return new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: item.iv }, await encryptionKey(), item.data));
}
export const forgetCode = id => access('readwrite', store => store.delete('pc.' + id));
export const commandPc = async (pc, command) => agentRequest(pc.ip, await readCode(pc.id), command);
