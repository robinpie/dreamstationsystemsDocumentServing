// Only here so notify.js can show notifications on Android Chrome.
// Clicking a notification focuses (or opens) the site.
self.addEventListener('notificationclick', function (e) {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window' }).then(function (cs) {
    return cs.length ? cs[0].focus() : self.clients.openWindow('./');
  }));
});
