(function () {
  'use strict';

  // DOM Elements
  const elPricingSection = document.getElementById('pricing');
  const elGrid = document.getElementById('subs-grid');
  const elLoading = document.getElementById('subs-loading');
  const elEmpty = document.getElementById('subs-empty');
  const elError = document.getElementById('subs-error');
  const btnMonthly = document.getElementById('subs-cycle-monthly');
  const btnYearly = document.getElementById('subs-cycle-yearly');

  let rawPlans = [];
  let currentCycle = 'monthly';

  // Fetch plans.json from the static hosting directory
  async function fetchPlans() {
    try {
      const response = await fetch('plans.json', { cache: 'no-cache' });
      if (!response.ok) throw new Error(`HTTP error! Status: ${response.status}`);

      const data = await response.json();
      rawPlans = Array.isArray(data) ? data : (data.plans || []);

      if (rawPlans.length === 0) {
        // Hide entire pricing section if no plans
        if (elPricingSection) elPricingSection.style.display = 'none';
        showState('empty');
      } else {
        // Show pricing section if plans exist
        if (elPricingSection) elPricingSection.style.display = 'block';
        renderGrid();
        showState('grid');
      }
    } catch (err) {
      console.error('Failed to load subscription plans:', err);
      // Hide entire pricing section on error
      if (elPricingSection) elPricingSection.style.display = 'none';
      showState('error');
    }
  }

  // Manage section visibility
  function showState(state) {
    if (elLoading) elLoading.hidden = state !== 'loading';
    if (elEmpty) elEmpty.hidden = state !== 'empty';
    if (elError) elError.hidden = state !== 'error';
    if (elGrid) elGrid.hidden = state !== 'grid';
  }

  // Format currency numbers safely
  function formatCurrency(amount) {
    if (amount === undefined || amount === null || isNaN(amount)) return '₹0';
    return new Intl.NumberFormat('en-IN', {
      style: 'currency',
      currency: 'INR',
      maximumFractionDigits: 0
    }).format(amount);
  }

  // Build HTML for plan cards
  function renderGrid() {
    if (!elGrid) return;

    elGrid.innerHTML = '';

    rawPlans.forEach(plan => {
      const isYearly = currentCycle === 'yearly';
      const price = isYearly ? plan.yearlyPrice : plan.monthlyPrice;
      const originalPrice = isYearly ? plan.yearlyOriginalPrice : plan.monthlyOriginalPrice;
      const isPopular = plan.isPopular || plan.popular;

      const card = document.createElement('div');
      card.className = `subs-card ${isPopular ? 'subs-card-popular' : ''}`;

      let featuresHTML = '';
      if (Array.isArray(plan.features)) {
        featuresHTML = plan.features
          .map(f => `<li><svg viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/></svg><span>${f}</span></li>`)
          .join('');
      }

      card.innerHTML = `
        ${isPopular ? '<span class="subs-badge">Most Popular</span>' : ''}
        <h3 class="subs-title">${plan.name || 'Standard Plan'}</h3>
        <p class="subs-desc">${plan.description || ''}</p>
        
        <div class="subs-price-box">
          ${originalPrice && originalPrice > price ? `<span class="subs-original-price">${formatCurrency(originalPrice)}</span>` : ''}
          <div class="subs-price-row">
            <span class="subs-price">${formatCurrency(price)}</span>
            <span class="subs-period">/${isYearly ? 'year' : 'month'}</span>
          </div>
        </div>

        <button class="btn btn-primary subs-cta" data-cta="register" onclick="enterApp()">
          ${plan.ctaText || 'Get Started'}
        </button>

        <ul class="subs-features">
          ${featuresHTML}
        </ul>
      `;

      elGrid.appendChild(card);
    });
  }

  // Toggle billing cycle listeners
  function setupCycleToggle() {
    if (!btnMonthly || !btnYearly) return;

    btnMonthly.addEventListener('click', () => {
      if (currentCycle === 'monthly') return;
      currentCycle = 'monthly';
      btnMonthly.classList.add('is-active');
      btnMonthly.setAttribute('aria-selected', 'true');
      btnYearly.classList.remove('is-active');
      btnYearly.setAttribute('aria-selected', 'false');
      renderGrid();
    });

    btnYearly.addEventListener('click', () => {
      if (currentCycle === 'yearly') return;
      currentCycle = 'yearly';
      btnYearly.classList.add('is-active');
      btnYearly.setAttribute('aria-selected', 'true');
      btnMonthly.classList.remove('is-active');
      btnMonthly.setAttribute('aria-selected', 'false');
      renderGrid();
    });
  }

  // Initialize script on DOM ready
  document.addEventListener('DOMContentLoaded', () => {
    setupCycleToggle();
    fetchPlans();
  });
})();