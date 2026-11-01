# How the 41 references behave together

Numbers are the 41 references in `references.md`. These are observations about how references
behave next to each other in each mode: pairings that tend to read well, and pairings that tend to
work against each other, with the reason. They are not limits; a pairing listed as weaker can be
exactly what a design wants, and the reason says what to watch.

Two things explain most of them:
1. A property of one element follows one progress source (how the framework works). Two
   references that drive the same property of the same element (two scales, two clips, two
   opacities) multiply or fight; on different elements they combine freely.
2. Attention. A reader follows one change more easily than two happening in the same place at
   once; separate windows (`at`) or separate scenes give each its moment.

## Ordinary scroll (content-tall sections, entrances on visibility)

References that carry a scene well here: 32 split text, 30 clip reveal, 09 path drawing, 13 count, 12 depth of field,
02 view progress, 27 duotone (on entry).

Pairings seen working:
- Opening title: 32 (`rise(line)` per row) + 09 (a rule drawn out from each row) + one slow
  decoration (a reel or dial turning on `loop`). Layout L06 or L07.
- Image and its sentence: 30 (`wipe` from the side of its text) + 32 (the sentence rises).
  Layout L01/L02 alternating.
- Proof number: 13 (`count`) + a caption that fades after it (`after`). Layout L09.
- Gallery passing the reading line: 12 (`focus(band)`) on each image + 04 (`drift(soft)`) on the
  captions only. Layout L13.
- Section line that leads in: two rows on `view(self)`, entering from the sides with `keyframes`
  on `cover` ranges (L07 two-row staggered).
- Faint line art behind a section: 09 (`draw`, on clock) under the content. Any layout.

Pairings that tend to work against each other:
- 07 skew on body text: lean while reading is hard to read; use it on thin decorative strokes only.
- 12 `focus(band)` on text: blurred text is unreadable for most of the passage.
- 32 split and 10 word scrub on the same passage: two treatments of the same words.
- 04 parallax on the subject of a sentence: the image drifts away from the words that point at it.

## Held zone (`<cv-scene zone>`: the screen holds while scroll drives time)

References that carry a scene well here: 03 pin and scrub (the frame), 08 timeline scope, 10 word scrub, 30 reveal, 27 duotone,
26 Ken Burns, a scroll-driven `<cv-video>`, your own drawing (timeline.subscribe).

Pairings seen working:
- Product demo: 03 + 08 (the interface's parts and their labels share windows) + 30 (each part
  wiped in). Layout L01. Anchor: a playhead or the last part.
- Timeline explainer: 03 + parts chained with `after` + a Gantt row per part whose fill copies
  the part's `duration`/`after` (L10). Shows sequencing itself.
- Film strip: 03 + 12 `focus` per frame + 27 `duotone` + the middle frame opening into a
  scroll-driven video (L12). One material, several treatments, in turn.
- Word and picture: 10 (`split="words"`) with each keyword sharing its window with its image
  (`at`). Layout L01 with the words left.
- Slow look at one picture: 26 `push(1.06, 1, focus)` + 32 caption entering late. Layout L05.
- Assemble a model: 03 + timeline.subscribe driving WebGL/Canvas; copy and a code card left.
  Layout L01, canvas under the whole scene.

Pairings that tend to work against each other:
- Two zones back to back with nothing between: the reader feels stuck. Put an ordinary section
  or a stacked/track scene between held scenes.
- A zone longer than its content needs: every 1000 ms is a screen of scrolling with no change.
- 04 parallax inside a zone on the element the zone scrubs: two sources on one transform.
- 12 `focus(band)` inside a zone: the band needs content passing the screen's middle, and a held
  scene does not pass.
- 36 marquee in a zone: its loop has nothing to do with the scrubbed time.

## Horizontal track (`<cv-scene track="x">`)

References that carry a scene well here: 05 horizontal section. Supports: 30 reveal per panel (on the panel's own entry),
19 snapped state to mark the panel at the centre, 13 count inside a panel.

Pairings seen working:
- Catalogue of kinds: 05 with a lead block, then panels that each hold a small storyboard,
  an approach line, tags (L19). Coming right after a stacked scene, it slides over it (11).
- Timeline of a history: 05 with dated panels + 09 a line drawn along the row (L10 sideways).

Pairings that tend to work against each other:
- 14 scroll snap or 22 kinetic drag inside the track: two horizontal movements compete.
- Panels with very different heights: the row's vertical rhythm breaks; give panels one height
  from their content.

## Cover stack (`<cv-scene stack>` and `<cv-stack>`)

References that carry a scene well here: 06 stacking cards, 11 curtain overlap. Supports: 18 stuck state, a step legend that
lights per card (keyframes on the zone).

Pairings seen working:
- Process deck: a zone with `stack covered="recede"` holding `<cv-stack>`; each covered card
  shows its head row; a three-step legend beside it lights as each card lands; the next scene
  (often a track) slides over (L03).
- Chapter covers: consecutive scenes with `stack`, each covering the last with its title (11),
  no other motion; reads like turning pages.

Pairings that tend to work against each other:
- A step that cuts a card's text line: set `step` to the card's head-row height.
- A deck taller than the screen: count the cards' drawn height (step x (cards - 1) + last card).

## Drag (`<cv-stage input="drag">`, one scene per screen)

References that carry a scene well here: one strong composition per scene; 13 count, 09 draw, 30 reveal, 32 split, a
scrubbed `<cv-video>`, 41 dark theme. The finger scrubs every entrance; release commits.

Pairings seen working:
- Cinematic sequence: each scene a full-bleed picture + one line (32), the picture with 26 push,
  scene changes covering in black; 3 to 6 scenes.
- Phone demo inside a scroll page: the drag page in an iframe in a phone frame (L17), activated
  when its act is current; the copy appears when the reader reaches the last scene.

Pairings that tend to work against each other:
- Native scrollers, snap strips (14, 22) or long text inside a drag scene: the finger is the
  scene change.
- More than about six scenes: each is a full gesture.
- Small type: a phone frame on a desktop page shows a drag page at about 280 px wide.

## Clock (`on="clock"`: time from the scene becoming current)

Use for entrances that cannot wait for visibility: large decorations partly off screen, sketches
nearly as tall as their scene, a reel spinning after it is drawn. Pair with 09 (`draw`) and
`loop`. Keep clock elements and scroll-driven elements in separate `after` chains.

## Colour across the page

- 41 threshold flip: one deliberate change (lights down for a finale), alternating chapters, or a
  palette per scene; the more often it changes, the more each change needs to mean.
- A ground that follows the scroll (a few colour stops, `colour.md` C3) and a theme flip on the
  same scenes both write the ground; on the scenes where they meet, one of them wins.
- 37 hue across a whole page shifts the brand colours too; scoped (38) to one figure it stays a
  detail.
- 27 duotone ties mixed photos into one set; tinting the same photos with 37 as well changes the
  inks it relies on.
- 40 invert reads over photographs with strong darks and lights; over mid grey it becomes
  unreadable.

## Across a page

- Held scenes (zone, stack, track) next to each other make a long stretch where the page does not
  move forward; ordinary sections between them change the pace.
- Several scenes that each carry their own effect read as a sampler; a motif or a treatment that
  returns ties them together.
- Pages range from one long held scene to many short ordinary ones; both extremes work when the
  material suits them.

## Index of the 41: mode, layout, good partners, poor partners

F = framework primitive, P = page work, X = not available. Modes: S ordinary scroll, Z zone,
T track, K stack, D drag, C clock. Layouts are in `layouts.md`.

| # | Reference | Kind | Modes | Layouts | Often pairs well with | Tends to work against |
|---|---|---|---|---|---|---|
| 01 | Page progress | F | S | thin bar under the top bar | 23 scrollspy, 16 markers | D (no document progress); decorative counters |
| 02 | View progress | F | S | any figure passing | 12, 04, 30 | the same property driven by `enter` |
| 03 | Pin and scrub | F | Z | L01, L02, L10, L12 | 08, 10, 30, 27, 26, video, subscribe | 12 band; another zone right after |
| 04 | Parallax | F | S | L05, L13 | 12, 02 | the subject of a sentence; 03 on the same element; body text |
| 05 | Horizontal section | F | T | L04, L19 | 30, 19, 13 | 14, 22 inside it; uneven panel heights |
| 06 | Stacking cards | F | Z, K, S | L03 | 11, 18, step legend | step cutting text; deck taller than the screen |
| 07 | Velocity skew | F | S | decorative strokes | 04 on the same strokes | body text, images with faces, D |
| 08 | Timeline scope | F | Z | L01, L14 | 03, 30, 09 | subjects in different scenes |
| 09 | Path drawing | F | S, Z, C | L06, L10, L18, L26 | 32, 13, 08, loop | a fill that carries meaning; scribbles with no route |
| 10 | Word scrub | F | Z | L01 (words left) | 08 (images share windows) | 32 on the same text; long passages |
| 11 | Curtain overlap | F | K | full-screen scenes | 06, 05 next, 41 | a covered scene that keeps animating |
| 12 | Depth of field | F | S | L13, L05 | 04, 02 | text; Z (needs passage) |
| 13 | Count | F | S, Z, D | L09, inside cards | 32 caption, 30 | invented numbers; numbers without unit or label |
| 14 | Scroll snap | P | S (local) | L13 local strip | 16, 17 | D; T |
| 15 | Snap stop | P | S (local) | step galleries | 14 | skippable content |
| 16 | Scroll markers | P | S | dots beside a strip | 14, 23 | markers without a current state |
| 17 | Scroll buttons | P | S, D | prev/next under a strip | 14, `stage.goTo` | buttons without end states |
| 18 | Stuck state | F | Z, K | any held scene | 03, 06 | ordinary sections (they are not held) |
| 19 | Snapped state | F | S, T, D | nav, row panels | 05, 23 | styling that hides content |
| 20 | Direction state | F | S | top bar | 01 | hiding the only way to navigate |
| 21 | Infinite loop | X | none | none | none | Stage scenes are finite |
| 22 | Kinetic drag | P | S (local) | L13 strip | 24 | D; T |
| 23 | Scrollspy | F | S | contents list, nav | 01, 19 | in-scene headings without scene anchors |
| 24 | Overscroll containment | P | S, D | local panels, embedded frames | 22 | trapping the page's own scroll |
| 25 | Blur-up | F | S, Z | any image | 27, 30 | faking a load that is not happening |
| 26 | Ken Burns | F | Z, D, S | L05, L12 | 32 caption, 41 | 04 on the same image; two pushes in view |
| 27 | Duotone | F | Z, S | L12, L15 | 12, 25, 30 | 37 on the same images |
| 28 | Progressive blur | P | S | L05 (text over image) | 32 | images with the subject under the text |
| 29 | Dithering | P | S | L13, L05 | 27 (pick one) | small images (pattern turns to noise) |
| 30 | Clip reveal | F | S, Z, T | L01, L02, L12, L15 | 32, 08, 09 | a direction that means nothing; 31 |
| 31 | Comparison slider | P | S | L15 | 27 for the "after" | 30 on the same pair; D |
| 32 | Split text | F | S, Z, D | L06, L07, any title | 09, 30, 13, 33 | 10 on the same text; long body copy |
| 33 | Variable font | F | S, Z | L06, large words | 32 | fonts without the axis; small text |
| 34 | Text mask | P | S | L05 (giant word) | 26 on the image | thin fonts; busy images |
| 35 | Vertical writing | P | S, T | narrow column, poetry | `unroll`, 05 | mixed Latin and numbers without rules |
| 36 | Marquee | P | S | thin band (L20 logos) | 07 | key information; Z |
| 37 | Token interpolation | F | S, Z | figure accents | 38 (scope it) | 27 on the same images; whole-page brand colour |
| 38 | Scoped rotation | P | S, Z | one figure | 37 | page-wide variables |
| 39 | Gamut arc | P | S, Z | colour changes | 37, 41 | unchecked middle colours |
| 40 | Difference invert | F | S | text over photos | 26 | mid-grey grounds |
| 41 | Threshold flip | F | S, Z, D | L26 dark act | 11, 26, drag demo | several dark acts; flipping light acts in a continuous ground |
