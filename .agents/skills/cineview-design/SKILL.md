---
name: cineview-design
description: "Plan a Cineview landing page with the user, then build it. Use when someone wants a landing page, wants to design scenes or motion, or brings material (video, photos, screenshots, copy) for a page. Starts with a conversation: what the page is for, how many scenes, what each scene shows and which material it needs, with suggestions and directions; then references for video, images, type, line art, styles, layouts and how the 41 references combine."
---

# Cineview design

Cineview is a framework for landing pages told as scenes: each scene has its own timeline, and the
reader's scroll (or finger) moves through it.

**Start with a conversation, not with code.** When a user asks for a page, or sends material,
`conversation.md` is the place to begin: understand what they want, propose two or three
directions with a number of scenes, go through the scenes one by one (what each says, what the
reader sees, which material it uses and what is still needed), and agree on a storyboard and a
material list. The rest of this folder is the library the suggestions come from.

The library is references, not templates. Its examples use neutral variables (`--font-display`,
`--accent`, ...) so they take on whatever look the page has, and a page can look like its own
product rather than like these notes.

Written for cineview 2 on npm (`cv-*` custom elements). The 1.0.x versions were a different React API;
do not mix their examples in.

## What is here

| Topic | File |
|---|---|
| Planning the page with the user: scenes, material, storyboard | `conversation.md` (first) |
| Elements, attributes, presets, timing, events | `framework.md` |
| Visual directions: type, colour, motifs, density | `styles.md` |
| Video and clips | `video.md` |
| Background video, click to play, transitions between scenes | `transitions.md` |
| Photos, screenshots, illustrations | `images.md` |
| Titles, passages, numbers | `type.md` |
| Line art and small supporting elements | `line-art.md` |
| Your own drawing on the timeline (Canvas, WebGL, SVG) | `drawing.md` |
| Palettes, dark scenes, contrast | `colour.md` |
| Layouts | `layouts.md` |
| How the 41 references behave together, by mode | `combinations.md` |
| Drag mode, and a drag page embedded in a scroll page | `drag.md` |
| Example page structures | `pages.md` |
| The 41 design references | `references.md` |
| Languages, reloads, and ways to test a page | `checks.md` |

Read what the task needs; most pages use a few files.

## Things that are true of the framework

These are how Cineview and browsers behave, so they hold for any design:
- One property of one element follows one progress source; two effects on the same property of
  the same element multiply or fight (`framework.md`).
- In a held scene (`zone`) 1 ms of timeline is 1 px of scroll, and the element that ends last sets
  the length.
- Animated text stays real text (split copies are hidden from screen readers); pictures and
  videos need alt text or a label to be accessible.
- With reduced motion, time-played entrances shorten to fades and loops stop; motion that follows
  the reader's own scroll stays.

## Ideas that often help

None of these is a rule; they are worth weighing against what the page wants.
- One clear change per screen is easier to follow than several at once.
- Real material (the user's own text, pictures and numbers) gives a page its character; invented
  facts or quotes mislead readers.
- A style chosen for the product and audience (`styles.md`) makes the same structure feel
  completely different.
- Body text that is hard to read against its background loses readers; 4.5:1 is the usual
  accessibility reference.
- Looking at the page in a browser at several widths, and having someone else (or a fresh
  assistant) try to break it, catches most problems before the user does (`checks.md`).
