import { readdir, readFile, writeFile } from 'node:fs/promises';
import { brotliCompressSync, gzipSync, constants } from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
async function compress(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) await compress(file);
    else if (/\.(js|css|html|json|webmanifest|ttf|txt)$/.test(file)) {
      const data = await readFile(file);
      if (data.length > 500) {
        await writeFile(file + '.br', brotliCompressSync(data, { params: { [constants.BROTLI_PARAM_QUALITY]: 11 } }));
        await writeFile(file + '.gz', gzipSync(data, { level: 9 }));
      }
    }
  }
}
await compress(fileURLToPath(new URL('../dist/', import.meta.url)));
console.log('Prepared Brotli/gzip files; production server only streams precompressed assets.');
