(function () {
  const state = {
    cycle: 'monthly',
    plans: [],
    firebaseLoaded: false
  };

  function setVisibility(el, show) {
    if (!el) return;
    show ? el.removeAttribute('hidden') : el.setAttribute('hidden', 'hidden');
  }

  function normalizeCycle(raw) {
    return raw === 'yearly' ? 'yearly' : 'monthly';
  }

  function formatInrMinor(minor) {
    const safeMinor = Number.isFinite(minor) ? minor : 0;
    return new Intl.NumberFormat('en-IN', {
      style: 'currency',
      currency: 'INR',
      maximumFractionDigits: 2,
    }).format(safeMinor / 100);
  }

  function safeCtaUrl(url) {
    if (typeof url !== 'string' || !url.trim()) return '/?app=1';
    try {
      const parsed = new URL(url, window.location.origin);
      if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') return '/?app=1';
      return parsed.toString();
    } catch (_) {
      return '/?app=1';
    }
  }

  function createPlanCard(plan) {
    const card = document.createElement('article');
    card.className = 'sub-card';
    if (plan.isPopular) card.classList.add('popular');

    const badgeLabel = typeof plan.badgeText === 'string' && plan.badgeText.trim().length > 0
      ? plan.badgeText.trim()
      : (plan.isPopular ? 'Most Popular' : '');
    
    if (badgeLabel) {
      const badge = document.createElement('span');
      badge.className = 'sub-badge';
      badge.textContent = badgeLabel;
      card.appendChild(badge);
    }

    const title = document.createElement('h3');
    title.className = 'sub-title';
    title.textContent = plan.name || 'Plan';
    card.appendChild(title);

    const desc = document.createElement('p');
    desc.className = 'sub-desc';
    desc.textContent = plan.description || '';
    card.appendChild(desc);

    const price = document.createElement('div');
    price.className = 'sub-price';
    price.textContent = formatInrMinor(Number(plan.priceMinor));
    card.appendChild(price);

    const unit = document.createElement('div');
    unit.className = 'sub-price-unit';
    unit.textContent = plan.billingCycle === 'yearly' ? 'per year' : 'per month';
    card.appendChild(unit);

    const list = document.createElement('ul');
    list.className = 'sub-features';
    const features = Array.isArray(plan.featureList) ? plan.featureList : [];
    features.forEach((feature) => {
      const text = String(feature || '').trim();
      if (text) {
        const item = document.createElement('li');
        item.textContent = text;
        list.appendChild(item);
      }
    });
    card.appendChild(list);

    const cta = document.createElement('a');
    cta.className = 'sub-cta';
    cta.textContent = plan.ctaLabel && plan.ctaLabel.trim() ? plan.ctaLabel.trim() : 'Start now';
    cta.href = safeCtaUrl(plan.ctaUrl);
    cta.rel = 'noopener noreferrer';
    if (cta.href.startsWith('http') && !cta.href.includes(window.location.origin)) {
      cta.target = '_blank';
    }
    card.appendChild(cta);

    return card;
  }

  function render() {
    const loading = document.getElementById('subs-loading');
    const empty = document.getElementById('subs-empty');
    const error = document.getElementById('subs-error');
    const grid = document.getElementById('subs-grid');
    const monthlyBtn = document.getElementById('subs-cycle-monthly');
    const yearlyBtn = document.getElementById('subs-cycle-yearly');

    if (!grid || !loading || !empty || !error || !monthlyBtn || !yearlyBtn) return;

    monthlyBtn.classList.toggle('is-active', state.cycle === 'monthly');
    monthlyBtn.setAttribute('aria-selected', state.cycle === 'monthly' ? 'true' : 'false');
    yearlyBtn.classList.toggle('is-active', state.cycle === 'yearly');
    yearlyBtn.setAttribute('aria-selected', state.cycle === 'yearly' ? 'true' : 'false');

    const filtered = state.plans.filter((p) => normalizeCycle(p.billingCycle) === state.cycle);

    grid.textContent = '';
    filtered.forEach((plan) => grid.appendChild(createPlanCard(plan)));

    setVisibility(loading, false);
    setVisibility(error, false);
    setVisibility(empty, filtered.length === 0);
    setVisibility(grid, filtered.length > 0);
  }

  // Load Firebase scripts dynamically on demand
  function loadScript(src) {
    return new Promise((resolve, reject) => {
      if (document.querySelector(`script[src="${src}"]`)) return resolve();
      const s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  async function initFirebase() {
    if (state.firebaseLoaded) return;
    state.firebaseLoaded = true;

    try {
      await loadScript('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
      await loadScript('https://www.gstatic.com/firebasejs/10.13.2/firebase-firestore-compat.js');

      if (!window.firebase.apps.length) {
        window.firebase.initializeApp({
          apiKey: "AIzaSyBDHpJHhF_Q1wP_uJf5MhV4cBxJ3xP4L8c",
          authDomain: "pocketpos-firebase.firebaseapp.com",
          projectId: "pocketpos-firebase",
          storageBucket: "pocketpos-firebase.appspot.com",
          messagingSenderId: "123456789012",
          appId: "1:123456789012:web:abcdef1234567890"
        });
      }

      subscribePlans(window.firebase);
    } catch (_) {
      showError();
    }
  }

  function showError() {
    setVisibility(document.getElementById('subs-loading'), false);
    setVisibility(document.getElementById('subs-empty'), false);
    setVisibility(document.getElementById('subs-grid'), false);
    setVisibility(document.getElementById('subs-error'), true);
  }

  function subscribePlans(firebase) {
    firebase
      .firestore()
      .collection('platform_subscription_plans')
      .where('isActive', '==', true)
      .where('publicVisible', '==', true)
      .where('deletedAt', '==', null)
      .orderBy('sortOrder', 'asc')
      .onSnapshot(
        (snapshot) => {
          state.plans = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
          render();
        },
        () => showError()
      );
  }

  function attachEvents() {
    const monthlyBtn = document.getElementById('subs-cycle-monthly');
    const yearlyBtn = document.getElementById('subs-cycle-yearly');
    if (monthlyBtn) monthlyBtn.addEventListener('click', () => { state.cycle = 'monthly'; render(); });
    if (yearlyBtn) yearlyBtn.addEventListener('click', () => { state.cycle = 'yearly'; render(); });
  }

  // Use IntersectionObserver to lazy load Firebase only when section comes into view
  function setupLazyObserver() {
    const section = document.getElementById('pricing');
    if (!section) return initFirebase();

    if ('IntersectionObserver' in window) {
      const observer = new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting) {
          initFirebase();
          observer.disconnect();
        }
      }, { rootMargin: '200px' });
      observer.observe(section);
    } else {
      initFirebase();
    }
  }

  document.addEventListener('DOMContentLoaded', () => {
    attachEvents();
    setupLazyObserver();
  });
})();