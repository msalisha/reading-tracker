// Offline support: the app shell is cached on install, fonts and the barcode library are cached the first time they load.
// Bump VERSION whenever app files change so phones pick up the new version.
const VERSION = 'rt-v3';
const SHELL = ['./', 'index.html', 'styles.css', 'app.js', 'seed.js', 'manifest.webmanifest', 'icons/icon.svg', 'icons/icon-192.png', 'icons/apple-touch-icon.png', 'vendor/zxing.min.js'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // book lookups always go to the network
  if (/openlibrary\.org|googleapis\.com\/books/.test(url.href)) return;
  const sameOrigin = url.origin === location.origin;
  const cacheable = sameOrigin || /fonts\.(googleapis|gstatic)\.com|cdn\.jsdelivr\.net/.test(url.host);
  if (!cacheable) return;
  if (sameOrigin) {
    // the app's own files: network first so updates arrive straight away; the cached copy when offline
    const key = req.mode === 'navigate' ? 'index.html' : req;
    e.respondWith(fetch(req).then(r => { if (r.ok) { const copy = r.clone(); caches.open(VERSION).then(c => c.put(key, copy)); } return r; })
      .catch(() => caches.match(key, { ignoreSearch: true })));
    return;
  }
  e.respondWith(caches.match(req).then(hit => {
    const net = fetch(req).then(r => { if (r.ok || r.type === 'opaque') { const copy = r.clone(); caches.open(VERSION).then(c => c.put(req, copy)); } return r; });
    return hit || net;
  }));
});
