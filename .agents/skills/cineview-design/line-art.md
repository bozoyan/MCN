# Line art and supporting elements

Line art and small marks make a page feel drawn rather than assembled, and they cost little. A
single motif that returns across the page (a shape tied to the product: a lens, a leaf, a cup, a
cursor, a dial) tends to tie scenes together better than a new ornament in each.

Things that usually help decoration sit well:
- Under the content (`position: absolute; z-index: 0`), with the content above it.
- Lighter than the text: a stroke in `var(--line)` or a mix like
  `color-mix(in srgb, var(--ground), var(--ink) 18%)`, 1.5-2 px.
- Drawn in a viewBox with the scene's aspect and `preserveAspectRatio="xMidYMid meet"`, so
  nothing is cut off at other screen shapes; shapes placed in the empty areas.
- Clear of a fixed top bar, if the page has one.
- Round caps and joins (`stroke-linecap: round; stroke-linejoin: round`) so drawn shapes close
  without a seam.
- On phones, hidden where it would sit under text.

## A1 A sketch drawn behind a section

Suits: a section that would otherwise be plain cards (a discussion, a method, a list). `on="clock"`
draws it when the scene becomes current (a sketch the size of its scene).

```html
<cv-scene>
  <section class="method">
    <cv-animate class="sketch" on="clock" fx="draw" target=".sketch-svg *" duration="2400" aria-hidden="true">
      <svg class="sketch-svg" viewBox="0 0 1920 900" preserveAspectRatio="xMidYMid meet">
        <rect x="1180" y="104" width="230" height="124" rx="12"/>
        <path d="M1204 140 H1350 M1204 166 H1316"/>
        <path d="M1410 166 H1480"/>
        <rect x="1480" y="104" width="230" height="124" rx="12"/>
        <path d="M1502 210 L1562 162 L1608 194 L1646 168 L1690 210"/>
        <path d="M60 860 C 300 800, 520 890, 780 840 S 1180 800, 1460 850"/>
      </svg>
    </cv-animate>
    <div class="content">...</div>
  </section>
</cv-scene>
```

```css
.method { position: relative; overflow: clip; }
.sketch { position: absolute; inset: 0; z-index: 0; pointer-events: none; }
.sketch-svg { width: 100%; height: 100%; fill: none; stroke-width: 1.6;
              stroke: var(--line);
              stroke-linecap: round; stroke-linejoin: round; }
.content { position: relative; z-index: 1; }
```

## A2 One object, drawn once, then turning

Suits a brand with a round or iconic object (a reel, a record, a lens, a clock face, a gear). It
can sit on the boundary between two sections so half shows in each. Drawn once (outline first,
then the fills), then a slow turn while it is on screen.

- One SVG: the outline shapes in one `<g>` (`pathLength="1"` on each), the fills in another.
- Drawing once in CSS: strokes from `stroke-dashoffset: 1` to 0 over about 1.6 s, then the fills
  fade in.
- Turning: `rotate` on a wrapper (about 20 s a turn), with `animation-play-state` paused unless an
  IntersectionObserver marks it in view; still under reduced motion.
- Or entirely in Cineview: `fx="draw"` plus `loop="spin"` and `loop-duration="20000"` on the same
  element (the loop starts after the drawing ends and runs only on screen).

## A3 A dial with a moving needle

Suits: weight, volume, speed, progress (as decoration, not as a readout). A ring of 60 ticks (every
fifth longer), an inner ring, a needle; the tick ring turns once a minute, the needle swings
-50deg to 50deg over 8 s. Each moving part is its own small SVG (a composited transform), not a
moving group inside one large SVG.

## A4 Connectors that show "this follows that"

Suits: timelines and flows (L10, L11, L18). From the end of one item to the start of the next: a
vertical line with a rounded elbow (`border-left` + `border-bottom` + `border-bottom-left-radius`)
and a small arrowhead; a lit copy wipes in from the top when the next item starts
(`fx="wipe(top)" after="previous"`).

## A5 Small marks that help reading

- Step numbers in outlined circles, filled as the step is reached (L18).
- Tags as outlined pills (14u, 1.2u border).
- Edge print on a film strip, frame numbers, a code card's coloured keyword.
- A faint grain or paper texture on dark acts only (static, not animated).
