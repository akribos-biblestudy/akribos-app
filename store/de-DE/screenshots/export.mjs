import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(directory, '../../..');
const outputDirectory = path.resolve(directory, '../images/phone-screenshots');
const metadata = JSON.parse(await readFile(path.join(directory, 'captures.json'), 'utf8'));
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

// Use an existing Playwright installation; do not change app dependencies.
let playwright;
for (const base of [path.join(appRoot, 'package.json'), path.resolve(appRoot, '../akribos/package.json')]) {
  try {
    playwright = createRequire(base)(process.env.PLAYWRIGHT_MODULE || 'playwright');
    break;
  } catch (error) {
    if (error.code !== 'MODULE_NOT_FOUND') throw error;
  }
}
assert(playwright, 'Install Playwright in this repository or its sibling akribos, or set PLAYWRIGHT_MODULE.');
await mkdir(outputDirectory, { recursive: true });
for (const capture of metadata.captures) {
  assert.equal(sha256(await readFile(path.join(directory, 'originals', capture.file))), capture.sourceSha256);
  assert(capture.alt.length < 140, `Alt text too long: ${capture.file}`);
}

const mimeTypes = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png' };
const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    const rendered = pathname.startsWith('/rendered/');
    const base = rendered ? outputDirectory : directory;
    const relative = rendered ? pathname.slice('/rendered/'.length) : pathname.slice(1);
    const filename = path.resolve(base, relative);
    if (!filename.startsWith(base + path.sep)) throw new Error('Invalid path');
    response.setHeader('Content-Type', mimeTypes[path.extname(filename)] || 'application/octet-stream');
    response.end(await readFile(filename));
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const baseUrl = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  browser = await playwright.chromium.launch({ headless: true });
  const page = await browser.newPage({
    viewport: { width: metadata.outputWidth, height: metadata.outputHeight },
    deviceScaleFactor: 1,
    colorScheme: 'dark',
  });
  const results = [];
  for (const capture of metadata.captures) {
    await page.goto(`${baseUrl}/pages/${capture.file.replace('.png', '.html')}`);
    await page.locator('img').evaluate((image) => image.decode());
    const bounds = await page.locator('img').boundingBox();
    assert.deepEqual(bounds, { x: metadata.offsetX, y: metadata.offsetY, width: metadata.sourceWidth, height: metadata.sourceHeight });
    const bytes = await page.screenshot({ path: path.join(outputDirectory, capture.file), omitBackground: false, fullPage: false });
    assert.equal(bytes.subarray(1, 4).toString(), 'PNG');
    assert.equal(bytes.readUInt32BE(16), metadata.outputWidth);
    assert.equal(bytes.readUInt32BE(20), metadata.outputHeight);
    assert.equal(bytes[24], 8, 'Expected 8-bit PNG');
    assert.equal(bytes[25], 2, 'Expected opaque RGB PNG without alpha');
    assert(metadata.outputHeight <= 2 * metadata.outputWidth);

    // Read-only decoded-pixel comparison. The canvas never produces output files.
    const validation = await page.evaluate(async ({ filename, offsetX, offsetY }) => {
      const source = document.querySelector('img');
      const output = new Image();
      output.src = `/rendered/${filename}`;
      await output.decode();
      const canvas = document.createElement('canvas');
      canvas.width = output.naturalWidth;
      canvas.height = output.naturalHeight;
      const context = canvas.getContext('2d', { willReadFrequently: true });
      context.drawImage(output, 0, 0);
      const allOutput = context.getImageData(0, 0, canvas.width, canvas.height).data;
      const renderedSource = context.getImageData(offsetX, offsetY, source.naturalWidth, source.naturalHeight).data;
      context.clearRect(0, 0, canvas.width, canvas.height);
      context.drawImage(source, 0, 0);
      const original = context.getImageData(0, 0, source.naturalWidth, source.naturalHeight).data;
      let differentChannels = 0;
      for (let i = 0; i < original.length; i += 1) {
        if (original[i] !== renderedSource[i]) differentChannels += 1;
      }
      let nonOpaquePixels = 0;
      for (let i = 3; i < allOutput.length; i += 4) {
        if (allOutput[i] !== 255) nonOpaquePixels += 1;
      }
      return { sourceWidth: source.naturalWidth, sourceHeight: source.naturalHeight, differentChannels, nonOpaquePixels };
    }, { filename: capture.file, offsetX: metadata.offsetX, offsetY: metadata.offsetY });
    assert.equal(validation.sourceWidth, metadata.sourceWidth);
    assert.equal(validation.sourceHeight, metadata.sourceHeight);
    assert.equal(validation.differentChannels, 0, 'Original pixels must be preserved exactly');
    assert.equal(validation.nonOpaquePixels, 0);
    results.push({ file: capture.file, sourceSha256: capture.sourceSha256, outputSha256: sha256(bytes), width: metadata.outputWidth, height: metadata.outputHeight, pngColorType: 'RGB', ...validation });
    console.log(`${capture.file}: 1620x2880 RGB; source pixels unchanged; ${sha256(bytes)}`);
  }
  await writeFile(path.join(directory, 'export-manifest.json'), JSON.stringify({
    browser: `Chromium ${browser.version()}`,
    deviceScaleFactor: 1,
    background: '#171e18',
    offsetX: metadata.offsetX,
    offsetY: metadata.offsetY,
    results,
  }, null, 2) + '\n');
} finally {
  await browser?.close();
  await new Promise((resolve) => server.close(resolve));
}
