import os from 'node:os';
import net from 'node:net';
import dns from 'node:dns/promises';
import { execFile } from 'node:child_process';

export function validMac(value) {
  const mac = value?.replaceAll('-', ':').toUpperCase();
  return mac && /^([\dA-F]{2}:){5}[\dA-F]{2}$/.test(mac) &&
    !(parseInt(mac.slice(0, 2), 16) & 1) && mac !== '00:00:00:00:00:00' ? mac : null;
}
export function parseNeighbor(output, ip) {
  for (const line of output.split(/\r?\n/)) {
    // Require the exact target IP in the same row; never use a different neighbor.
    if (!line.split(/[\s()]+/).includes(ip)) continue;
    const match = line.match(/\b(?:[\da-f]{2}[:-]){5}[\da-f]{2}\b/i);
    if (match) return validMac(match[0]);
  }
  return null;
}
function run(file, args) {
  return new Promise(resolve => execFile(file, args,
    { timeout: 1500, windowsHide: true, maxBuffer: 65536 },
    (error, stdout) => resolve(error ? '' : stdout)));
}
export async function deviceInfo(ip, { interfaces = os.networkInterfaces(), hostname = os.hostname,
  reverse = dns.reverse, execute = run, platform = process.platform } = {}) {
  if (!net.isIPv4(ip)) throw Error('Invalid IP');
  const local = Object.values(interfaces).flat().find(a => a.family === 'IPv4' && a.address === ip);
  if (local) return { ip, name: hostname(), mac: validMac(local.mac), source: 'local' };
  const macTask = (async () => {
    if (platform === 'linux') {
      const result = parseNeighbor(await execute('ip', ['neigh', 'show', ip]), ip);
      if (result) return result;
    }
    return parseNeighbor(await execute('arp', platform === 'win32' ? ['-a', ip] : ['-n', ip]), ip);
  })();
  const nameTask = (async () => {
    let timer;
    try {
      const names = await Promise.race([reverse(ip), new Promise(resolve => { timer = setTimeout(() => resolve([]), 1200); })]);
      return names?.[0]?.replace(/\.$/, '') || null;
    } catch { return null; } finally { clearTimeout(timer); }
  })();
  const [mac, name] = await Promise.all([macTask, nameTask]);
  return { ip, mac, name, source: 'neighbor' };
}
