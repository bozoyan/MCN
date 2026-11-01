# Visual directions

The recipes in this folder use neutral variables. Setting these variables is what gives a page its
look, and the same scene structure reads very differently under each set. Below are some
directions as starting points, each with values to adapt; a brand's own fonts and colours take
their place whenever they exist. Mixing parts of several directions, or ignoring all of them, works
as well.

```css
/* the variables the recipes use */
:root {
  --font-display: ...;   /* titles */
  --font-body: ...;      /* text */
  --ground: ...;         /* page background */
  --surface: ...;        /* cards, panels */
  --ink: ...;            /* titles */
  --ink-soft: ...;       /* body text */
  --accent: ...;         /* links, buttons, highlights */
  --on-accent: ...;      /* text on the accent */
  --line: ...;           /* rules, outlines, line art */
  --radius: ...;         /* corner rounding */
}
```

## At a glance

| Direction | Feels | Often suits |
|---|---|---|
| Clean product | clear, calm, trustworthy | software, tools, fintech |
| Editorial paper | literary, crafted, unhurried | culture, publishing, studios |
| Night neon | electric, after dark | games, music, gadgets |
| Poster | loud, graphic, immediate | events, launches, campaigns |
| Soft lifestyle | warm, friendly, photo-led | food, cafés, wellness, travel |
| Monochrome documentary | serious, honest, timeless | journalism, non-profits, history |
| Playful | bright, bouncy, approachable | kids, education, communities |
| Luxury minimal | quiet, expensive, precise | fashion, jewellery, hotels, cars |
| Brutalist | raw, direct, unpolished on purpose | agencies, indie tools, art |
| Retro terminal | nerdy, nostalgic, technical | developer tools, CLIs, hacker events |
| Swiss grid | ordered, rational, typographic | architecture, design studios, reports |
| Organic nature | earthy, slow, textured | outdoors, farms, sustainability |
| Cinematic | dramatic, widescreen, story-led | films, games, brand stories |

## Clean product

White or near-white, a sans-serif in two weights, one saturated brand colour, generous radius,
soft shadows. Suits software, tools, fintech, developer products.
- Fonts: Inter, Manrope, IBM Plex Sans; numbers in the same family.
- Values: `--ground: #ffffff; --surface: #f5f7fa; --ink: #0f172a; --ink-soft: #475569;
  --accent: #2563eb; --on-accent: #ffffff; --line: #e2e8f0; --radius: 16px`.
- Titles: 600 weight, tight tracking, one line where possible.
- Motifs: interface fragments, a grid of small icons, product screenshots in device frames.
- Motion: short and crisp (`rise(soft)`, `wipe`), little decoration.

## Editorial paper

Warm off-white, a serif for titles, thin rules, an earthy accent, lots of space. Suits culture,
publishing, craft, studios. (The Cineview homepage is one version of this.)
- Fonts: Fraunces, Newsreader, Noto Serif SC; body in a quiet serif or sans.
- Values: `--ground: #fbefdd; --surface: #fffaf3; --ink: #352820; --ink-soft: #5f4739;
  --accent: #994f36; --on-accent: #fffaf3; --line: #caae8c; --radius: 14px`.
- Titles: light weight, very large, arranged in rows with rules or offsets.
- Motifs: line drawings, a single repeated object (a reel, a dial), film strips.
- Motion: slow entrances, drawn lines.

## Night neon

Near-black, one or two glowing colours, high contrast, a technical sans or mono. Suits games,
music, nightlife, gadgets, anything after dark.
- Fonts: Space Grotesk, Sora, JetBrains Mono for details.
- Values: `--ground: #07080d; --surface: #11131c; --ink: #f4f6ff; --ink-soft: #a6acc8;
  --accent: #ff3d7f; --on-accent: #07080d; --line: #2a2f45; --radius: 10px`.
- Titles: bold, uppercase or tight, sometimes with a glow (`text-shadow` in the accent).
- Motifs: light trails, grids, scan lines, a single glowing object.
- Motion: fast wipes, scrubbed video, counts.

## Poster

Big blocks of colour, a heavy grotesque at huge sizes, tight leading, almost no ornament. Suits
events, campaigns, fashion, launches.
- Fonts: Archivo Black, Anton, Bebas Neue (Latin); a bold sans for CJK.
- Values: two or three flat colours used as whole-section grounds, e.g. `--ground: #ffde21;
  --ink: #111111; --accent: #ff4b1f; --on-accent: #111111; --radius: 0`.
- Titles: fill the width; one word per line; numbers as graphic elements.
- Motifs: colour blocks, oversized numerals, cut-out photos.
- Motion: big moves (`wipe`, `push`), blocks sliding over each other (`stack`).

## Soft lifestyle

Pale, rounded, photo-led, friendly. Suits food, cafés, wellness, consumer apps, travel.
- Fonts: DM Serif Display or Recoleta for titles; Nunito or DM Sans for text.
- Values: `--ground: #f6f1ea; --surface: #ffffff; --ink: #2b2a28; --ink-soft: #6b665f;
  --accent: #d9774b; --on-accent: #ffffff; --line: #e6ddd2; --radius: 28px`.
- Titles: medium size, centred or beside a photo.
- Motifs: rounded photo crops, hand-drawn underlines, small stickers.
- Motion: gentle (`focus`, `rise(soft)`), photos that drift slightly.

## Monochrome documentary

Black and white photography, grain, a serif or typewriter face for captions, red or no accent.
Suits journalism, non-profits, history, portraits, brand stories.
- Fonts: Source Serif, IBM Plex Mono for captions.
- Values: `--ground: #111111; --surface: #1b1b1b; --ink: #f2f2f2; --ink-soft: #b3b3b3;
  --accent: #e23b2e; --on-accent: #ffffff; --line: #333333; --radius: 0`.
- Titles: modest size; the photos carry the page.
- Motifs: full-bleed photos, captions with dates and places, archival frames.
- Motion: slow push on photos, captions fading in, `duotone(mono)` to unify mixed sources.

## Playful

Bright colours, rounded shapes, bouncy entrances, illustrations. Suits kids' products, education,
community tools.
- Fonts: Fredoka, Baloo 2, Quicksand.
- Values: `--ground: #fff7e6; --surface: #ffffff; --ink: #1d1b4b; --ink-soft: #4b4a7a;
  --accent: #7c5cff; --on-accent: #ffffff; --line: #ffd36b; --radius: 24px`.
- Titles: chunky, sometimes rotated a few degrees.
- Motifs: blobs, stickers, characters, confetti shapes.
- Motion: `grow`, springy easing (`cubic-bezier(.34, 1.56, .64, 1)`), loops.

## Luxury minimal

Lots of empty space, a thin high-contrast serif, black and one metallic or muted tone, very slow
motion. Suits fashion, jewellery, hotels, cars, perfume.
- Fonts: Cormorant Garamond, Bodoni Moda, Playfair Display; body in a light sans (Jost, Montserrat
  light).
- Values: `--ground: #f7f5f2; --surface: #ffffff; --ink: #121212; --ink-soft: #6e6a64;
  --accent: #a08458; --on-accent: #ffffff; --line: #d9d4cc; --radius: 0`.
- Titles: small caps or wide letter-spacing for labels, large light titles, few words.
- Motifs: one product photographed on a plain ground, thin rules, a monogram.
- Motion: very slow `push`, `focus`, long fades; nothing bounces.

## Brutalist

Raw HTML energy: system or mono fonts, hard borders, clashing colours, visible structure,
deliberately unpolished. Suits agencies, indie tools, art projects.
- Fonts: system-ui, Courier Prime, Space Mono, Arial Black.
- Values: `--ground: #f2f2f2; --surface: #ffffff; --ink: #000000; --ink-soft: #222222;
  --accent: #0000ff; --on-accent: #ffffff; --line: #000000; --radius: 0`; 2-4 px black borders.
- Titles: huge, sometimes overflowing their boxes on purpose, underlined links.
- Motifs: boxes with thick borders, raw screenshots, marquee bands, visible grids.
- Motion: abrupt (`wipe` with linear easing, instant switches), `skew` on fast scroll.

## Retro terminal

Monospace everything, green or amber on black, scan lines, blinking cursors. Suits developer
tools, CLIs, hacker events, games with a retro feel.
- Fonts: JetBrains Mono, IBM Plex Mono, VT323 for display.
- Values: `--ground: #0b0f0a; --surface: #111a10; --ink: #b7f7a5; --ink-soft: #6fa862;
  --accent: #ffcc33; --on-accent: #0b0f0a; --line: #1f3a1b; --radius: 2px`.
- Titles: typed in (typewriter, `type.md` T3), a prompt sign before them.
- Motifs: command lines, ASCII art, window frames, a faint scan-line overlay.
- Motion: typing, stepping (`steps()` easing in `keyframes`), cursor blink as a `loop`.

## Swiss grid

A strict grid, a neo-grotesque sans, flush-left text, big numbers, red as the only colour. Suits
architecture, design studios, annual reports, conferences.
- Fonts: Inter Tight, Neue Haas Grotesk alternatives (Helvetica Neue, Arimo), Noto Sans SC.
- Values: `--ground: #ffffff; --surface: #f4f4f4; --ink: #111111; --ink-soft: #555555;
  --accent: #e3000f; --on-accent: #ffffff; --line: #111111; --radius: 0`.
- Titles: flush left, tight leading, set on the grid; numbers as section markers.
- Motifs: visible columns, thin rules, numbered sections, cropped photos in exact boxes.
- Motion: precise `wipe` along grid lines, `split="lines"` entering in order.

## Organic nature

Earth colours, paper or linen textures, hand-drawn lines, photography of materials. Suits
outdoor brands, farms, sustainability, ceramics, tea.
- Fonts: Lora, Fraunces (soft), EB Garamond; body in a humanist sans (Source Sans, Nunito Sans).
- Values: `--ground: #efeadf; --surface: #f8f5ee; --ink: #2f3a2c; --ink-soft: #5d6656;
  --accent: #7a8b4a; --on-accent: #ffffff; --line: #c9c0ad; --radius: 18px`.
- Titles: medium, warm, sometimes with a hand-drawn underline.
- Motifs: leaves, contour lines, grain textures, irregular photo crops.
- Motion: drawn lines (`draw`), slow `drift` on layers, photos coming into focus.

## Cinematic

Widescreen frames, letterbox bars, a dark ground, big moving pictures with sparse titles, like a
film's title sequence. Suits films, games, brand stories, product launches with strong footage.
- Fonts: a condensed display (Oswald, Bebas Neue, Barlow Condensed) or an elegant serif; small
  credits in a light sans.
- Values: `--ground: #050505; --surface: #121212; --ink: #f5f1ea; --ink-soft: #a8a196;
  --accent: #d4a24c; --on-accent: #050505; --line: #2b2b2b; --radius: 0`.
- Titles: centred, spaced out, appearing over the picture like credits.
- Motifs: 2.39:1 frames, letterbox bars that open and close, film grain, timecodes.
- Motion: scrubbed video (`video.md` V1), slow `push`, cuts between scenes (`transitions.md`).

## Choosing

What usually decides it: the product's category and audience, the material (photos suit
lifestyle and documentary; screenshots suit clean product), an existing brand, and the tone the
user wants. Offering two or three that fit, with a sentence on why, gives the user something to
react to; their answer often lands somewhere in between.
