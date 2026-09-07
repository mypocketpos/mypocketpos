(function () {
  const mount = document.getElementById('subscriptions-mount');
  if (!mount) return;

  const state = {
    cycle: 'monthly',
    plans: [],
  };

  function setVisibility(el, show) {
    if (!el) return;
    if (show) {
      el.removeAttribute('hidden');
    } else {
      el.setAttribute('hidden', 'hidden');
    }
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
    if (typeof url !== 'string' || url.trim().length === 0) return '/?app=1';
    try {
      const parsed = new URL(url, window.location.origin);
      const allowedProtocol = parsed.protocol === 'https:' || parsed.protocol === 'http:';
      if (!allowedProtocol) return '/?app=1';
      if (parsed.origin !== window.location.origin && parsed.protocol !== 'https:') {
        return '/?app=1';
      }
      return parsed.toString();
    } catch (_) {
      return '/?app=1';
    }
  }

  function createPlanCard(plan) {
    const card = document.createElement('article');
    card.className = 'sub-card';
    if (plan.isPopular === true) {
      card.classList.add('popular');
    }

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
    title.textContent = typeof plan.name === 'string' ? plan.name : 'Plan';
    card.appendChild(title);

    const desc = document.createElement('p');
    desc.className = 'sub-desc';
    desc.textContent = typeof plan.description === 'string' ? plan.description : '';
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
    for (const feature of features) {
      const item = document.createElement('li');
      item.textContent = String(feature || '').trim();
      if (!item.textContent) continue;
      list.appendChild(item);
    }
    card.appendChild(list);

    const cta = document.createElement('a');
    cta.className = 'sub-cta';
    cta.textContent =
      typeof plan.ctaLabel === 'string' && plan.ctaLabel.trim().length > 0
        ? plan.ctaLabel.trim()
        : 'Start now';
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
    for (const plan of filtered) {
      grid.appendChild(createPlanCard(plan));
    }

    setVisibility(loading, false);
    setVisibility(error, false);
    setVisibility(empty, filtered.length === 0);
    setVisibility(grid, filtered.length > 0);
  }

  async function ensureTemplate() {
    const response = await fetch('/subscriptions.html', { credentials: 'same-origin' });
    if (!response.ok) {
      throw new Error('subscriptions template load failed');
    }
    const html = await response.text();
    const template = document.createElement('template');
    template.innerHTML = html;
    mount.appendChild(template.content.cloneNode(true));
  }

  function waitForFirebaseReady(timeoutMs) {
    return new Promise((resolve, reject) => {
      const started = Date.now();
      const timer = setInterval(() => {
        const firebaseReady =
          window.firebase &&
          typeof window.firebase.initializeApp === 'function' &&
          typeof window.firebase.firestore === 'function';

        if (firebaseReady) {
          clearInterval(timer);
          try {
            if (!window.firebase.apps || window.firebase.apps.length === 0) {
              window.firebase.initializeApp();
            }
          } catch (_) {
            // If init is already handled by Firebase Hosting init.js this can throw.
          }
          resolve(window.firebase);
          return;
        }

        if (Date.now() - started > timeoutMs) {
          clearInterval(timer);
          reject(new Error('firebase-not-ready'));
        }
      }, 120);
    });
  }

  function subscribePlans(firebase) {
    const loading = document.getElementById('subs-loading');
    const empty = document.getElementById('subs-empty');
    const error = document.getElementById('subs-error');
    const grid = document.getElementById('subs-grid');

    setVisibility(loading, true);
    setVisibility(empty, false);
    setVisibility(error, false);
    setVisibility(grid, false);

    firebase
      .firestore()
      .collection('platform_subscription_plans')
      .where('isActive', '==', true)
      .where('publicVisible', '==', true)
      .where('deletedAt', '==', null)
      .orderBy('sortOrder', 'asc')
      .onSnapshot(
        (snapshot) => {
          state.plans = snapshot.docs.map((doc) => {
            const data = doc.data() || {};
            data.id = doc.id;
            return data;
          });
          render();
        },
        () => {
          setVisibility(loading, false);
          setVisibility(empty, false);
          setVisibility(grid, false);
          setVisibility(error, true);
        }
      );
  }

  function attachEvents() {
    const monthlyBtn = document.getElementById('subs-cycle-monthly');
    const yearlyBtn = document.getElementById('subs-cycle-yearly');
    if (monthlyBtn) {
      monthlyBtn.addEventListener('click', () => {
        state.cycle = 'monthly';
        render();
      });
    }
    if (yearlyBtn) {
      yearlyBtn.addEventListener('click', () => {
        state.cycle = 'yearly';
        render();
      });
    }
  }

  (async function init() {
    try {
      await ensureTemplate();
      attachEvents();
      const firebase = await waitForFirebaseReady(9000);
      subscribePlans(firebase);
    } catch (_) {
      const loading = document.getElementById('subs-loading');
      const error = document.getElementById('subs-error');
      const empty = document.getElementById('subs-empty');
      const grid = document.getElementById('subs-grid');
      setVisibility(loading, false);
      setVisibility(empty, false);
      setVisibility(grid, false);
      setVisibility(error, true);
    }
  })();
})();
