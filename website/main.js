/* =========================================================================
   AI Boxing Coach — site interactions
   Vanilla JS, no dependencies. Everything degrades gracefully.
   ========================================================================= */
(function () {
  'use strict';

  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------------------------------------------------------------------
     Analytics: a thin, provider-agnostic event bus.
     Wire window.dataLayer / gtag / Plausible etc. in one place later.
     --------------------------------------------------------------------- */
  window.dataLayer = window.dataLayer || [];
  function track(event, params) {
    var payload = Object.assign({ event: event, ts: Date.now() }, params || {});
    window.dataLayer.push(payload);
    if (typeof window.gtag === 'function') window.gtag('event', event, params || {});
    // console.debug('[analytics]', payload);
  }

  // Any element with data-analytics fires a click event with its value.
  document.addEventListener('click', function (e) {
    var el = e.target.closest('[data-analytics]');
    if (el) track('cta_click', { id: el.getAttribute('data-analytics'), text: (el.textContent || '').trim() });
  });

  /* ---------------------------------------------------------------------
     Footer year
     --------------------------------------------------------------------- */
  var y = document.querySelector('[data-year]');
  if (y) y.textContent = new Date().getFullYear();

  /* ---------------------------------------------------------------------
     Mobile menu
     --------------------------------------------------------------------- */
  var toggle = document.querySelector('.nav__toggle');
  var menu = document.getElementById('mobile-menu');
  if (toggle && menu) {
    toggle.addEventListener('click', function () {
      var open = toggle.getAttribute('aria-expanded') === 'true';
      toggle.setAttribute('aria-expanded', String(!open));
      menu.hidden = open;
    });
    menu.addEventListener('click', function (e) {
      if (e.target.closest('a')) { toggle.setAttribute('aria-expanded', 'false'); menu.hidden = true; }
    });
  }

  /* ---------------------------------------------------------------------
     Reveal on scroll
     --------------------------------------------------------------------- */
  var revealEls = document.querySelectorAll('.reveal');
  if (reduceMotion || !('IntersectionObserver' in window)) {
    revealEls.forEach(function (el) { el.classList.add('in-view'); });
  } else {
    var revObs = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) { entry.target.classList.add('in-view'); revObs.unobserve(entry.target); }
      });
    }, { threshold: 0.15, rootMargin: '0px 0px -8% 0px' });
    revealEls.forEach(function (el) { revObs.observe(el); });
  }

  /* ---------------------------------------------------------------------
     Count-up stats
     --------------------------------------------------------------------- */
  var counters = document.querySelectorAll('[data-count]');
  function runCount(el) {
    var target = parseFloat(el.getAttribute('data-count')) || 0;
    var suffix = el.getAttribute('data-suffix') || '';
    if (reduceMotion) { el.textContent = target + suffix; return; }
    var start = performance.now(), dur = 1100;
    function step(now) {
      var p = Math.min((now - start) / dur, 1);
      var eased = 1 - Math.pow(1 - p, 3);
      el.textContent = Math.round(target * eased) + suffix;
      if (p < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }
  if ('IntersectionObserver' in window) {
    var cObs = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) { runCount(entry.target); cObs.unobserve(entry.target); }
      });
    }, { threshold: 0.6 });
    counters.forEach(function (el) { cObs.observe(el); });
  } else {
    counters.forEach(runCount);
  }

  /* ---------------------------------------------------------------------
     Hero demo: cycle record -> analyse -> error -> correct
     Pauses when off-screen; shows a representative state if reduced-motion.
     --------------------------------------------------------------------- */
  var demo = document.querySelector('[data-demo]');
  if (demo) {
    var statusEl = demo.querySelector('[data-demo-status]');
    var tagEl = demo.querySelector('[data-demo-tag]');
    var textEl = demo.querySelector('[data-demo-text]');
    var phases = [
      { key: 'record',  status: '● REC',           tag: 'Recording',  text: 'Recording round · front camera', dur: 2000 },
      { key: 'analyse', status: 'ANALYSING',       tag: 'Analysing',  text: 'Reading pose · 16 fps · on-device', dur: 2000 },
      { key: 'error',   status: 'ISSUE DETECTED',  tag: 'Detected',   text: 'Lead hand dropped after the cross — head exposed.', dur: 2600 },
      { key: 'correct', status: 'CORRECTED',       tag: 'Fixed',      text: 'Lead hand tight to the cheek through the rotation.', dur: 2400 }
    ];
    var i = -1, timer = null, running = false;

    function apply(p) {
      demo.setAttribute('data-phase', p.key);
      if (statusEl) statusEl.textContent = p.status;
      if (tagEl) tagEl.textContent = p.tag;
      if (textEl) textEl.textContent = p.text;
    }
    function next() {
      i = (i + 1) % phases.length;
      var p = phases[i];
      apply(p);
      timer = setTimeout(next, p.dur);
    }
    function start() { if (running) return; running = true; next(); }
    function stop() { running = false; clearTimeout(timer); }

    if (reduceMotion) {
      apply(phases[2]); // show the "issue detected" state statically
    } else if ('IntersectionObserver' in window) {
      var dObs = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) { entry.isIntersecting ? start() : stop(); });
      }, { threshold: 0.35 });
      dObs.observe(demo);
    } else {
      start();
    }
  }

  /* ---------------------------------------------------------------------
     Before / after compare slider
     --------------------------------------------------------------------- */
  document.querySelectorAll('[data-compare]').forEach(function (root) {
    var top = root.querySelector('[data-compare-top]');
    var divider = root.querySelector('[data-compare-divider]');
    var range = root.querySelector('[data-compare-range]');
    if (!top || !divider || !range) return;
    function set(v) {
      top.style.width = v + '%';
      divider.style.left = v + '%';
    }
    range.addEventListener('input', function () { set(range.value); });
    set(range.value);
  });

  /* ---------------------------------------------------------------------
     Signup forms (stubbed — wire to your provider in submit())
     --------------------------------------------------------------------- */
  function isEmail(v) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v); }

  document.querySelectorAll('[data-signup]').forEach(function (form) {
    var msg = form.querySelector('[data-signup-msg]');
    var input = form.querySelector('input[type="email"]');
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var email = (input && input.value || '').trim();
      if (!isEmail(email)) {
        if (msg) { msg.textContent = 'Enter a valid email address.'; msg.classList.add('is-error'); }
        if (input) input.focus();
        return;
      }
      if (msg) { msg.classList.remove('is-error'); msg.textContent = "You're on the list. We'll be in touch."; }
      track('signup', { list: form.getAttribute('data-signup'), email_domain: email.split('@')[1] || '' });
      form.reset();
      // TODO: POST { email } to your beta list / CRM here.
    });
  });

  // "Join the hardware waitlist" jump focuses the beta email with intent tagged.
  var jump = document.querySelector('[data-signup-jump]');
  if (jump) {
    jump.addEventListener('click', function (e) {
      e.preventDefault();
      var input = document.getElementById('beta-email');
      if (input) { input.focus(); input.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'center' }); }
    });
  }
})();
