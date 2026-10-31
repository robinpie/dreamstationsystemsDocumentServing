// "Notify me of updates to <product>" -> ten browser notifications, right now.
// The product name is read from the <strong> in the .notify box.
(function () {
  var box = document.querySelector('.notify');
  if (!box) return;
  var strong = box.querySelector('strong');
  var product = strong ? strong.textContent.trim() : 'this product';

  var status = document.createElement('p');
  status.className = 'status';
  status.setAttribute('role', 'status');
  box.appendChild(status);

  // A service worker is needed for notifications on Android Chrome, which
  // refuses `new Notification()` from a page. Desktop falls back to that.
  var swReady = null;
  if ('serviceWorker' in navigator) {
    swReady = navigator.serviceWorker.register('sw.js').then(function () {
      return navigator.serviceWorker.ready;
    }).catch(function () { return null; });
  }

  function blast() {
    var title = 'Hansen Discount Electronics';
    var stamp = Date.now();
    var show = function (reg) {
      for (var i = 0; i < 10; i++) {
        var opts = {
          body: 'Remember that ' + product + ' exists!',
          icon: 'images/tick.png',
          tag: 'hde-' + stamp + '-' + i // distinct tags, so they don't collapse into one
        };
        if (reg) reg.showNotification(title, opts);
        else new Notification(title, opts);
      }
      status.textContent = "You're subscribed!";
    };
    (swReady || Promise.resolve(null)).then(show, function () { show(null); });
  }

  function onClick(e) {
    e.preventDefault();
    if (!('Notification' in window)) {
      status.textContent = "Your browser can't do notifications. Remember that " + product + ' exists!';
      return;
    }
    if (Notification.permission === 'granted') return blast();
    if (Notification.permission === 'denied') {
      status.textContent = 'Notifications are blocked. Remember that ' + product + ' exists anyway!';
      return;
    }
    // Older Safari uses the callback form, newer browsers the promise form.
    var p = Notification.requestPermission(function (r) { if (r === 'granted') blast(); });
    if (p && p.then) p.then(function (r) {
      if (r === 'granted') blast();
      else status.textContent = 'No notifications? Fine. Remember that ' + product + ' exists!';
    });
  }

  var links = box.querySelectorAll('a');
  for (var i = 0; i < links.length; i++) links[i].addEventListener('click', onClick);
})();
