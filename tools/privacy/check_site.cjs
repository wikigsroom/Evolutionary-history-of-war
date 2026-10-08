// Native Windows fallback for read-only page QA when Browser's JS kernel cannot start.
// Uses an isolated ephemeral browser and closes every page, context, and process.
const { chromium } = require('C:/Users/carzy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

(async () => {
  const url = process.argv[2];
  const outputDirectory = process.argv[3];
  const proxyArgument = process.argv.find(argument => argument.startsWith('--proxy='));
  const proxy = proxyArgument ? { server: proxyArgument.slice('--proxy='.length) } : undefined;
  if (!url || !outputDirectory) throw new Error('URL and QA output directory are required');
  await fs.mkdir(outputDirectory, { recursive: true });
  const browser = await chromium.launch({
    executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true,
    proxy,
    args: ['--disable-background-networking', '--disable-sync'],
  });
  const report = [];
  try {
    for (const viewport of [
      { name: 'desktop', width: 1280, height: 1000 },
      { name: 'mobile', width: 390, height: 844 },
      { name: 'small-mobile', width: 320, height: 860 },
    ]) {
      const context = await browser.newContext({ viewport: { width: viewport.width, height: viewport.height }, acceptDownloads: true });
      const page = await context.newPage();
      const requests = [];
      page.on('request', request => requests.push(request.url()));
      try {
        const response = await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
        await page.screenshot({ path: path.join(outputDirectory, viewport.name + '.png') });
        const content = await page.evaluate(() => ({
          title: document.title,
          language: document.documentElement.lang,
          viewport: innerWidth,
          pageWidth: document.documentElement.scrollWidth,
          sections: Array.from(document.querySelectorAll('article section[id]')).map(section => section.id),
          scripts: document.scripts.length,
          scriptSources: Array.from(document.scripts).map(script => script.src || '[inline]'),
          forms: document.forms.length,
          brokenAnchors: Array.from(document.querySelectorAll('a[href^="#"]')).map(a => a.getAttribute('href').slice(1)).filter(id => id && !document.getElementById(id)),
          textLength: document.body.innerText.length,
          operatorMissing: /内容校对稿|运营者信息尚未提供|privacy@example\.invalid/.test(document.body.innerText),
        }));
        if (response.status() !== 200 || content.title !== '纪元急袭隐私政策' || content.sections.length !== 10) {
          throw new Error('Privacy page is not accessible or incomplete: ' + JSON.stringify({ status: response.status(), ...content, headers: response.headers() }));
        }
        if (content.pageWidth > content.viewport + 1) throw new Error(viewport.name + ' has horizontal overflow');
        if (content.brokenAnchors.length) throw new Error('Broken section navigation');
        if (content.scripts || content.forms) throw new Error('Unexpected scripts or forms');
        if (content.operatorMissing) throw new Error('Unresolved operator information');
        const expectedOrigin = new URL(url).origin;
        const externalRequests = requests.filter(request => new URL(request).origin !== expectedOrigin);
        if (externalRequests.length) throw new Error('Unexpected external page resources');
        if (viewport.name === 'mobile') {
          await page.locator('.mobile-nav summary').click();
          await page.screenshot({ path: path.join(outputDirectory, 'mobile-directory.png') });
          await page.locator('.mobile-nav a[href="#rights"]').click();
          await page.screenshot({ path: path.join(outputDirectory, 'mobile-rights.png') });
        }
        if (viewport.name === 'desktop') {
          await page.locator('.desktop-nav a[href="#third-parties"]').click();
          await page.screenshot({ path: path.join(outputDirectory, 'desktop-third-parties.png') });
        }
        const downloads = [];
        if (viewport.name === 'desktop') {
          for (const filename of ['privacy-policy.docx', 'privacy-policy.md']) {
            const pendingDownload = page.waitForEvent('download', { timeout: 30000 });
            await page.locator('.downloads a[href="/' + filename + '"]').click();
            const download = await pendingDownload;
            const savedPath = path.join(outputDirectory, filename);
            await download.saveAs(savedPath);
            const failure = await download.failure();
            if (failure) throw new Error('Download failed: ' + failure);
            const actualBytes = await fs.readFile(savedPath);
            const expectedBytes = await fs.readFile(path.resolve(__dirname, '../../web/privacy-policy', filename));
            const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
            if (digest(actualBytes) !== digest(expectedBytes)) throw new Error('Published download differs from final document: ' + filename);
            downloads.push({ filename: download.suggestedFilename(), bytes: actualBytes.length, sha256: digest(actualBytes), matchesFinalDocument: true });
          }
        }
        report.push({ viewportName: viewport.name, status: response.status(), finalUrl: page.url(), headers: response.headers(), ...content, externalRequests, downloads });
      } finally {
        await page.close();
        await context.close();
      }
    }
  } finally {
    await browser.close();
  }
  await fs.writeFile(path.join(outputDirectory, 'report.json'), JSON.stringify(report, null, 2), 'utf8');
  console.log(JSON.stringify({ report, networkProxyUsed: Boolean(proxy), closedAllQaPages: true, closedBrowser: true }));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
