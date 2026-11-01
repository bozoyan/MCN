# Colour

Palettes for different directions are in `styles.md`. This file covers how colour can move with
a page, and how to keep text readable.

## C1 Tokens that everything derives from

Deriving surfaces from a few tokens means one change of `--ground` moves the whole page together:

```css
:root {
  --ground: #ffffff; --ink: #0f172a; --ink-soft: #475569; --accent: #2563eb; --on-accent: #fff;
  --surface: color-mix(in srgb, var(--ground) 92%, var(--ink));
  --line: color-mix(in srgb, var(--ground) 80%, var(--ink));
}
body { background: var(--ground); color: var(--ink); }
```

To animate a token (for example `--ground` between scenes), register it so the browser can
interpolate it:

```css
@property --ground { syntax: "<color>"; inherits: true; initial-value: #ffffff; }
:root.tokens-live { transition: --ground .7s ease, --ink .7s ease; }
```

Turning the transition on only after `stage.ready` keeps a reload inside a dark scene from fading
in from the light palette:

```js
document.querySelector('cv-stage').ready.then(() =>
  requestAnimationFrame(() => document.documentElement.classList.add('tokens-live')));
```

## C2 A palette per scene (threshold flip)

`<cv-scene theme="night">` sets `data-cv-theme="night"` on the stage while that scene is at eye
level; page CSS maps it to tokens:

```css
:root:has(cv-stage[data-cv-theme="night"]) { --ground: #0b0e1a; --ink: #eef1ff; --ink-soft: #a9b0cc; --accent: #ff5a7a; }
```

Used for one deliberate change (lights down for a finale), for alternating chapters, or for a
different palette on every scene; the more often it changes, the more each change has to mean.

## C3 A ground that follows the scroll

Instead of steps, the ground can glide continuously with the scroll position: a few colour stops,
mixed for the current position, written only when the colour changes.

```js
const STOPS = [[0, [255, 255, 255]], [0.5, [238, 244, 255]], [1, [255, 255, 255]]]; // any colours
let last = '';
function paint() {
  const f = Math.min(1, Math.max(0, (scrollY + innerHeight / 2) / document.documentElement.scrollHeight));
  let i = 1; while (i < STOPS.length - 1 && STOPS[i][0] < f) i++;
  const [a, ca] = STOPS[i - 1], [b, cb] = STOPS[i], t = (f - a) / (b - a);
  const css = `rgb(${ca.map((v, k) => Math.round(v + (cb[k] - v) * t)).join(' ')})`;
  if (css !== last) document.documentElement.style.setProperty('--ground', (last = css));
}
addEventListener('scroll', () => requestAnimationFrame(paint), { passive: true }); paint();
```

Close stops read as one atmosphere that shifts; far-apart stops read as distinct chapters.

## C4 Hue that turns (token interpolation)

`fx="hue(0deg, 120deg)"` turns `--cv-hue` over an element's progress; colours written as
`oklch(.6 .15 calc(250deg + var(--cv-hue)))` follow it. Scoping it to one figure (reference 38)
keeps the rest of the page stable.

## C5 Readability

- Body text: 4.5:1 against what is behind it is the usual accessibility reference (WCAG AA); large
  titles 3:1.
- Text over photos or video: a gradient, a progressive blur (reference 28) or a panel behind the
  text keeps it readable as the picture changes.
- Small labels set in a lighter colour rather than with `opacity` keep their contrast predictable.
- A button label on its fill, in every palette the page uses.
