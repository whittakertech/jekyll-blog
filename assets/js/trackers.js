/* Analytics loader (Google Analytics 4, Microsoft Clarity). Nothing loads until the visitor
   accepts in the consent banner (consent.js). The IDs come from data attributes on
   #wt-trackers, which _includes/trackers.html renders in production only; without that
   element this file does nothing. Kept external so a CSP can drop 'unsafe-inline' scripts. */
(function () {
  var cfg = document.getElementById('wt-trackers');
  if (!cfg) return;
  var gaId = cfg.getAttribute('data-ga-id');
  var clarityId = cfg.getAttribute('data-clarity-id');

  window.wtLoadAnalytics = function () {
    if (window.wtAnalyticsLoaded) return;
    window.wtAnalyticsLoaded = true;

    // Google Analytics 4
    window.dataLayer = window.dataLayer || [];
    function gtag() { dataLayer.push(arguments); }
    gtag('js', new Date());
    gtag('config', gaId);
    var gaScript = document.createElement('script');
    gaScript.async = true;
    gaScript.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(gaId);
    document.head.appendChild(gaScript);

    // Microsoft Clarity
    (function (c, l, a, r, i, t, y) {
      c[a] = c[a] || function () { (c[a].q = c[a].q || []).push(arguments); };
      t = l.createElement(r); t.async = 1; t.src = 'https://www.clarity.ms/tag/' + i;
      y = l.getElementsByTagName(r)[0]; y.parentNode.insertBefore(t, y);
    })(window, document, 'clarity', 'script', clarityId);
  };

  window.addEventListener('load', function () {
    if (window.wtConsent && window.wtConsent.get() === 'granted') window.wtLoadAnalytics();
  });
})();
