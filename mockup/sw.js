// Side Quest service worker (V2): the app shell opens instantly and still loads with no signal; everything live
// (events, people, chats) always comes from the network. Only same-origin static files are ever cached.
const CACHE = 'sq-shell-v2-1';
const SHELL = ['/', '/logo.png', '/icon-192.png', '/manifest.webmanifest', '/vendor/leaflet.js', '/vendor/leaflet.css'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin) return;           // other sites (map tiles, photos): untouched
  if (u.pathname.startsWith('/api/') || u.pathname === '/config.js' || u.pathname.startsWith('/story-') || u.pathname.startsWith('/avatar/')) return;
  if (e.request.mode === 'navigate') {   // the page: always fresh when online, the saved copy when not
    e.respondWith(fetch(e.request).then(r => { const c = r.clone(); caches.open(CACHE).then(x => x.put('/', c)); return r; })
      .catch(() => caches.match('/')));
    return;
  }
  if (u.pathname.startsWith('/vendor/') || /\.(png|webmanifest)$/.test(u.pathname)) {   // static files: saved copy first
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(r => {
      if (r.ok) { const c = r.clone(); caches.open(CACHE).then(x => x.put(e.request, c)); }
      return r;
    })));
  }
});
// Tapping a system notification brings the app forward.
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window' }).then(ws => ws.length ? ws[0].focus() : self.clients.openWindow('/')));
});
