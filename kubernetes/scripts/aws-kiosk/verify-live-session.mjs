// Usage: KIOSK_URL=https://your-kiosk.example.com node verify-live-session.mjs
import { chromium } from 'playwright';
const KIOSK_URL = process.env.KIOSK_URL ?? 'https://miniprem-kiosk.services.uneeq.io/';
const browser = await chromium.launch({ args: ['--use-fake-ui-for-media-devices','--use-fake-device-for-media-stream'] });
const page = await (await browser.newContext({ permissions: ['microphone'] })).newPage();
await page.goto(KIOSK_URL, { waitUntil: 'networkidle', timeout: 45000 });
await page.waitForTimeout(4000);
await page.getByText(/start digital human/i).first().click();
await page.waitForTimeout(35000);
for (const f of page.frames()) {
  const n = await f.locator('video').count().catch(()=>0);
  if (n) for (let i=0;i<n;i++) {
    const v = f.locator('video').nth(i);
    console.log(`FRAME ${f.url().slice(0,60)} VIDEO[${i}]: readyState=${await v.evaluate(e=>e.readyState)} playing=${await v.evaluate(e=>!e.paused)} ${await v.evaluate(e=>e.videoWidth)}x${await v.evaluate(e=>e.videoHeight)}`);
  }
}
await page.screenshot({ path: 'kiosk-live2.png' });
await browser.close();
