# Layouts

A catalogue of arrangements that work, to mix and adapt. Sizes are written for a 1920-wide design
in the unit `--u: calc(min(100vw, 177.78vh) / 1920)` (so `calc(N * var(--u))` scales with the
screen) and a page margin `--m`; any other system works as well. On narrow screens most of these
become one column; sizes set in `--u` get small on phones (a 700u block is 146 px wide at 400 px),
so fixed px or `auto` widths usually read better there.

Each entry: structure | sizes | modes | references | content it suits.

## Columns and figures

**L01 Copy left, figure right.** Grid `minmax(0, 620fr) minmax(0, 900fr)`, gap 100-140u, one
screen high, copy vertically centred on the figure. | Title 76u, text 22u, figure from the height:
`width: min(100%, calc((100svh - 260 * var(--u)) * 16 / 9))` for a 16:9 figure. | Z, S | 03, 08, 10, 30, subscribe | a product
part, an interface, a process diagram, a drawing.

**L02 Figure left, copy right.** L01 mirrored (`order`). Alternate L01/L02 down a page. | same |
S | 30 (wipe from the copy's side), 32 | image + sentence pairs, case studies.

**L03 Copy left, deck right.** Copy 620fr; deck 860-900u wide, right-aligned; cards content-tall;
covered cards show the head row (`step` = head height); a step legend under the copy. | card
padding 24u 36u; head 30u; text 24u | Z + stack | 06, 11, 18 | steps, a method, a plan.

**L04 Lead block, then a row.** A 520u lead (title + text), then panels 520u wide x content tall,
40u apart, last panel ending on the right margin. | panel padding 40u | T | 05, 30 | kinds,
options, a timeline of items.

**L05 Full-bleed picture, copy over it.** Picture covers the screen (`object-fit: cover`), copy in
the lower left on a soft gradient or progressive blur. | title 88u | Z, S, D | 26, 28, 34, 41 |
one strong photo, a brand moment.

**L06 Centred title card.** A small kicker (name in the accent colour + what it is, a short rule
under), then one or two very large lines, then one sentence and two buttons. | headline 140-180u;
kicker 44u | S, C | 32, 09, 33 | the opening screen.

**L07 Two-row staggered title.** Row 1 starts on the left margin with a rule running out to the
right edge; row 2 ends on the right margin with a rule from the left edge; or row 2 begins where
row 1 ends (two `max-content` columns). | rows 140u apart, rules 1.6u | S, C | 32, 09 | an
opening line, a transition line between sections.

**L08 Three cards in a row.** Three equal columns, 40u gaps; each card: icon or thumbnail, title,
two lines, a tag. | card padding 40u | S | 30, 32 (stagger) | features, plans, benefits.

**L09 Big number with caption.** A number at 200-280u, the unit beside it, a one-line label under,
the source in small text. Two or three side by side at most. | | S, Z | 13, 32 | results,
proof, statistics (true ones).

**L10 Timeline (Gantt).** A screen frame on top showing parts; below, one track per part with a
take (bar) whose position is the part's window; connectors from one end to the next start; a
playhead. | track 34u high; take labels 15u | Z | 03, 08, 09 | sequencing, schedules,
"what happens when".

**L11 Storyboard strip.** Three to six shot frames (4:3 or 9:16) with arrows between and a caption
under each. | frames 120-250u wide | S, T | 30, 09 | a plan of scenes, a flow, a user journey.

**L12 Film strip.** A dark film base with sprocket holes top and bottom (drawn in the ground
colour), five 9:16 frames, edge print text; step chips under it. | frames up to 250u wide;
base padding 52u 34u | Z | 12, 27, 30, video | a set of photos or video stills; treatments.

**L13 Gallery passing the reading line.** Pictures in one column (or offset two columns), each
with a caption, spaced so one is near the middle at a time. | images 60-70% width | S | 12, 04,
25, 14 (local) | portfolios, photo essays.

## Product, proof and closing

**L14 Code card next to its result.** Copy and a code card (monospace 18u, 26u 30u padding, a
coloured keyword) on the left; the result (drawing, canvas, live demo) on the right or under the
whole scene. | | Z, S | 03, 08, subscribe | APIs, "how it is made".

**L15 Before and after.** Two aligned pictures of the same subject, side by side or one over the
other with a divider; labels in the corners. | | S | 31, 27, 30 | redesigns, edits, filters.

**L16 Conversation.** A brief card (what the user asks, with copy and secondary buttons) on the
left; three answer cards on the right, each offset 48u to the right of the one above, each with a
small header (who answers). Typed text enters on view. | answer cards 640-740u | S | 32
(lines), typewriter | AI products, support, onboarding.

**L17 Phone with copy.** A phone frame 332:720 (thin accent edge, warm glow), nearly a screen
high; the copy beside it as one centred group (phone ~0.86, gap 110u, copy 600u). On phones:
the phone shrinks to the top, the copy fills below. | | D, Z | 41, drag demo | apps, mobile
products, an embedded drag demo.

**L18 Step flow.** Three numbered circles joined by short lines, each with a word; under a
deck or a paragraph as its legend. Numbers outlined, filled as their step is reached. | circles
34u; lines 46u | Z, S | 06, 09 | any three-step process.

**L19 Catalogue panels.** In a row (L04) or a grid: each panel has a three-shot storyboard, a
name, one approach line, a sample line set as a quote, a pace bar, effect tags, a use line. |
panels 520u | T, S | 05, 30 | page types, templates, product lines.

**L20 Logo or partner band.** One row of marks at 40-60% opacity of the ink colour, evenly
spaced; optionally a slow marquee. | marks 40u high | S | 36 | customers, partners.

**L21 Quote with picture.** A large quote (52-64u serif), the person's name and role, a portrait
or product photo beside it. | | S | 32, 30 | testimonials, a founder's line.

**L22 Pricing tiers.** Two or three columns; one highlighted with the accent edge; price at 72u,
features as a short list, one button each. | | S | 13 (for real numbers) | plans.

**L23 Questions.** A list of questions as buttons that open their answers; one open at a time;
no motion beyond a short fade. | | S | none | FAQs, specs.

**L24 Closing action.** A title, one sentence, a primary button and one or two secondary ones,
centred or under the last act's copy. | title 64u | S, Z | 32 | the end of every page.

**L25 Narrow screen.** One column; 88px top padding (clear of the bar); titles 32px; decks with
fixed head heights; decorations under text hidden; figures full width; sideways rows keep
250px panels. | | all | | every layout below 760px.

**L26 Dark immersive act.** `theme="night"`: near-black ground, warm light text, one accent; the
top bar can turn clear once the act reaches it; a single lit object (a phone, a screen, a product). |
| D, Z | 41, 26, 11 | the finale, a demo, a cinematic sequence.

## More arrangements

**L27 Bento grid.** A grid of unequal tiles (one large, several small), each a feature with an
icon or a cropped screenshot; tiles enter with a short stagger. | gap 20-24u, radius from the
style | S | 30, 32 | software features, product specs.

**L28 Sticky caption, scrolling pictures.** A caption column that stays (`position: sticky`)
while a column of pictures scrolls past; the caption changes as each picture reaches the middle
(`view(#picture)` or `data-cv-current`). | | S | 02, 08, 12 | case studies, step-by-step stories.

**L29 Overlapping cut-outs.** Photos with their backgrounds removed overlapping big type and
colour blocks, each on its own `drift` layer. | | S | 04, 34 | fashion, food, campaigns.

**L30 Split screen.** The screen divided in two halves of different colour, each with its own
content, sometimes swapping sides per scene. | | S, Z | 41, 30 | comparisons, two audiences.

**L31 Single column essay.** One narrow column of text (60-70 characters), pictures breaking out
to full width between paragraphs, captions in the margin. | | S | 32, 12, 26 | stories, reports,
manifestos.

**L32 Marquee band.** One or two thin rows of words or logos moving slowly across the screen
between sections. | | S | 36 | brands, partners, a mood.

## Notes that apply to most layouts

- Surfaces derived from the ground (`color-mix(in srgb, var(--ground) 92%, var(--ink))`) follow
  any palette change.
- Decoration under the content (`z-index: 0`) with the content above it keeps text readable; on
  phones decoration that would sit under text is often better hidden.
- Layout for an animated group (a button row, a label) goes on an element inside the
  `<cv-animate>`; layout set on the `cv-animate` itself does not reach its children.
