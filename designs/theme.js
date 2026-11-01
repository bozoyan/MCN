/* =========================================================================
   Reveric Design Mockups — Theme switcher (shared by desktop + mobile)

   Mirrors Flutter AppTheme × AppThemeMode:
     palette: reveric | classic | ivory
     mode:    light | dark | system

   Writes <html data-palette data-theme> (data-theme = resolved brightness)
   and persists to localStorage. Load in <head> before stylesheets render so
   the first paint uses the saved theme.

   API (window.RevericTheme):
     get() → { palette, mode, brightness }
     set({ palette?, mode? })
     subscribe(fn) → unsubscribe
     useTheme() → React hook returning get() and re-rendering on change
     PALETTES / MODES → metadata for settings pickers

   The floating switcher can be hidden with ?themebar=0.

   URL overrides (?palette=&mode=) win over localStorage and are not
   persisted, so a page can be embedded or screenshotted at a fixed theme.
   ========================================================================= */
(function () {
  var STORAGE_KEY = "reveric-design-theme";

  /* Preview swatches follow each palette's light preset, like the Flutter
     appearance section's _buildThemePreview. */
  var PALETTES = [
    { key: "reveric", label: "Reveric", desc: "玉白底色，墨玉落笔",
      preview: { canvas: "#F2F6F4", surface: "#FFFFFF", accent: "#1C2623", text: "#141A18" } },
    { key: "classic", label: "经典", desc: "极简、永恒、高对比度",
      preview: { canvas: "#FFFFFF", surface: "#FAFAFA", accent: "#000000", text: "#000000" } },
    { key: "ivory", label: "象牙", desc: "温柔而雅致，如陈年纸与乳脂",
      preview: { canvas: "#F8F8F0", surface: "#FAFAF3", accent: "#A2AF9B", text: "#2E3026" } },
  ];
  var MODES = [
    { key: "light", label: "浅色" },
    { key: "dark", label: "深色" },
    { key: "system", label: "跟随系统" },
  ];

  var media = window.matchMedia ? window.matchMedia("(prefers-color-scheme: dark)") : null;
  var listeners = [];
  var params = new URLSearchParams(location.search);
  var forced = {
    palette: params.get("palette"),
    mode: params.get("mode"),
  };
  var state = load();

  function isKey(list, key) {
    for (var i = 0; i < list.length; i++) if (list[i].key === key) return true;
    return false;
  }

  function load() {
    var saved = {};
    try { saved = JSON.parse(localStorage.getItem(STORAGE_KEY)) || {}; } catch (e) {}
    if (isKey(PALETTES, forced.palette)) saved.palette = forced.palette;
    if (isKey(MODES, forced.mode)) saved.mode = forced.mode;
    return {
      palette: isKey(PALETTES, saved.palette) ? saved.palette : "reveric",
      mode: isKey(MODES, saved.mode) ? saved.mode : "light",
    };
  }

  function brightness() {
    if (state.mode === "system") return media && media.matches ? "dark" : "light";
    return state.mode;
  }

  function get() {
    return { palette: state.palette, mode: state.mode, brightness: brightness() };
  }

  function apply() {
    var root = document.documentElement;
    root.setAttribute("data-palette", state.palette);
    root.setAttribute("data-theme", brightness());
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) {
      var canvas = getComputedStyle(root).getPropertyValue("--canvas").trim();
      if (canvas) meta.setAttribute("content", canvas);
    }
  }

  function notify() {
    apply();
    var snapshot = get();
    listeners.slice().forEach(function (fn) { fn(snapshot); });
  }

  function set(next) {
    if (next.palette && isKey(PALETTES, next.palette)) state.palette = next.palette;
    if (next.mode && isKey(MODES, next.mode)) state.mode = next.mode;
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (e) {}
    notify();
  }

  function subscribe(fn) {
    listeners.push(fn);
    return function () {
      listeners = listeners.filter(function (l) { return l !== fn; });
    };
  }

  function useTheme() {
    var React = window.React;
    var pair = React.useState(get());
    React.useEffect(function () { return subscribe(pair[1]); }, []);
    return pair[0];
  }

  if (media) {
    var onSystemChange = function () { if (state.mode === "system") notify(); };
    if (media.addEventListener) media.addEventListener("change", onSystemChange);
    else if (media.addListener) media.addListener(onSystemChange);
  }

  // Cross-tab / cross-iframe sync (preview cards embed pages in iframes).
  window.addEventListener("storage", function (e) {
    if (e.key !== STORAGE_KEY || params.has("palette")) return;
    state = load();
    notify();
  });

  apply();

  /* ---- Floating switcher ------------------------------------------------ */
  function mountBar() {
    if (/[?&]themebar=0\b/.test(location.search)) return;
    if (window.self !== window.top) return;

    var style = document.createElement("style");
    style.textContent = [
      ".rv-themebar{position:fixed;left:16px;bottom:16px;z-index:2147483000;display:flex;align-items:center;gap:6px;",
      "padding:5px;border-radius:999px;background:var(--surface);border:1px solid var(--border);",
      "box-shadow:0 6px 24px color-mix(in srgb,var(--shadow-base) 16%,transparent);",
      "font:500 12px/1 system-ui,-apple-system,'PingFang SC',sans-serif;color:var(--text-secondary);}",
      ".rv-themebar button{all:unset;cursor:pointer;display:inline-flex;align-items:center;gap:5px;height:26px;",
      "padding:0 10px;border-radius:999px;white-space:nowrap;}",
      ".rv-themebar button:hover{background:var(--hover);}",
      ".rv-themebar button.is-on{background:var(--selected);color:var(--text-primary);font-weight:600;}",
      ".rv-themebar__dot{width:10px;height:10px;border-radius:50%;box-shadow:inset 0 0 0 1px color-mix(in srgb,var(--text-primary) 20%,transparent);}",
      ".rv-themebar__sep{width:1px;height:16px;background:var(--border);}",
      ".rv-themebar__toggle{width:26px;padding:0!important;justify-content:center;}",
      ".rv-themebar__group{display:flex;align-items:center;gap:2px;flex-wrap:wrap;}",
      ".rv-themebar.is-collapsed .rv-themebar__group{display:none;}",
      "@media print{.rv-themebar{display:none;}}",
    ].join("");
    document.head.appendChild(style);

    var bar = document.createElement("div");
    bar.className = "rv-themebar" + (window.innerWidth < 720 ? " is-collapsed" : "");
    bar.setAttribute("role", "toolbar");
    bar.setAttribute("aria-label", "主题切换");

    var toggle = document.createElement("button");
    toggle.className = "rv-themebar__toggle";
    toggle.title = "主题";
    toggle.textContent = "◐";
    toggle.onclick = function () { bar.classList.toggle("is-collapsed"); };
    bar.appendChild(toggle);

    var group = document.createElement("div");
    group.className = "rv-themebar__group";
    bar.appendChild(group);

    var buttons = [];
    PALETTES.forEach(function (p) {
      var b = document.createElement("button");
      b.innerHTML = '<span class="rv-themebar__dot" style="background:' + p.preview.accent + '"></span>' + p.label;
      b.onclick = function () { set({ palette: p.key }); };
      b._match = function (s) { return s.palette === p.key; };
      buttons.push(b);
      group.appendChild(b);
    });
    var sep = document.createElement("span");
    sep.className = "rv-themebar__sep";
    group.appendChild(sep);
    MODES.forEach(function (m) {
      var b = document.createElement("button");
      b.textContent = m.label;
      b.onclick = function () { set({ mode: m.key }); };
      b._match = function (s) { return s.mode === m.key; };
      buttons.push(b);
      group.appendChild(b);
    });

    function sync(s) {
      buttons.forEach(function (b) { b.classList.toggle("is-on", b._match(s)); });
    }
    sync(get());
    subscribe(sync);
    document.body.appendChild(bar);
  }

  if (document.body) mountBar();
  else document.addEventListener("DOMContentLoaded", mountBar);

  window.RevericTheme = {
    PALETTES: PALETTES,
    MODES: MODES,
    get: get,
    set: set,
    subscribe: subscribe,
    useTheme: useTheme,
  };
})();
