/* Simple scroll reveal animation */
document.addEventListener('DOMContentLoaded', function() {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('revealed');
      }
    });
  }, {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
  });

  document.querySelectorAll('.scroll-reveal').forEach(el => {
    observer.observe(el);
  });
});


/* Conversion Tracking */

// Conversion tracking function
function trackConversion(event, data) {
  if (typeof gtag !== 'undefined') {
    gtag('event', event, {
      event_category: 'conversion',
      event_label: data.label || 'unknown',
      value: data.value || 0
    });
    console.log('📊 Tracked:', event, data);
  }

  // Also track in Clarity if available
  if (typeof clarity !== 'undefined') {
    clarity('event', event);
  }
}

// Email signup tracking
document.addEventListener('DOMContentLoaded', function() {
  const emailForms = document.querySelectorAll('[data-track="email-signup"]');

  emailForms.forEach(form => {
    form.addEventListener('submit', function(e) {
     const location = this.dataset.location || 'unknown';

      trackConversion('email_signup', {
        label: location,
        value: 100  // Assign $100 value to email signups
      });

      // Let the form submit normally to Formspree
    });
  });
});


const RUBYGEMS_API = "https://rubygems.org/api/v1";

async function fetchJson(url) {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}: ${url}`);
  }

  return response.json();
}

async function fetchRubyGem(name) {
  const encodedName = encodeURIComponent(name);

  const [gem, versions] = await Promise.all([
    fetchJson(`${RUBYGEMS_API}/gems/${encodedName}.json`),
    fetchJson(`${RUBYGEMS_API}/versions/${encodedName}.json`)
  ]);

  const releases = versions
      .filter(version => !version.yanked)
      .sort(
          (a, b) =>
              new Date(a.created_at).getTime() -
              new Date(b.created_at).getTime()
      );

  return {
    version: gem.version,
    downloads: gem.downloads,
    versionDownloads: gem.version_downloads,

    firstRelease: releases.at(0)?.created_at ?? null,
    latestRelease: gem.version_created_at,

    releases: releases.length
  };
}

function formatNumber(value) {
  return new Intl.NumberFormat().format(value);
}

function formatDate(value) {
  return new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric"
  }).format(new Date(value));
}

async function hydrateProduct(element) {
  const gemName = element.dataset.rubygem;

  if (!gemName) return;

  try {
    const product = await fetchRubyGem(gemName);

    element.querySelectorAll("[data-product-version]")
        .forEach(el => el.textContent = product.version);

    element.querySelectorAll("[data-product-downloads]")
        .forEach(el => el.textContent = formatNumber(product.downloads));

    element.querySelectorAll("[data-product-first-release]")
        .forEach(el => {
          el.dateTime = product.firstRelease;
          el.textContent = formatDate(product.firstRelease);
        });

    element.querySelectorAll("[data-product-latest-release]")
        .forEach(el => {
          el.dateTime = product.latestRelease;
          el.textContent = formatDate(product.latestRelease);
        });

    element.dataset.productHydrated = "";
  } catch (error) {
    console.warn(`Unable to hydrate ${gemName}`, error);
    element.dataset.productUnavailable = "";
  }
}

document
    .querySelectorAll("[data-product]")
    .forEach(hydrateProduct);

/* Copy-to-clipboard buttons: <button data-copy-target="code-element-id" hidden>.
   Buttons stay hidden where the Clipboard API is unavailable. */
document.addEventListener('DOMContentLoaded', function() {
  if (!navigator.clipboard) return;

  document.querySelectorAll('[data-copy-target]').forEach(button => {
    const target = document.getElementById(button.dataset.copyTarget);
    if (!target) return;

    const label = button.querySelector('[data-copy-label]');
    const status = button.closest('section')?.querySelector('[data-copy-status]');
    let timer;

    button.hidden = false;
    button.addEventListener('click', () => {
      navigator.clipboard.writeText(target.textContent).then(() => {
        if (label) label.textContent = 'Copied';
        if (status) status.textContent = 'Copied to clipboard';
        clearTimeout(timer);
        timer = setTimeout(() => {
          if (label) label.textContent = 'Copy';
          if (status) status.textContent = '';
        }, 2000);
      }).catch(() => {
        if (status) status.textContent = 'Copy failed';
      });
    });
  });
});
