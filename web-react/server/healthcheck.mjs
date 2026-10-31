import http from 'node:http';

// Check the local bridge even when PUBLIC_ORIGIN is an HTTPS reverse proxy.
const origin = new URL(process.env.PUBLIC_ORIGIN || `http://localhost:${process.env.PORT || 8787}`);
const request = http.request({
  hostname: '127.0.0.1', port: Number(process.env.PORT || 8787), path: '/api/network',
  method: 'POST', headers: { Host: origin.host, 'Content-Type': 'application/json' },
  timeout: 4000
}, response => {
  response.resume();
  process.exitCode = response.statusCode === 200 ? 0 : 1;
});
request.on('timeout', () => request.destroy());
request.on('error', () => { process.exitCode = 1; });
request.end('{}');
