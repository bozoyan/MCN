# Images

Pick the treatment from what the picture has to say, then the layout from `layouts.md`.

| When the picture is meant to | A treatment that fits | Recipe |
|---|---|---|
| arrive with the sentence about it | `wipe` from the side of its text | I1 |
| look like part of one set with other photos | `duotone` | I2 |
| come into focus as the reader reaches it | `focus` (time) or `focus(band)` (passage) | I3 |
| keep its place while it loads | `develop` with `data-cv-standin` | I3 |
| be looked at slowly, detail by detail | `push(from, to, focus)` | I4 |
| show a plan or a flow | storyboard thumbnails | I5 |
| be one of several related items | cards (`cv-stack` or a row) | I6 |

## Prepare pictures

- Serve each at about 2x its displayed CSS width (a 520u panel at 1920 is ~1040 px wide); WebP
  or JPEG at quality 70-80.
- Same aspect ratio for pictures that share a layout; crop to the subject.
- For blur effects on large pictures, a stand-in 16-32 px wide (`data-cv-blurred` for `focus`,
  `data-cv-standin` for `develop`).
- `duotone` reads each image's pixels, so the images have to be same-origin or CORS-enabled.

## I1 Picture wiped in beside its sentence (ordinary scroll)

```html
<cv-scene>
  <div class="pair">
    <cv-animate class="pair-copy" fx="rise(soft)" duration="700" exit="opacity:0; y:-24px" exit-duration="500" replay>
      <h3>Write the brief</h3><p>Say what the page must explain.</p>
    </cv-animate>
    <cv-animate class="pair-pic" fx="wipe(left), push(1.04, 1)" duration="1100" delay="120" replay>
      <img src="brief.jpg" alt="A one-page brief" width="1120" height="720">
    </cv-animate>
  </div>
</cv-scene>
```

Copy on the left, so the picture wipes in from the left edge (the side its sentence is on). Mirror
both for the next pair (L02).

## I2 One set, two inks (held zone)

```html
<cv-animate fx="duotone(var(--ink-dark), var(--ink-light))" at="20% 40%" ease="linear">
  <img src="a.jpg" alt=""><img src="b.jpg" alt=""><img src="c.jpg" alt="">
</cv-animate>
```

Named pairs: `blue`, `orange`, `terracotta`, `mono`; or any dark and light colour from the page's
palette. The print fades in over its window; stagger several with shifted `at` windows.

## I3 Into focus

- On time, as it enters: `<cv-animate fx="focus" duration="900">`.
- While it passes the reading line: `<cv-animate fx="focus(band)">` in an ordinary scroll
  section (sharp only in the middle of the passage); on text it leaves words blurred for most
  of the passage.
- Real loading: `<cv-animate fx="develop"><img src="big.jpg" data-cv-standin="tiny.jpg"></cv-animate>`.

## I4 Slow look (Ken Burns)

```html
<cv-animate fx="push(1.06, 1, 30% 40%)" duration="2400" ease="linear">
  <img src="hall.jpg" alt="The hall at dusk">
</cv-animate>
```

The third argument is the focus point (what stays still). Combine with a caption that enters late
(`after`), and only one push in view at a time.

## I5 Storyboard thumbnails

Three to six small frames (SVG line drawings or crops), arrows between, a caption under each.
Suits: a plan of scenes, a user journey, "how the page will go". Layout L11 or inside L19 cards.

```html
<div class="board">
  <figure><svg viewBox="0 0 80 60"><rect x="10" y="14" width="60" height="9" rx="4.5"/></svg><figcaption>Opening line</figcaption></figure>
  <span class="arrow"></span>
  <figure><svg viewBox="0 0 80 60"><rect x="6" y="12" width="20" height="30" rx="4"/><rect x="30" y="12" width="20" height="30" rx="4"/><rect x="54" y="12" width="20" height="30" rx="4"/></svg><figcaption>Three features</figcaption></figure>
  <span class="arrow"></span>
  <figure><svg viewBox="0 0 80 60"><rect x="20" y="20" width="40" height="14" rx="7"/></svg><figcaption>Get started</figcaption></figure>
</div>
```

```css
.board { display: flex; align-items: flex-start; gap: calc(6 * var(--u)); }
.board figure { flex: 1; margin: 0; display: grid; gap: calc(8 * var(--u)); }
.board svg { aspect-ratio: 4 / 3; padding: calc(6 * var(--u)); border-radius: calc(10 * var(--u));
             background: var(--surface);
             fill: color-mix(in srgb, var(--ground), var(--accent) 25%); stroke: var(--accent); stroke-width: 1.4; }
.board .arrow { width: calc(14 * var(--u)); height: calc(14 * var(--u)); margin-top: calc(34 * var(--u));
                border-top: 2px solid var(--accent); border-right: 2px solid var(--accent); rotate: 45deg; scale: .6; }
```

## I6 Picture cards

A thumbnail tile inside each card (`aspect-ratio` fixed, `object-fit: cover`), title and two lines
under it; cards in a `cv-stack` (L03) or a row (L04, L08).
