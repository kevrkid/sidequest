// Side Quest service worker (V2): the app shell opens instantly and still loads with no signal; everything live
// (events, people, chats) always comes from the network. Only same-origin static files are ever cached.
const CACHE = 'sq-shell-v3-10';
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
    e.respondWith(fetch(e.request).then(r => {   // only the app itself is saved (not /lens, /privacy.html...)
      if (u.pathname === '/' && r.ok) { const c = r.clone(); caches.open(CACHE).then(x => x.put('/', c)); }
      return r;
    }).catch(() => caches.match('/')));
    return;
  }
  if (u.pathname.startsWith('/vendor/') || /\.(png|webmanifest)$/.test(u.pathname)) {   // static files: saved copy first
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(r => {
      if (r.ok) { const c = r.clone(); caches.open(CACHE).then(x => x.put(e.request, c)); }
      return r;
    })));
  }
});
// Web Push from the server (encrypted for this phone only): show it, even with the app closed.
self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch (x) { d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Side Quest', {
    body: d.body || '', icon: '/icon-192.png', badge: '/icon-192.png', tag: d.tag || undefined, data: { url: d.url || '/' } }));
});
// Tapping a notification opens the app on that thing (an event, a group, the inbox).
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || '/';
  e.waitUntil(self.clients.matchAll({ type: 'window' }).then(ws => {
    const w = ws.find(x => new URL(x.url).origin === location.origin);
    return w ? w.focus().then(x => x.navigate(url)) : self.clients.openWindow(url);
  }));
});
