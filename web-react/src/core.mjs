export function ipv4Number(ip) {
  if (typeof ip !== 'string' || !/^(\d{1,3}\.){3}\d{1,3}$/.test(ip) || ip.split('.').some(p => +p > 255)) throw Error('Địa chỉ IPv4 không hợp lệ.');
  return ip.split('.').reduce((n, p) => (n * 256 + +p) >>> 0, 0);
}
export const ipv4String = n => [24, 16, 8, 0].map(b => n >>> b & 255).join('.');
export function normalizeMac(value) {
  const mac = value.trim().replaceAll('-', ':').toUpperCase();
  if (!/^([\dA-F]{2}:){5}[\dA-F]{2}$/.test(mac) || (parseInt(mac.slice(0, 2), 16) & 1) || mac === '00:00:00:00:00:00') throw Error('Nhập MAC Ethernet hợp lệ, ví dụ A4:BB:6D:12:34:56.');
  return mac;
}
export function lanInfo({ ip, mask, interface: interfaceName }) {
  const address = ipv4Number(ip), m = ipv4Number(mask), inverse = ~m >>> 0;
  if ((inverse & (inverse + 1)) !== 0) throw Error('Subnet không hợp lệ.');
  const network = (address & m) >>> 0, end = (network | inverse) >>> 0;
  const start = end - network > 255 ? (address & 0xffffff00) >>> 0 : network;
  const last = end - network > 255 ? start + 255 : end;
  return { ip, mask, interface: interfaceName, broadcast: ipv4String(end), key: `${ipv4String(network)}/${mask}`,
    contains: value => ((ipv4Number(value) & m) >>> 0) === network,
    hosts: Array.from({ length: Math.max(0, last - start - 1) }, (_, i) => ipv4String(start + i + 1)) };
}
export function validatePc(pc) {
  if (!pc.name.trim()) throw Error('Nhập tên máy tính.');
  const mac = normalizeMac(pc.mac);
  if (pc.ip) ipv4Number(pc.ip);
  if (pc.broadcast) ipv4Number(pc.broadcast);
  for (const [key, min, max] of [['port', 1, 65535], ['retries', 1, 10], ['timeout', 5, 300]]) {
    if (!Number.isInteger(+pc[key]) || +pc[key] < min || +pc[key] > max) throw Error(`${key}: nhập số từ ${min} đến ${max}.`);
  }
  const startupDelay = Number(pc.startupDelay ?? 20);
  if (!Number.isInteger(startupDelay) || startupDelay < 10 || startupDelay > 30) throw Error('Thời gian chờ khởi động phải từ 10 đến 30 giây.');
  return { ...pc, name: pc.name.trim(), mac, port: +pc.port, retries: +pc.retries, timeout: +pc.timeout, startupDelay };
}
export function parsePairQr(raw) {
  try {
    if (raw.length > 512) throw Error();
    const u = new URL(raw), q = u.searchParams;
    if (u.protocol !== 'wakemypc:' || u.hostname !== 'pair' || u.pathname || u.port || u.username || u.password || u.hash ||
      [...q].length !== 4 || new Set(q.keys()).size !== 4 || q.get('v') !== '1') throw Error();
    const ip = q.get('ip'), n = ipv4Number(ip);
    if ((n >>> 24) === 0 || (n >>> 24) === 127 || (n >>> 24) >= 224) throw Error();
    return { ip, mac: normalizeMac(q.get('mac')), key: normalizeCode(q.get('key')) };
  } catch { throw Error('QR không phải mã ghép nối Wake My PC hợp lệ.'); }
}
export function normalizeCode(code) {
  const value = code.trim().replace(/[\s-]/g, '').toLowerCase();
  if (!/^[\da-f]{32}$/.test(value)) throw Error('Nhập mã 32 ký tự từ Windows Agent.');
  return value;
}
export function textCommand(text) {
  const bytes = new TextEncoder().encode(text);
  if (!bytes.length || bytes.length > 240 || /[\u0000-\u001f\u007f-\u009f]/.test(text)) throw Error('Mỗi lần gửi tối đa 240 byte UTF-8, không chứa ký tự điều khiển.');
  return 'text:' + btoa(String.fromCharCode(...bytes));
}
export function keyCommand(key, modifiers = []) {
  const keys = { Esc: 27, Tab: 9, Enter: 13, Backspace: 8, Delete: 46, Space: 32, '←': 37, '↑': 38, '→': 39, '↓': 40 };
  const vk = keys[key] ?? (/^F([1-9]|1[0-2])$/.test(key) ? 111 + +key.slice(1) : /^[A-Z0-9]$/.test(key) ? key.charCodeAt(0) : null);
  if (!vk) throw Error('Phím chưa được hỗ trợ.');
  return `key:${modifiers.reduce((m, v) => m | ({ Ctrl: 1, Alt: 2, Shift: 4, Win: 8 }[v] || 0), 0)}:${vk}`;
}
export const quickCommands = { Desktop: 'key:8:68', 'Đổi cửa sổ': 'key:2:9', 'Chụp màn hình': 'key:12:83', 'Tìm kiếm': 'key:8:83', 'Bài trước': 'key:0:177', 'Phát / Dừng': 'key:0:179', 'Bài sau': 'key:0:176', 'Tắt / Bật tiếng': 'key:0:173', 'Giảm âm lượng': 'key:0:174', 'Tăng âm lượng': 'key:0:175' };
export async function scanLan(lan, { signal, progress, probe }) {
  let next = 0, done = 0;
  await Promise.all(Array.from({ length: 12 }, async () => {
    while (!signal.aborted && next < lan.hosts.length) {
      const ip = lan.hosts[next++], found = await probe(ip, signal);
      if (signal.aborted) return;
      progress(++done, lan.hosts.length, found ? ip : null);
    }
  }));
}
