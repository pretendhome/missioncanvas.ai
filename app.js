/* Mission Canvas — Landing Page JS
   Handles: hero fade-in, demo animation, copy button, theme toggle, nav scroll-hide
*/

// ── Hero entrance animation ──────────────────────────────────────
// Banner fades in first, then hero items stagger after
const banner = document.querySelector('.hero-banner.fade-in');
if (banner) setTimeout(() => banner.classList.add('visible'), 80);

const heroItems = document.querySelectorAll('.hero .fade-in');
heroItems.forEach((el, i) => {
  setTimeout(() => {
    el.classList.add('visible');
  }, 300 + i * 120);
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

// ── Install block copy buttons ───────────────────────────────────
document.querySelectorAll('.install-cmd').forEach(function(block) {
  var copyBtn = block.querySelector('.copy-btn');
  function doCopy() {
    var cmd = block.getAttribute('data-cmd');
    if (!cmd) return;
    navigator.clipboard.writeText(cmd).then(function() {
      copyBtn.classList.add('copied');
      setTimeout(function() { copyBtn.classList.remove('copied'); }, 2000);
    });
  }
  if (copyBtn) copyBtn.addEventListener('click', function(e) { e.stopPropagation(); doCopy(); });
  block.addEventListener('click', doCopy);
});

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
      secondary.textContent = 'Download for Mac/Linux';
      secondary.href = 'https://github.com/pretendhome/missioncanvas.ai/releases/latest/download/MissionCanvas.dmg';
    } else {
      primary.textContent = 'Download for Mac/Linux';
      primary.href = isMac
        ? 'https://github.com/pretendhome/missioncanvas.ai/releases/latest/download/MissionCanvas.dmg'
        : 'https://github.com/pretendhome/missioncanvas.ai/releases/latest/download/MissionCanvas.AppImage';
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

// ── Hero product demo animation ──────────────────────────────────
(function missionCanvasHeroDemo() {
  const query =
    'Draft a response to the Acme contract dispute using our terms from the Henderson file';
  const answer =
    'Based on the indemnification clause in §4.2 of the Henderson MSA and the three prior communications regarding delivery timelines, the recommended response addresses both the liability cap and the performance remedy...';

  const cycleMs = 18000;
  const timers = [];
  const content = document.getElementById('mcDemoContent');
  const input = document.getElementById('mcDemoInput');
  const placeholder = document.getElementById('mcDemoPlaceholder');
  const queryEl = document.getElementById('mcDemoQuery');
  const responseArea = document.getElementById('mcResponseArea');
  const responseText = document.getElementById('mcResponseText');
  const sources = document.getElementById('mcSources');
  const proof = document.getElementById('mcProof');
  const chips = [
    document.getElementById('mcChipOne'),
    document.getElementById('mcChipTwo'),
    document.getElementById('mcChipThree'),
  ].filter(Boolean);

  if (!content || !input || !queryEl || !responseText) return;

  function at(delay, fn) {
    timers.push(window.setTimeout(fn, delay));
  }

  function clearTimers() {
    while (timers.length) {
      window.clearTimeout(timers.pop());
    }
  }

  function reset() {
    content.classList.remove('mc-demo-resetting');
    content.style.opacity = '1';
    input.classList.remove('typing');
    responseArea?.classList.remove('streaming');
    if (placeholder) placeholder.style.display = '';
    queryEl.textContent = '';
    responseText.textContent = '';
    chips.forEach((chip) => chip.classList.remove('visible'));
    sources?.classList.remove('visible');
    proof?.classList.remove('visible');
  }

  function typeQuery() {
    input.classList.add('typing');
    if (placeholder) placeholder.style.display = 'none';
    queryEl.textContent = '';

    const stepMs = 4000 / query.length;
    [...query].forEach((char, index) => {
      at(index * stepMs, () => {
        queryEl.textContent += char;
      });
    });

    at(4000, () => input.classList.remove('typing'));
  }

  function streamAnswer() {
    responseArea?.classList.add('streaming');
    responseText.textContent = '';

    const tokens = answer.split(/(\s+)/);
    const wordMs = 1000 / 15;
    let wordIndex = 0;

    tokens.forEach((token) => {
      const delay = wordIndex * wordMs;
      at(delay, () => {
        responseText.textContent += token;
      });
      if (!/^\s+$/.test(token)) wordIndex += 1;
    });

    at(Math.min(5000, wordIndex * wordMs + 250), () => {
      responseArea?.classList.remove('streaming');
    });
  }

  function showCompleteState() {
    if (placeholder) placeholder.style.display = 'none';
    queryEl.textContent = query;
    responseText.textContent = answer;
    chips.forEach((chip) => chip.classList.add('visible'));
    sources?.classList.add('visible');
    proof?.classList.add('visible');
  }

  function play() {
    clearTimers();
    reset();

    typeQuery();
    chips.forEach((chip, index) => {
      at(4000 + index * 300, () => chip.classList.add('visible'));
    });
    at(6000, () => sources?.classList.add('visible'));
    at(9000, streamAnswer);
    at(14000, () => proof?.classList.add('visible'));
    at(17500, () => content.classList.add('mc-demo-resetting'));
    at(cycleMs, play);
  }

  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    showCompleteState();
    return;
  }

  at(250, play);
})();
