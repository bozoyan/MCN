---
name: reveric-design
description: Use this skill to generate well-branded interfaces and assets for Reveric, the AI-assisted long-form fiction writing app, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping.
user-invocable: true
---

# Reveric Design Skill

Reveric is an **AI-assisted long-form fiction writing application**. The
visual language is calm and modern — cool mint‑white canvas, white cards
on soft shadows, near‑black ink‑jade actions (jade for AI), sans for every
title and all UI, Georgia only for manuscript prose. The writer is the hero;
AI is tooling.

## Before you do anything

1. **Read `README.md`** at the root of this skill — it is the source of
   truth for product context, content fundamentals, and visual
   foundations.
2. **Read `ICONOGRAPHY.md`** if your work involves any iconography.
3. **Skim `colors_and_type.css`** — every color, font, spacing and
   radius lives there as a CSS variable. Never hardcode hex.

## Foundation values (always)

| Token            | Default value         | Use for                                |
|------------------|----------------------|----------------------------------------|
| `--canvas`       | `#F2F6F4`            | outermost app background               |
| `--surface`      | `#FFFFFF`            | cards, editor, panels                  |
| `--text-primary` | `#141A18`            | body + headings (NEVER `#000`)         |
| `--accent`       | `#1C2623`            | primary actions + state (sparingly)    |
| `--font-display` | system sans          | every title (page/card/dialog/hero)    |
| `--font-serif`   | Georgia, …           | manuscript prose only                  |
| `--font-sans`    | system-ui, …         | buttons, labels, metadata              |
| body type        | Georgia 16 / 1.75    | reading copy                           |
| button radius    | pill (`999px`)       | every button variant                   |
| card radius      | `18px` (2xl)         | cards, panels, dialogs                 |
| elevation        | `--shadow-card`      | cards float; chrome stays flat         |

## Working modes

**If asked for a visual artifact (slide, mock, throwaway prototype,
landing-style sketch, screenshot deliverable):**

1. Copy `colors_and_type.css` into the artifact's folder (or link to it
   in this skill's directory if working locally inside the skill).
2. Copy any logos / illustrations / backgrounds you'll reference from
   `assets/`. **Never** re-draw them as SVG.
3. Copy any phosphor SVG icons from `assets/icons/phosphor/`. **Never**
   substitute Heroicons / Lucide / Material / emoji.
4. Build a single static HTML file (or a tiny React-via-Babel doc if you
   need state). Match the tonal-layer composition (`canvas` outside,
   `surface` cards with `--shadow-card` and `--card-border`, flat chrome).
5. Cross-check tone & casing against the README's CONTENT FUNDAMENTALS
   section before writing any user-visible string.

**If working on production code (this repository’s Flutter app):**

- Use `RevericTheme.colorsOf(context)` and
  `RevericTheme.typographyOf(context)` — never hardcode colors.
- Use `RevericSpacing`, `RevericRadius`, `RevericSizes`.
- Use `RevericIcon` + `RevericIcons.*` (phosphor only).
- Wrap desktop pages in `DesktopWindowFrame`.
- Surface user-visible copy through i18n (`context.t(LocaleKeys.xxx)`).

## What to absolutely refuse

- ❌ Purple-blue AI gradients, glassmorphism, neon glows, sparkle
  particles, gradient hero text.
- ❌ Emoji in product copy, headlines, or buttons.
- ❌ "Unlock the power of AI…" promotional copy.
- ❌ Colored-left-border accent cards; ad-hoc shadows outside the shadow tokens.
- ❌ Pure `#000` text or actions (white `surface` cards are fine).
- ❌ Material Icons. Custom hand-drawn SVG icons. Unicode glyph icons.
- ❌ Marketing dashboard tropes — decorative metrics, sparkline cards,
  badge-festooned settings.

## If the user invokes this skill with no guidance

Ask **what surface** they want — Reveric only ships one product, the
desktop client, but within it there are five clear surface families:

1. **Home / Library** — novels grid + AI rail
2. **Novel editor** — chapter tree + manuscript + AI chat
3. **Lore / characters / outline** — structured asset
   management screens
4. **Settings / providers / agents** — dialog-mounted config
5. **Onboarding** — first-run welcome

Then ask whether they want:
- A throwaway mock (single HTML)
- A clickable prototype (multiple screens, one HTML with React)
- A slide deck describing a Reveric concept
- Production-grade Flutter widgets (read AGENTS.md inside the repo
  first; follow the file-header comment convention)

When in doubt, propose **the throwaway HTML mock** by default — that's
the fastest path to a useful artifact and easiest to iterate on.

## Tone you write in when asked to write copy

- Sentence case. No exclamation marks. No emoji.
- The user is *"the writer"* / *"作者"*. Not "you", not "creator", not
  "storyteller".
- Bilingual is the norm — every primary copy block should have a
  Chinese version, especially titles and confirmations.
- Use real craft vocabulary (cartographic, manuscript, foreshadowing)
  rather than tech metaphors (intelligent, smart, powerful).

## Index of skill files

| File                       | What's in it                                     |
|----------------------------|--------------------------------------------------|
| `README.md`                | Foundational doc — read first                    |
| `ICONOGRAPHY.md`           | Phosphor icon rules + inventory                  |
| `colors_and_type.css`      | All design tokens as CSS vars                    |
| `assets/logo/`             | Mark + lockup + app icon                         |
| `assets/icons/phosphor/`   | ~95 phosphor regular SVGs                        |
| `assets/illustrations/`    | ai_assistant_window.svg                          |
| `assets/images/background/`| Four ink-painting webp backgrounds               |
| `preview/`                 | Component preview cards (good reference for HTML)|
| `index.html`               | Desktop entry & home page (Library/Editor/Chat)  |
| `*.jsx`, `kit.css`, `data.js` | Home page app source (React via Babel)        |
| `UI_KIT.md`                | Component reference for the home page app        |
| `canvas/`                  | 无限画布 prototype (board/inspector/AI 共创)      |
| `screenplay/`              | 剧本写作 (剧本/大纲/节拍/场次/人物关系)           |
