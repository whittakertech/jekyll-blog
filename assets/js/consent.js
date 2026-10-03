/* Analytics consent banner. Markup lives in _includes/consent.html.
   Shares window.wtConsent with trackers.js. Kept external (not inline) so a CSP can drop 'unsafe-inline' scripts. */
(function () {
  var KEY = 'wt-consent';
  var banner = document.getElementById('consent-banner');

  function read() { try { return window.localStorage.getItem(KEY); } catch (e) { return null; } }
  function write(v) { try { window.localStorage.setItem(KEY, v); } catch (e) {} }
  function clear() { try { window.localStorage.removeItem(KEY); } catch (e) {} }

  window.wtConsent = {
    get: function () {
      if (navigator.globalPrivacyControl) return 'denied';
      return read();
    }
  };

  function show() { banner.hidden = false; }
  function hide() { banner.hidden = true; }

  if (window.wtConsent.get() === null) show();

  banner.addEventListener('click', function (event) {
    var choice = event.target.closest('[data-consent]');
    if (!choice) return;
    write(choice.getAttribute('data-consent'));
    hide();
    if (choice.getAttribute('data-consent') === 'granted' && window.wtLoadAnalytics) window.wtLoadAnalytics();
  });

  document.addEventListener('click', function (event) {
    if (!event.target.closest('[data-consent-open]')) return;
    clear();
    show();
    var first = banner.querySelector('button');
    if (first) first.focus();
  });
})();
