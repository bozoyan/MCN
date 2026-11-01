# The 41 references, one line each

Names follow the Mocubix design lexicon (https://mocubix.renocrypt.com/lexicon/); the mapping to
Cineview is this project's. F = framework primitive, P = page implementation, X = not available.
Format: number name | kind | markup | layout | watch for. Which ones combine: `combinations.md`.
Full descriptions: `docs/ai/lexicon.md` in the Cineview repository.

01 Page progress | F | `on="page"` on a thin bar | top edge, full width | drag has no document progress
02 View progress | F | `on="view(self)"`, `view(#id)` | object changes while crossing viewport | pick subject + range
03 Pin & scrub | F | `<cv-scene zone>` + anchor `duration` | copy left, demo right, one screen | anchor sets length
04 Parallax | F | `drift(soft)` on separate layers | background layer behind text | keep text still
05 Horizontal section | F | `<cv-scene track="x">`, children in a row | lead block + panels, end margin | travel = real overflow
06 Stacking cards | F | `<cv-stack step="64" duration="500">` | deck right, copy left | step keeps titles visible
07 Velocity skew | F | `skew` (velocity source) | decorative strokes | leaning body text is hard to read
08 Timeline scope | F | `view(#id)` shared in one scene | caption follows its image | same scene only
09 Path drawing | F | `fx="draw" target="..."` | lines that mean a route/sequence | round caps, target only strokes
10 Word scrub | F | `split="words" stagger` | keyword next to its image | pair words and images by window
11 Curtain overlap | F | `<cv-scene stack covered="recede|dim">` then next scene | next section slides over | a covered scene that keeps changing competes with the one covering it
12 Depth of field | F | `fx="focus(band)"` (view) | images pass the middle sharp | needs a scrolling, not pinned, scene
13 Count | F | `fx="count"` on a real number | number + unit + label | the final value is what readers remember
14 Scroll snap | P | native scroller + CSS snap | local gallery | not Stage paging
15 Snap stop | P | `scroll-snap-stop` | steps that should not be skipped | content decision
16 Scroll markers | P | anchors, `aria-current` | chapter dots | focus order
17 Scroll buttons | P | `stage.goTo(i)` buttons | prev/next | disable at ends
18 Stuck state | F | style `[data-cv-stuck]` | restyle a held zone | zone scenes only
19 Snapped state | F | `[data-cv-current]` | highlight current scene | scene level
20 Direction | F | `[data-cv-direction]` | hide/show nav by direction | keep actions reachable
21 Infinite loop | X | none | none | Stage scenes are finite
22 Kinetic drag | P | local horizontal container | image strip | not Stage drag
23 Scrollspy | F | scene anchors + `aria-current` | contents list | in-scene headings are page work
24 Overscroll | P | `overscroll-behavior` | local panels | check drag edge handoff
25 Blur-up | F | `fx="develop"` + `data-cv-standin` | image keeps its box | only real loading
26 Ken Burns | F/P | `fx="push(1.06, 1, focus)"` | slow push on one image | full plan needs page focal points
27 Duotone | F | `fx="duotone(dark, light)"` | original vs printed side by side | real material, not an overlay
28 Progressive blur | P | layered blur + mask | text over image | no preset
29 Dithering | P | pre-processed asset | limited tone | runtime reads need CORS
30 Clip reveal | F | `fx="wipe(left|right|top|bottom)"`, `reveal` | new picture over the old | the direction reads as meaning
31 Comparison slider | P | native range + clip | before/after | keyboard, no drag paging
32 Split text | F | `split="lines" fx="rise(soft)" stagger="120"` | short passage | recheck fonts and line breaks
33 Variable font | F | `fx="axis(wght 250 650)"` | large words | needs a font with the axis (Inter, Fraunces, Recursive, Noto Serif SC)
34 Text mask | P | CSS background-clip text | large type over image | keep a solid fallback
35 Vertical writing | P | `writing-mode`, `fx="unroll"` | scroll strip | punctuation rules
36 Marquee | P | measured CSS/WAAPI loop | thin text band | one focusable copy, pause
37 Token interpolation | F | `fx="hue(0deg,180deg)"` -> CSS var | palette shift | check contrast mid-way
38 Scoped rotation | P | scope vars to a container | local color change | not page-wide
39 Gamut arc | P | `color-mix(in oklch)` | color transition | inspect mid colors
40 Difference invert | F | `fx="invert"` | text over mixed backgrounds | mid gray is unreadable
41 Threshold flip | F | `<cv-scene theme="name">` -> `[data-cv-theme]` | one deliberate palette change (a dark act) | page CSS transitions the tokens (~0.7 s)
