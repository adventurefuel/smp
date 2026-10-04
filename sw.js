/* Swurl Kurl store app — receives push alerts for new appointments and purchases */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: 'Swurl Kurl', body: e.data && e.data.text() }; }
  e.waitUntil((async () => {
    await self.registration.showNotification(d.title || 'Swurl Kurl', {
      body: d.body || 'New activity',
      tag: d.tag || undefined,
      renotify: true,
      requireInteraction: true,
      icon: '/img/icon-192.png',
      badge: '/img/badge-96.png',
      vibrate: [250, 120, 250, 120, 500],
      data: { url: d.url || '/store.html#appointments' }
    });
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    wins.forEach((c) => c.postMessage({ type: 'push', payload: d }));
  })());
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || '/store.html', self.location.origin).href;
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of wins) {
      if (c.url.includes('/store')) { await c.focus(); if (c.navigate) await c.navigate(url); return; }
    }
    await self.clients.openWindow(url);
  })());
});
