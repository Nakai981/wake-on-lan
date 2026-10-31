import os from 'node:os';
import net from 'node:net';
import { execFile } from 'node:child_process';

export function selectLan(ip = process.env.LAN_IP, interfaces = os.networkInterfaces()) {
  const addresses = Object.entries(interfaces).flatMap(([name, values]) =>
    (values || []).filter(a => a.family === 'IPv4' && !a.internal)
      .map(a => ({ ...a, name })));
  const virtual = name => /vethernet|hyper-v|vmware|virtualbox|vbox|docker|wsl|tailscale|zerotier|tun\d*|tap\d*|vpn|loopback/i.test(name);
  const score = a => (virtual(a.name) ? -100 : 0) +
    (/^(169\.254\.|0\.)/.test(a.address) ? -200 : 0) +
    (/wi-?fi|wlan|wireless|ethernet|^en\w*|^eth\d+$/i.test(a.name) ? 20 : 0);
  const selected = ip ? addresses.find(a => a.address === ip) : addresses.sort((a, b) => score(b) - score(a))[0];
  if (!selected) throw Error('Set LAN_IP to the IPv4 address of the LAN bridge.');
  return { ip: selected.address, mask: selected.netmask, interface: selected.name };
}

export function probeTcp(ip, port, { timeout = 700, connect = net.connect } = {}) {
  return new Promise(resolve => {
    const socket = connect({ host: ip, port });
    let done = false;
    const finish = result => { if (done) return; done = true; socket.destroy(); resolve(result); };
    socket.setTimeout(timeout, () => finish('silent'));
    socket.once('connect', () => finish('open'));
    // A refusal is evidence that the IP answers, even with no service open.
    socket.once('error', error => finish(error.code === 'ECONNREFUSED' ? 'refused' : 'silent'));
  });
}
export async function tcpEvidence(ip, probe = probeTcp) {
  if (!net.isIPv4(ip)) throw Error('Invalid IPv4 target');
  const results = await Promise.all([47991, 445, 3389, 22, 80].map(port => probe(ip, port)));
  return { reachable: results.includes('open'), responds: results.some(result => result !== 'silent') };
}
export function pingHost(ip, { platform = process.platform, run = execFile } = {}) {
  if (!net.isIPv4(ip)) return Promise.resolve(false);
  const args = platform === 'win32' ? ['-n', '1', '-w', '700', ip] : ['-n', '-c', '1', '-W', '1', ip];
  return new Promise(resolve => run('ping', args, { timeout: 1600, windowsHide: true, maxBuffer: 8192 },
    (error, stdout) => resolve(!error && /\bttl[= ]\d+/i.test(stdout))));
}
export async function discoverHost(ip, { tcp = tcpEvidence, ping = pingHost } = {}) {
  const evidence = await tcp(ip);
  if (evidence.responds) return { found: true, via: evidence.reachable ? 'tcp' : 'tcp-refused' };
  return await ping(ip) ? { found: true, via: 'icmp' } : { found: false, via: null };
}
