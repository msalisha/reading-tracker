// Renders the advert frame by frame and encodes it with ffmpeg.
// usage: node render.js [a|b] [out.mp4]      (needs playwright and ffmpeg)
const { chromium } = require('playwright');
const { spawnSync } = require('child_process');
const fs = require('fs'), path = require('path'), os = require('os');
(async () => {
  const hook = process.argv[2] || 'a';
  const out = process.argv[3] || path.join(__dirname, `pageturner-advert-9x16${hook === 'a' ? '' : '-' + hook}.mp4`);
  const fps = 30, frames = fs.mkdtempSync(path.join(os.tmpdir(), 'advert-'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 360, height: 640 }, deviceScaleFactor: 3 });
  await page.goto('file://' + path.join(__dirname, 'index.html') + '?hook=' + hook);
  await page.waitForLoadState('networkidle');
  await page.evaluate(() => document.fonts.ready);
  const duration = await page.evaluate(() => window.DURATION);
  const total = Math.round(duration * fps);
  for (let f = 0; f < total; f++) {
    await page.evaluate(t => window.setTime(t), f / fps);
    await page.screenshot({ path: path.join(frames, String(f).padStart(5, '0') + '.png') });
  }
  if (process.env.STILLS) {   // one picture per scene, for checking
    for (const [i, t] of [1.8, 5.8, 9.8, 12.6, 14.3, 16.2, 18.2, 19.9, 23.4, 27.2].entries()) {
      await page.evaluate(t => window.setTime(t), t);
      await page.screenshot({ path: path.join(process.env.STILLS, `still-${i}.png`) });
    }
  }
  await browser.close();
  const r = spawnSync('ffmpeg', ['-v', 'error', '-y', '-framerate', String(fps), '-i', path.join(frames, '%05d.png'),
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow', '-movflags', '+faststart', out], { stdio: 'inherit' });
  fs.rmSync(frames, { recursive: true, force: true });
  if (r.status !== 0) process.exit(1);
  console.log('wrote', out, `${duration}s`);
})();
