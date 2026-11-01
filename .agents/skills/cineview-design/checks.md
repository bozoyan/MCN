# Two languages, and checking the page

## K1 A language switch

Every text node gets a key; one dictionary per language; a classic script at the end of `<body>`
applies the language before the Cineview module runs, so the first frame is already right.

```html
<button data-set-lang="en">EN</button><button data-set-lang="zh">中文</button>
<h2 class="title"><span class="nb" data-i18n="film.t1">The night's photos,</span> <span class="nb" data-i18n="film.t2">cut into a film</span></h2>
<img data-i18n-alt="diary.alt" alt="A diary page with three photos">
<script src="lang.js"></script>          <!-- classic script, before the module boots -->
<!-- in <head>: the head snippet, cineview.css and the module (framework.md, Load) -->
```

```js
const TEXT = { en: { 'film.t1': "The night's photos,", 'film.t2': 'cut into a film', 'diary.alt': 'A diary page with three photos' },
               zh: { 'film.t1': '当晚的照片，', 'film.t2': '自动剪成短片', 'diary.alt': '一页日记，夹着三张照片' } };
const KEY = 'site-lang';
function pick() {
  const asked = new URLSearchParams(location.search).get('lang');
  if (asked in TEXT) return asked;
  try { const kept = localStorage.getItem(KEY); if (kept in TEXT) return kept; } catch {}
  return /^zh\b/i.test(navigator.language || '') ? 'zh' : 'en';
}
function setLanguage(lang) {
  const t = TEXT[lang];
  document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
  for (const el of document.querySelectorAll('[data-i18n]')) el.textContent = t[el.dataset.i18n];
  for (const el of document.querySelectorAll('[data-i18n-alt]')) el.alt = t[el.dataset.i18nAlt];
  for (const el of document.querySelectorAll('[data-i18n-label]')) el.setAttribute('aria-label', t[el.dataset.i18nLabel]);
  document.title = t['page.title'];
  document.querySelector('meta[name="description"]')?.setAttribute('content', t['page.desc']);
  for (const b of document.querySelectorAll('[data-set-lang]')) b.setAttribute('aria-pressed', String(b.dataset.setLang === lang));
  try { localStorage.setItem(KEY, lang); } catch {}
}
setLanguage(pick());
for (const b of document.querySelectorAll('[data-set-lang]')) b.addEventListener('click', () => {
  const url = new URL(location.href);
  if (url.searchParams.has('lang')) { url.searchParams.set('lang', b.dataset.setLang); history.replaceState(history.state, '', url); }
  setLanguage(b.dataset.setLang);
});
```

- Write each language for its readers; check every title's break in both.
- Elements with `split` measure their lines from the text they had when the page started: after a
  language change, reload the page (or keep `split` off titles whose text changes).
- An embedded page (a drag demo in an iframe) needs the language too: reload it after a change.

## K3 Reload in the middle of the page without flashing the opening

A reload starts at the top, then the browser (or the page) scrolls back: for a frame or two the
reader sees the opening and its palette. Hide the page from the first frame, restore the place and
the palette, then show it.

In `<head>`, before any stylesheet:

```html
<script>
  (function () {
    try {
      if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
      var nav = performance.getEntriesByType('navigation')[0];
      var saved = JSON.parse(sessionStorage.getItem('place') || 'null');
      var root = document.documentElement;
      if (nav && (nav.type === 'reload' || nav.type === 'back_forward') && saved && saved.id) {
        root.classList.add('restoring');
        if (saved.theme) root.setAttribute('data-boot-theme', saved.theme);
      } else if (location.hash) {
        // a link straight to a scene (#film): start in that scene's palette too
        var THEMES = { film: 'night', closing: 'night' };   // scene id -> its theme, from the page
        var theme = THEMES[location.hash.slice(1)];
        if (theme) root.setAttribute('data-boot-theme', theme);
      }
    } catch (e) {}
  })();
</script>
```

```css
:root.restoring body > * { opacity: 0; }
:root:not(.restoring) body > * { transition: opacity .2s; }
/* the saved act's palette, until the stage sets data-cv-theme itself */
:root[data-boot-theme="night"] { --ground: #15100d; --ink: #f3e6d6; /* ...the night tokens... */ }
```

In the page script, wait for the custom element to be defined before reading `stage.ready`. Install
the visibility timeout first so a failed module still leaves the page readable:

```js
const stage = document.querySelector('cv-stage'), root = document.documentElement;
const save = () => {
  if (root.classList.contains('restoring')) return;
  const s = stage.querySelector(':scope > cv-scene[data-cv-current]');
  if (s) try { sessionStorage.setItem('place', JSON.stringify({ id: s.id, offset: Math.round(scrollY - s.offsetTop), theme: stage.getAttribute('data-cv-theme') })); } catch {}
};
let queued = 0;
addEventListener('scroll', () => { if (!queued) queued = requestAnimationFrame(() => { queued = 0; save(); }); }, { passive: true });
addEventListener('pagehide', save);
if (root.classList.contains('restoring')) {
  const show = () => { root.classList.remove('restoring'); root.removeAttribute('data-boot-theme'); };
  setTimeout(show, 2500);                                       // a cap, even if the module never runs
  let saved = null;
  try { saved = JSON.parse(sessionStorage.getItem('place') || 'null'); } catch {}
  customElements.whenDefined('cv-stage').then(() => stage.ready).then(() => {
    const s = saved && document.getElementById(saved.id);
    if (s) scrollTo(0, s.offsetTop + saved.offset);
    requestAnimationFrame(() => requestAnimationFrame(show));   // let the stage read the new place
  });
}
if (!root.classList.contains('restoring') && root.hasAttribute('data-boot-theme')) {
  // opened from a #scene link: hand the palette over to the stage once it has set data-cv-theme
  customElements.whenDefined('cv-stage').then(() => stage.ready).then(() => requestAnimationFrame(() => requestAnimationFrame(() => root.removeAttribute('data-boot-theme'))));
}
```

Offsets use `offsetTop` (the scene's place in the document), not its box, which a held zone pins.
A link to a scene (`#film`) is a fresh navigation, not a reload: the `THEMES` map gives it the
scene's palette from the first frame; the page script removes `data-boot-theme` once
`stage.ready` has set `data-cv-theme` (as in the reload branch). Check it: open the page with each
`#id` you link to.

Optional, so the first frame is already in place: give each zone its height in CSS before the
module runs, the same height the stage will set (`#film { height: calc(3000px + 100svh) }` for a
zone of 3000), and `cv-stage, cv-scene { display: block }`. The document is then full height at
the first paint and the browser can restore the scroll itself. Keep the number in step with the
zone's anchor `duration`.

## K2 Probes for "Check before handing over"

Playwright, Chrome (`chromium.launch({ channel: 'chrome' })` if Playwright's own browser is
missing). Each probe under about 90 seconds.

```js
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
await page.addInitScript(() => { window.__cv = []; addEventListener('cv-error', (e) => window.__cv.push(e.detail.code)); });
await page.goto(url, { waitUntil: 'domcontentloaded' });         // not 'load': videos preload whole files
await page.evaluate(async () => { await customElements.whenDefined('cv-stage'); await document.querySelector('cv-stage').ready; });
```

- First load: sample `requestAnimationFrame` frames from the start and check that no animated
  element is drawn finished and then jumps back (missing head snippet or `cineview.css`).
- Rest points: for each scene, `scrollTo` its top (a zone: `top + f * scene.solution.total` for
  f = 0, 0.5, 1), wait ~1.5 s, screenshot; check `document.documentElement.scrollWidth ===
  innerWidth` and that no text box crosses the screen edge or the fixed bar.
- Stop and reverse in a zone: scroll +600 px, read the state, wait 700 ms, read again (unchanged),
  scroll -600 px (back to the first state). For a video read `currentTime` from
  `cvVideo.shadowRoot.querySelector('video')`.
- Frame intervals: in the page, record `requestAnimationFrame` deltas while scrolling 60 px every
  30 ms through the scene; report P50/P95/max; P95 under 25 ms at 1920x1080.
- Reload: scroll into a scene, reload, and check the scroll position and palette from the first
  sampled frame (with K3 the page is hidden until both are right).
- Contrast: compute text colour against the pixels behind it (hide the text, screenshot its box).
