/* Mission Canvas — Landing Page JS
   Handles: hero fade-in, demo animation, copy button, theme toggle, nav scroll-hide
*/

// ── Hero entrance animation ──────────────────────────────────────
const heroItems = document.querySelectorAll('.hero .fade-in');
heroItems.forEach((el, i) => {
  setTimeout(() => {
    el.classList.add('visible');
  }, 100 + i * 120);
});

// ── Nav: hide on scroll down, show on scroll up ──────────────────
(function navScrollBehavior() {
  const nav = document.getElementById('nav');
  let lastY = 0;
  let ticking = false;

  window.addEventListener('scroll', () => {
    if (!ticking) {
      requestAnimationFrame(() => {
        const y = window.scrollY;
        if (y > 80) {
          nav.classList.add('nav--scrolled');
          nav.classList.toggle('nav--hidden', y > lastY + 10);
        } else {
          nav.classList.remove('nav--scrolled', 'nav--hidden');
        }
        lastY = y;
        ticking = false;
      });
      ticking = true;
    }
  }, { passive: true });
})();

// ── OS-specific download labels ───────────────────────────────────
(function osDetect() {
  var p = (navigator.userAgentData && navigator.userAgentData.platform)
    || navigator.platform || '';
  var isWin = /Win/.test(p);
  var isMac = /Mac/.test(p);

  function configure(primaryId, secondaryId) {
    var primary = document.getElementById(primaryId);
    var secondary = document.getElementById(secondaryId);
    if (!primary || !secondary) return;
    if (isWin) {
      primary.textContent = 'Download for Windows';
      primary.href = 'https://github.com/pretendhome/missioncanvas.ai/releases/latest/download/MissionCanvas-Setup.exe';
      secondary.textContent = 'Download for macOS';
      secondary.href = 'https://github.com/pretendhome/missioncanvas.ai/releases/latest/download/MissionCanvas.dmg';
    } else if (!isMac) {
      primary.textContent = 'Download for Linux';
      primary.href = 'https://github.com/pretendhome/missioncanvas.ai/releases/latest/download/MissionCanvas.AppImage';
    }
  }
  configure('btn-primary-dl', 'btn-secondary-dl');
  configure('btn-primary-dl-2', 'btn-secondary-dl-2');
})();

// ── Theme toggle ──────────────────────────────────────────────────
(function themeInit() {
  const toggle = document.querySelector('[data-theme-toggle]');
  const root = document.documentElement;
  var _currentTheme = 'dark';
  function setTheme(theme) {
    root.dataset.theme = theme;
    _currentTheme = theme;
    const isDark = theme === 'dark' || (!theme && true);
    if (toggle) {
      toggle.setAttribute('aria-label', isDark ? 'Switch to light mode' : 'Switch to dark mode');
      toggle.innerHTML = isDark
        ? `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>`
        : `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>`;
    }
  }

  // Default: dark
  setTheme('dark');

  if (toggle) {
    toggle.addEventListener('click', () => {
      const current = _currentTheme || 'dark';
      setTheme(current === 'dark' ? 'light' : 'dark');
    });
  }
})();

// ── Demo window animation ─────────────────────────────────────────
(function demoAnimation() {
  const DEMOS = [
    {
      prompt: "Draft a response to the Acme escalation using the contract terms from my legal folder.",
      chips: [
        { text: '🔒 LOCAL ONLY', cls: 'chip chip-local' },
        { text: 'MC-LEGAL-004', cls: 'chip chip-node' },
        { text: 'legal lens', cls: 'chip chip-lens' },
        { text: '3 sources', cls: 'chip chip-sources' },
      ],
      answer: "Based on Section 12.4 of the Master Services Agreement (March 2024), Acme's 72-hour SLA window began on July 14. The escalation clause requires written acknowledgment within 4 business hours of receipt. I've drafted the response using the indemnification language from Exhibit B...",
      trace: ['SCAN:pass', 'CLASSIFY:contract_review', 'TRAVERSE:legal→fiduciary', 'BLOCKS_EXTERNAL:true', 'KL:3_entries', 'REASON:local', 'STORE:path_record'],
    },
    {
      prompt: "What are the HIPAA audit requirements for AI decisions involving patient data?",
      chips: [
        { text: '🔒 LOCAL ONLY', cls: 'chip chip-local' },
        { text: 'MC-HC-002', cls: 'chip chip-node' },
        { text: 'clinical lens', cls: 'chip chip-lens' },
        { text: '5 sources', cls: 'chip chip-sources' },
      ],
      answer: "Under HIPAA 2026 Final Rule (effective August 2, 2026), any AI-assisted decision involving PHI requires an immutable audit log — including model identity, query hash, and consent status. Mission Canvas generates this automatically on every query. Confidence: 0.91...",
      trace: ['SCAN:PHI_detected', 'CLASSIFY:phi_data_mapping', 'BLOCKS_EXTERNAL:true', 'TIER:1_source', 'KL:5_entries', 'REASON:local', 'STORE:path_record'],
    },
    {
      prompt: "What does the market expect from the Fed at the next two meetings?",
      chips: [
        { text: '⬡ EXTERNAL', cls: 'chip chip-external' },
        { text: 'MC-FIN-003', cls: 'chip chip-node' },
        { text: 'research mode', cls: 'chip chip-lens' },
        { text: '4 sources', cls: 'chip chip-sources' },
      ],
      answer: "Fed funds futures as of July 17 imply an 84% probability of a hold at the July 30 meeting, with a 25bp cut priced at ~67% for September. CME FedWatch shows the market has repriced significantly since June CPI...",
      trace: ['SCAN:pass', 'CLASSIFY:market_data', 'BLOCKS_EXTERNAL:false', 'ROUTE:external_research', 'KL:4_entries', 'REASON:cloud', 'STORE:path_record'],
    },
  ];

  const promptEl    = document.getElementById('demoPrompt');
  const cursorEl    = document.getElementById('demoCursor');
  const chipsEl     = document.getElementById('demoChips');
  const answerEl    = document.getElementById('demoAnswer');
  const traceEl     = document.getElementById('demoTrace');

  if (!promptEl) return;

  let currentDemo = 0;
  let animating = false;

  async function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
  }

  async function typeText(el, text, speed = 28) {
    el.textContent = '';
    for (const char of text) {
      el.textContent += char;
      await sleep(speed + Math.random() * 20);
    }
  }

  async function revealText(el, text, chunkSize = 4) {
    el.textContent = '';
    const words = text.split(' ');
    for (let i = 0; i < words.length; i += chunkSize) {
      el.textContent += words.slice(i, i + chunkSize).join(' ') + ' ';
      await sleep(60);
    }
  }

  async function runDemo(demo) {
    if (animating) return;
    animating = true;

    // Reset
    promptEl.textContent = '';
    chipsEl.innerHTML = '';
    answerEl.textContent = '';
    traceEl.innerHTML = '';
    if (cursorEl) cursorEl.style.display = 'inline';

    // Type the prompt
    await typeText(promptEl, demo.prompt, 22);

    await sleep(400);

    // Hide cursor, show "thinking" state
    if (cursorEl) cursorEl.style.display = 'none';
    await sleep(300);

    // Add governance chips one by one
    for (const chip of demo.chips) {
      const span = document.createElement('span');
      span.className = chip.cls;
      span.textContent = chip.text;
      span.style.opacity = '0';
      span.style.transform = 'scale(0.85)';
      span.style.transition = 'opacity 0.2s ease, transform 0.2s ease';
      chipsEl.appendChild(span);
      await sleep(30);
      requestAnimationFrame(() => {
        span.style.opacity = '1';
        span.style.transform = 'scale(1)';
      });
      await sleep(180);
    }

    await sleep(200);

    // Stream the answer
    await revealText(answerEl, demo.answer, 3);

    await sleep(300);

    // Show pipeline trace items
    for (const t of demo.trace) {
      const div = document.createElement('span');
      div.className = 'demo-trace-item';
      div.textContent = t;
      traceEl.appendChild(div);
      await sleep(80);
    }

    await sleep(3500);
    animating = false;

    // Next demo
    currentDemo = (currentDemo + 1) % DEMOS.length;
    runDemo(DEMOS[currentDemo]);
  }

  // Start after hero is visible
  setTimeout(() => runDemo(DEMOS[0]), 1200);
})();
