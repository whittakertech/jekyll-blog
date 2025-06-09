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