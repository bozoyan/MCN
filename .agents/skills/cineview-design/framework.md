# Framework quick reference (cineview 2, cv-* HTML)

Checked against `src` (types in `src/jsx.ts`, presets in `src/core/fx.ts`). Full conventions:
`docs/ai/declarative-design.md`. When this file and the source disagree, the source wins.

## Load

All three, in `<head>`, in this order:

```html
<!-- 1. the head snippet (dist/head.js): marks .cv-js when the browser supports the framework -->
<script>(function(s){if(s&&s('selector(:has(*))')&&s('width:1lh')&&s('color:color-mix(in srgb,red,red)'))document.documentElement.classList.add('cv-js')})(window.CSS&&CSS.supports);</script>
<!-- 2. the boot stylesheet: structure and first-screen states before the module runs -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/cineview@2/dist/cineview.css">
<!-- 3. the module -->
<script type="module" src="https://cdn.jsdelivr.net/npm/cineview@2/dist/cineview.js"></script>
```

To self-host, copy `node_modules/cineview/dist/` (after `npm install cineview`) and point both URLs at
it. With a bundler, `import 'cineview'` replaces the module script; keep 1 and 2 in `<head>`, and keep
code splitting on so the on-demand chunks stay separate.

Without 1 and 2 the page paints every animated element in its finished state, then jumps to its
start state when the module runs (a flash on every load). Browsers that fail the snippet's test get
the static, readable page. Under a Content-Security-Policy, allow the snippet by its hash (the first
line of `head.js`).

## Units used by every recipe

```css
:root {
  --u: calc(min(100vw, 177.78vh) / 1920);   /* 1 design px at 1920 wide, scaled to the screen */
  --m: calc(120 * var(--u));                 /* page margin */
}
```

Sizes in the recipes are `calc(N * var(--u))`. `design-width` on `<cv-stage>` caps the stage's
frame width and sets the framework's own unit `--cv-unit` (default 750, a phone): a scroll page
designed with `--u` can set `design-width="1920"`; a drag page designed for phones keeps 750.

## Elements

| Element | Role |
|---|---|
| `<cv-stage>` | The page. Holds the scenes; owns the input. |
| `<cv-scene>` | One scene: one point, one timeline. Direct child of the stage. |
| `<cv-animate>` | One element with effects on the scene's timeline. Wrap the content. |
| `<cv-stack>` | Cards that stack; its element children are the cards. |
| `<cv-video>` | A video whose time follows the scene (scrubs with scroll or drag). |
| `<cv-fixed>` | Content held still on screen while its scene passes (sticky inside the scene). |
| `<cv-pause>` | A pause/play toggle for time-played motion (WCAG 2.2.2). Scroll and drag keep working. |

### cv-stage

| Attribute | Values | Meaning |
|---|---|---|
| `input` | `scroll` (default), `drag` | Reader scrolls the page, or drags scene by scene. |
| `design-width` | px, e.g. `1920` | Width the authored px refer to. |
| `paused` | flag | Time-played motion waits (remove it to start). |
| `transition-duration` | ms | Drag: duration of one scene change. |
| `threshold` | `"slow fast speed"` e.g. `"0.32 0.15 1200"` | Drag: release ratios and fling speed (px/s). |
| `unit`, `scale` | `time`/`percent`, number | Drag: how finger travel maps to time. |
| `margin`, `first-scene-timeout`, `fallback` | | Entrance margin; first-screen wait; `fallback` turns off the browser's native scroll timelines and computes scroll motion in script (for testing; pages without native support use it already). |

### cv-scene

| Attribute | Values | Meaning |
|---|---|---|
| `zone` | flag | Held: the screen holds while scroll drives the scene's time (1 ms = 1 px). |
| `track` | `x` | Content in a row that moves sideways along the scene's time (a zone in scroll). |
| `stack` | flag | This scene stays while the next scene slides over it. |
| `covered` | `dim`, `recede` | How the stacked scene looks while covered. |
| `theme` | name | At eye level the stage gets `data-cv-theme="name"`; style your palette from it. |
| `preload` | flag or URL list | Wait for first-screen images/videos before starting. |
| `drag` | `off` | This scene is not draggable (drag input). |
| `threshold`, `unit`, `scale`, `sequence` | | Per-scene drag overrides; scene order. |

### cv-animate

| Attribute | Example | Meaning |
|---|---|---|
| `fx` | `rise(soft), wipe(left)` | Preset effects, comma separated (table below). |
| `from` / `to` | `from="opacity:0; y:40" to="opacity:1; y:0"` | Raw values: opacity, x, y, scale, scale-x/y, rotate, rotate-x/y, skew-x/y, blur, clip, custom properties (`--name`). `%` on x/y is of the element. |
| `exit` | `opacity:0; y:-16px` or a preset | What leaving looks like. |
| `exit-duration` | ms | Duration of the exit. |
| `duration` / `delay` | ms | Length and wait (in a zone: px of scroll). |
| `after` | `title`, `title -120`, `title +80` | Start when that element's entrance ends; minus overlaps, plus waits. Same scene. |
| `name` | `title` | The name `after` refers to. |
| `at` | `20% 60%`, `20%`, `auto 80%` | Place the window as a share of the scene's length; every value carries `%`. |
| `on` | `scene`, `enter`, `enter(partial)`, `eye`, `view(self)`, `view(#id)`, `page`, `clock`, `velocity`, `direction` | Progress source (see below). |
| `ease` | `linear`, `ease-in-out`, `cubic-bezier(...)` | Easing. |
| `split` | `lines`, `words` | Animate each line/word (real text stays, copies are aria-hidden). |
| `stagger` | ms | Delay between split pieces or targets. |
| `target` | `.lines *` | Apply the effect to matching descendants (e.g. strokes for `draw`). |
| `loop` | `float`, `sway`, `pulse`, `breathe`, `spin`, any fx preset (played there and back), raw lists `opacity: 1 .45 1`, `--name: 0 1 0` | A loop after the entrance (on screen only). Several, comma separated. |
| `loop-duration` | ms | Loop period. |
| `replay` | omitted, flag / `true`, `false` | Omitted keeps the source's rule; flag / `true` plays on return; `false` shows the end after one complete entrance. Each follower keeps its own window and replay setting. |
| `margin` | px | Visibility gate margin. |

How `cv-animate` wraps its content: the children stay in the light DOM, but they are slotted into
blocks in the host's shadow root (one block per progress source). So:
- Layout for the children (grid, flex, gap) goes on an inner element, not on the `cv-animate`
  itself: `<cv-animate fx="fade"><div class="row">...</div></cv-animate>` with `.row { display: flex }`.
  Size and position the host itself as usual (it is `display: block`).
- The motion (transform, opacity, filter) is applied to those blocks, not to the host: paint the
  thing that moves inside it (a rule is an inner `<span>` with the background), and set its
  origin with `::part(layer)`: `.rule::part(layer) { transform-origin: left center; }`. Blocks
  carry `part="layer"` plus their kind (`layer keyframes`, ...).
- A custom property animated with `from`/`to` (`--lit: 0` to `1`) is set on those inner blocks:
  the content inside reads it, the host and its `::before`/`::after` do not; whatever uses it
  works as a real element inside. A default declared on those inner elements overrides the
  inherited value, so a fallback (`opacity: var(--lit, 0)`) is the way to give one.

### cv-stack

`step` (px each covered card stays visible), `covered` (`dim`/`recede`), `duration` (ms per card),
`delay`, `after`, `name`, `at`, `ease`. In a zone the cards rise one after another along scene
time and settle on the deck; in ordinary scroll they stick `step` px apart (native sticky).

`--cv-veil` on the stack or an ancestor colors covered cards; its alpha is the strength at full
cover. Use HTML container cards (`article`, `div`); put images, video and SVG inside them. Direct
media/SVG cards report `invalid-attribute` and fall back to default darkening for the whole stack.
The color uses the card's `::after`; custom pseudo-elements and filters belong on an inner element.

### cv-video

Everything `cv-animate` takes, plus `src`, `poster`, `range="from to"` (seconds of the file to
map), `preload` (whole-file into the blob cache unless `none`), `playback-rate`. The `<video>` is in
its shadow root: style it with `cv-video::part(video) { object-fit: cover; }`.

### cv-pause

`<cv-pause>Pause motion</cv-pause>` or `<cv-pause for="stage-id">`. Style
`cv-pause[aria-pressed="true"]`.

## Progress sources (`on`)

| Source | Plays on | Use for |
|---|---|---|
| `scene` (default in a zone or drag) | the scene's time: scroll in a zone, finger in drag | demos the reader scrubs |
| `enter` (default in ordinary scroll) | a clock, once the element is fully in view | entrances in content-tall sections; not inside a zone |
| `enter(partial)` | a clock, as soon as any part is visible | large or partly visible content in ordinary scroll; not in zones, rows or drag |
| `eye` | a clock, when the element crosses 45% of the screen | tall elements, reading position; not inside a zone |
| `view(self)`, `view(#id)` | the element (or `#id` in the same scene) crossing the viewport | scroll-following motion outside zones |
| `page` | the whole document's scroll | a reading-progress bar |
| `clock` | real time from the scene becoming current | entrances of large or partly off-screen things |
| `velocity`, `direction` | scroll speed / direction signals | `skew`, direction-aware chrome |

Inside a zone, elements follow the scene's time (`scene`, the default there) or play on their own
clock (`on="clock"`, e.g. copy that simply appears when the zone becomes current); `enter`,
`enter(partial)` and `eye` are refused there with a `cv-error`. Clock entrances restart on scene
return unless `replay="false"` has already completed one entrance; they follow Stage pause.

View ranges (with `on="view(self)"` or `view(#id)`) go after an fx item, not in `at`:
`fx="keyframes(in) cover 10% cover 42%"`, `fx="fade entry"`. The names are `cover`, `contain`,
`entry`, `exit`, `entry-crossing` and `exit-crossing`, each with an optional percentage. `at` takes
shares of the scene's length only; a value without `%` is reported and the whole `at` is ignored.

## Presets (`fx`)

| Preset | Arguments | Does |
|---|---|---|
| `fade` | | opacity 0 to 1 (the only change) |
| `rise` | `soft` (20 px), `strong` (80), px, `%`, `line`; none = 40 px | fades in while coming up from below; `rise(line)` rises out of its own clip without fading (split lines, a clipped row) |
| `grow` | `soft`, `strong`, scale | fades in while scaling up from 0.9 |
| `focus` | `soft`, `strong`, px; `band`; none = 4.5 px | blur to sharp while opacity goes 0.34 to 1; `focus(band)`: sharp only in the middle of a view passage |
| `wipe` | `left` (default), `right`, `top`, `bottom`, `up`, `down`, `center` | clip edge travels across; `center` opens from the middle line outward |
| `push` | `in`, `out`, or `from, to, focus` | slow scale about a focus point (Ken Burns) |
| `reveal` | `side, blur` (e.g. `reveal(left, soft)`) | wipe + focus + push in one |
| `develop` | | pictures develop from a blurred stand-in as they load (`data-cv-standin`) |
| `duotone` | `blue`, `orange`, `terracotta`, `mono`, or `dark, light` colours | prints every picture inside in two inks (the print fades in over the window) |
| `draw` | | each stroke draws itself (sets `pathLength` 1; confine with `target`) |
| `count` | | a real number rolls up on digit wheels |
| `axis` | `wght 250 650`, `wdth 75 100` | variable-font axis over time |
| `drift` | `soft` (3.5%), `strong` (16%), `%`, px; none = 10% of the element's height, a bare number is px | parallax offset over a view passage |
| `skew` | `soft`, `strong`, deg; none = 4 deg | leans with scroll speed |
| `hue` | `to` or `from, to` angles | turns `--cv-hue` for `oklch(... calc(h + var(--cv-hue)))` |
| `invert` | | difference blend against what is behind |
| `unroll` | | a long vertical-writing strip unrolls across its window |
| `keyframes` | page `@keyframes` name | plays your own keyframes on the element's progress |
| `fade-in`, `slide-up`, `zoom-in`, `rotate-in`, `blur-in` | | 1.x presets with 1.x values |

`rise`, `grow` and `focus` already change opacity, so adding `fade` to them puts two effects on one
property (they multiply, and the fade comes out slower). Presets that own different properties
combine cleanly: `rise(soft), wipe(left)`.

The size words are `soft` and `strong`; leaving the argument out gives the middle value (`rise` is
`rise(40px)`), and writing `normal` is reported as an error.

Pictures for `focus` on large images: add `data-cv-blurred="tiny.jpg"` (a few-px-wide copy) so the
blur is a crossfade, not a live filter.

## Time rules

- A zone's length is where its last element ends (`delay` + `duration` after its `after`,
  plus its exit), in ms; 1 ms is 1 px of scroll. An element with `at` still counts its own
  `duration` (and exit) toward the length, and its window is then placed as that share of the
  total. Give every zone one anchor whose `duration` is the intended length; keep other
  `duration`s at or under it.
- `after` waits for the named element's entrance; names are per scene; an `after` chain stays on
  one kind of timeline (a clock chain and an input chain do not link).
- `delay` waits on the element's own gate; use it to order elements that have their own gates.
- In ordinary scroll an entrance plays when its gate opens (`enter`: fully in view); with `exit`
  it plays its exit when it leaves; with `replay` it plays again on return.
- A `loop` starts after its element's entrance has finished, and only while it is on screen.
- Reduced motion: time-played entrances become short fades and loops stop; scroll- and
  drag-following motion stays (it is the reader's own).

## State on the page (style from these)

- Stage: `data-cv-theme` (current scene's `theme`), `data-cv-direction` (scroll direction).
- Scene: `data-cv-current`, `data-cv-stuck` (held: a zone in its hold, a stacked scene while covered).
- Animate: `data-cv-phase` (`entering`, `entered`, `exiting`, `exited`).

## Events (all bubble)

`cv-ready`, `cv-enter`, `cv-leave`, `cv-progress` (detail: `kind`, `progress`), `cv-play`,
`cv-pause`, `cv-dragstart`, `cv-dragend`, `cv-dragcancel`, `cv-dragblocked`, `cv-error` (detail:
`code`, `message`; listen during development and fix every one).

## Script interface

- `stage.ready` (Promise), `stage.goTo(indexOrId, { animated })`.
- `scene.solution.total`: the zone's length in px (for probes and fallbacks).
- `el.timeline.subscribe(frame => ...)` returns an unsubscribe function; `frame.progress` 0..1,
  `frame.phase`; `el.timeline.frame` is the current frame. Draw Canvas/WebGL/SVG from it.
