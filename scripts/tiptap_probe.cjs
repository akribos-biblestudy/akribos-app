#!/usr/bin/env node
'use strict';

// Read-only, synthetic probe of an extracted *published* tiptap_flutter archive.
// Uses Playwright already installed in the sibling backend. No npm install,
// backend server, account, network request or application write is involved.
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { createRequire } = require('node:module');
const path = require('node:path');

const packageDir = process.env.TIPTAP_PACKAGE_DIR;
if (!packageDir) {
  console.error('Set TIPTAP_PACKAGE_DIR to an extracted published tiptap_flutter archive.');
  process.exit(2);
}
const backendDir = path.resolve(process.env.AKRIBOS_BACKEND_DIR || path.join(__dirname, '../../akribos'));
const requireBackend = createRequire(path.join(backendDir, 'package.json'));
const { chromium } = requireBackend('playwright');
const bundle = readFileSync(path.join(packageDir, 'assets/engine/tiptap-engine.js'), 'utf8');
const packageYaml = readFileSync(path.join(packageDir, 'pubspec.yaml'), 'utf8');
const hash = createHash('sha256').update(bundle).digest('hex');
const knownPublishedHash = '22e35aa61ffba84cf798ba1c07e949982cefef0f76662d6b2c5f81877851bbe9';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  await context.route('**/*', route => route.abort());
  let sequence = 0;
  async function inspect(content, commands = [], editable = true) {
    const page = await context.newPage();
    page.setDefaultTimeout(10000);
    try {
      await page.setContent('<!doctype html><div id="editor"></div>');
      await page.evaluate(() => {
        window.probeMessages = [];
        window.TiptapBridge = { postMessage: raw => window.probeMessages.push(JSON.parse(raw)) };
      });
      await page.addScriptTag({ content: bundle });
      async function command(name, payload = {}) {
        const id = `probe-${++sequence}`;
        await page.evaluate(message => window.TiptapEngine.handleCommand(JSON.stringify(message)), {
          type: 'command', id, name, payload,
        });
        await page.waitForFunction(id => window.probeMessages.some(message => message.type === 'response' && message.id === id), id);
        const response = await page.evaluate(id => window.probeMessages.find(message => message.type === 'response' && message.id === id), id);
        if (!response.success) throw new Error(`${name}: ${JSON.stringify(response)}`);
        return response.payload;
      }
      await command('init', { content, editable });
      for (const [name, payload] of commands) await command(name, payload);
      return {
        html: (await command('getContent', { format: 'html' })).content,
        document: (await command('getContent', { format: 'json' })).content,
      };
    } finally {
      await page.close();
    }
  }
  try {
    const selectStart = ['setTextSelection', { anchor: 1 }];
    const results = {
      nestedListAndQuote: await inspect('<ul><li><p>Parent</p><blockquote><p>Quote</p></blockquote><ul><li><p>Child</p></li></ul></li></ul>'),
      customSchema: await inspect('<p><mark>Highlight</mark> Text<sup data-footnote-ref="n">1</sup></p><table><tbody><tr><th>Header</th><th>Other</th></tr><tr><td>Cell one</td><td>Cell two</td></tr></tbody></table><ol data-footnotes="true"><li data-footnote-id="n"><p>Footnote</p></li></ol>'),
      explicitListCommand: await inspect('<p>Parent</p>', [selectStart, ['exec', { command: 'toggleBulletList' }]]),
      plainTextInsertion: await inspect('<p></p>', [selectStart, ['insertText', { text: '<strong>X</strong>' }]]),
      bulletTyping: await inspect('<p></p>', [selectStart, ['insertText', { text: '-' }], ['insertText', { text: ' ' }]]),
      headingTyping: await inspect('<p></p>', [selectStart, ['insertText', { text: '##' }], ['insertText', { text: ' ' }]]),
      readOnlyCommand: await inspect('<p>Original</p>', [selectStart, ['insertText', { text: 'CHANGED ' }]], false),
    };
    const observed = {
      nestedListAndQuoteKept: results.nestedListAndQuote.html.includes('<blockquote><p>Quote</p></blockquote><ul>'),
      explicitListCommandWorks: results.explicitListCommand.html.startsWith('<ul>'),
      tableKept: results.customSchema.html.includes('<table'),
      highlightKept: results.customSchema.html.includes('<mark>'),
      footnoteIdentityKept: results.customSchema.html.includes('data-footnote-ref="n"') && results.customSchema.html.includes('data-footnote-id="n"'),
      insertedTextIsLiteral: results.plainTextInsertion.html.includes('&lt;strong&gt;X&lt;/strong&gt;'),
      bulletInputRuleRuns: results.bulletTyping.html.startsWith('<ul>'),
      headingInputRuleRuns: results.headingTyping.html.startsWith('<h2>'),
      readOnlyRejectsMutationCommand: results.readOnlyCommand.html === '<p>Original</p>',
    };
    console.log(JSON.stringify({
      packageVersion: /^version:\s*(\S+)/m.exec(packageYaml)?.[1],
      bundleSha256: hash,
      matchesAuditedPublished030: hash === knownPublishedHash,
      nodeVersion: process.version,
      chromiumVersion: browser.version(),
      observed,
      results,
    }, null, 2));
  } finally {
    await context.close();
    await browser.close();
  }
})().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
