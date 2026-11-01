# Reveric Design System

> **Reveric** is an AI‑assisted long‑form fiction writing application. The
> visual language is calm and modern — a cool mint‑white canvas, white
> cards that float on soft shadows, near‑black ink‑jade (墨玉) actions with
> jade for AI, sans titles and Georgia only for the manuscript — explicitly rejecting generic
> SaaS polish, glassmorphism, purple‑blue AI gradients, and neon chat‑toy
> aesthetics. **The writer's manuscript is the hero; AI is tooling.**

This project mirrors that system in HTML/CSS so design agents can ship
on‑brand Reveric artifacts (mocks, throwaway prototypes, marketing pages,
chapter sketches, settings dialogs, slides) without rebuilding tokens by
hand.

## Sources

The source of truth is this repository’s `DESIGN.md`, `PRODUCT.md`, and
`lib/shared/theme/`.

## Product context

Reveric is **not** "an AI chat app for writers". It is a structured
**creative workspace** in which novels, chapters, world rules, characters,
outlines, foreshadowing, and AI agents all live as connected story assets.
The recommended writing flow is **five‑step human‑machine collaboration**:

1. **Chapter summary** — author or AI, with human review
2. **Chapter title** — author or AI shortlist
3. **AI drafts the chapter** — using world + character + outline as context
4. **Author revises** — the surgical, voice‑defining step
5. **AI polishes** — grammar, rhythm, repetition; final pass

The application is a desktop Flutter app (macOS / Windows / Linux) with a
mobile companion. There is no marketing website, no docs site, no SaaS
dashboard in scope — **one product**, exactly: the desktop writing client.

Primary surfaces:

- **Home / Library** — novels, recent AI sessions, agents/subagents/skills
  in a left rail
- **Novel Editor** — chapter tree + manuscript editor + AI chat panel
- **Agent / Subagent / Skill edit panels** — prompt management
- **Settings** — providers, appearance, background, language
- **Onboarding** — first‑run welcome with the brand illustration

The product ships **bilingual** (English + Simplified Chinese) and assumes
extended, focused writing sessions, not impulse usage.

---

## Content fundamentals

### Tone & voice

- **Calm, literary, deliberate.** Practical and craft‑oriented, not
  promotional. "Reveric should feel like a writer's study with careful
  tooling: warm, focused, readable, and quietly capable."
- **AI is a collaborator, not a protagonist.** Copy never sells the AI;
  it describes what it will help the author *do*. Examples from the repo:
  *"AI 自动参考设定、人物档案、前文内容"* — AI quietly references
  established lore rather than "magically generating".
- **Practical metaphors over hype.** "Cartographer's desk", "parchment",
  "manuscript", "ink", "foreshadowing埋设/回收". The world is real‑craft
  vocabulary, not "AI‑powered intelligence".

### Casing & punctuation

- **Sentence case** for titles, buttons, menus, and section headers.
  Not Title Case. Not ALL CAPS (except optional `uiTiny` 1‑letter‑spaced
  section labels in the sidebar, used sparingly).
- **No emoji.** None. Anywhere. Iconography is phosphor SVG only — see
  ICONOGRAPHY.
- **No exclamation marks** in product copy. "Saved." not "Saved!". A
  toast is a quiet confirmation.

### Person / address

- The author is **"the writer"** / **"作者"**. Direct address ("you") is
  used in onboarding and tooltips; product copy generally describes state
  rather than addresses the user.
- Chinese copy uses neutral plain form (no `您`).

### Vibe — three examples

- **Hero (zh):** *"AI 辅助小说创作软件"* — five words, no hype, the
  product literally on the label.
- **Empty state (zh):** *"先把'约束'和'路线'固定下来，降低后续写崩设定
  和剧情失控的风险。"* — caring, practical, mentions failure modes
  honestly.
- **Toast (en):** *"Saved."* — period, lowercase verb after, no
  decoration.

### Anti‑patterns (do NOT do)

- ❌ "Unlock the power of AI writing!"
- ❌ "Your intelligent co‑writer 🤖✨"
- ❌ "Welcome back! Ready to create magic?"
- ❌ ALL CAPS section headers, marketing pull‑quotes, decorative metrics
  ("12,432 chapters drafted this week").
- ❌ Calling the user "creator" or "storyteller". Call them **the writer**.

---

## Visual foundations

### Color

The default palette is **Reveric · 玉白 · 墨玉** — a cool mint‑white canvas
(`#F2F6F4`) holding white cards, near‑black ink‑jade (`#1C2623`) for primary
actions, and jade (`#2A9C78`, the `accent-amber` slot) for AI and small
emphasis — intentionally low‑glare. The mockups use it as the default; the Flutter
runtime palette in `reveric_colors.dart` has not been switched yet. Palettes
mirror Flutter `AppTheme` — **three palettes** × light/dark, defined in
`../themes.css` and switched by `../theme.js` (floating bar, or Settings →
外观):

| Palette       | Personality                              | Accent (light / dark)   |
|---------------|------------------------------------------|-------------------------|
| Reveric ★     | Mint‑white canvas, ink‑jade (default)    | `#1C2623` / `#E4ECE8`   |
| 经典 Classic  | Pure B&W, high contrast                  | `#000000` / `#FFFFFF`   |
| 象牙 Ivory    | Sage on cream                            | `#A2AF9B` / `#A2AF9B`   |

Every palette obeys the **Writer‑First Rule** (accent for action + state,
not decoration) and the **Tinted Ink Rule** (no pure `#000` for text or
actions — use the palette's tinted near‑blacks; Classic is the deliberate
pure‑B&W exception, mirroring Flutter).

Semantic colors are stable across palettes: deletion red, addition green,
warning amber, blockquote amber. See `colors_and_type.css` for the
authoritative variable list.

### Typography

**The Manuscript vs. Mechanism Rule.** Two type families, one purpose
each:

- **Manuscript = Georgia** (`--font-serif`) only for prose being read or
  written: chapter text, excerpts, novel summaries, blockquotes, script
  lines. Body sits at 16px / 1.75 leading — generous enough that 65–75ch
  line length is comfortable.
- **Everything else = system sans** (system-ui / SF Pro / Segoe / PingFang SC).
  Every title — page, section, card, dialog, hero, cover, stat number —
  uses `--font-display` (sans, 600–700, tracking −0.01 to −0.02em at
  ≥22px, never decorative italic). Labels, nav, buttons, toolbars,
  metadata and chat use `--font-sans` at fixed sizes (`ui` 13 / `uiSmall`
  12 / `uiTiny` 11). **No fluid type.**

### Spacing & radii

The spacing scale is tight and named numerically by Material‑style steps:
`xxs 4 / xs 6 / sm 8 / md 10 / lg 12 / xl 14 / 2xl 16 / 3xl 20 / 4xl 24 /
5xl 28 / 6xl 40`. The editor uses **72px horizontal padding** to preserve
prose line length — protect this number when recreating the editor.

Radii are **rounded and modern**: `small 6 / medium 8 / large 12 / xl 14 /
2xl 18 / full 20 / pill 999`. Every button is a pill (`--radius-button`),
as are chips and tags (`--radius-pill`). Cards, panels and dialogs use
18px (`--radius-2xl`); small cards and inputs 12px; menus 14px. **Never**
use pill radii on cards or panels.

### Elevation

**Cards float, chrome stays flat.** Cards and panels sit on the canvas
with `--shadow-card` and no visible border (`--card-border` is transparent
in light, a faint hairline in dark). Dialogs and popovers use
`--shadow-dialog` / `--shadow-overlay`. Chrome — sidebars, toolbars, nav
rail, inputs, list rows — stays flat: tonal layers (`canvas` → `surface` →
`surfaceDim` → `surfaceContainer`) plus `selected`/`hover` fills. No
ad‑hoc shadows beyond these tokens.

### Background, imagery, texture

The app supports a **user‑configurable global background**. Bundled
options ship as `.webp` photographs of ink‑painted landscapes:
*distant mountains*, *plum blossom*, *solitary boat*, *withered tree*,
*magnificent*, *starry sky* — quiet Chinese‑literary scenes with grain.
When a background is active, sidebars and toolbars switch to translucent
chrome; cards/inputs/dialogs stay **opaque** (the "elevated" layer).

Marketing‑style hero illustrations are not used inside the product. The
single bundled vector illustration (`ai_assistant_window.svg`) appears on
the AI onboarding bubble, not as a hero. Maps and decorative imagery
exist in `raw_assets/` only for the in‑app **world map tool** — they are
content, not chrome.

No gradients on surfaces or on the logo — the mark is a flat `#283B5E`
ribbon over a flat `#8797D2` fold.

### Animation

Restrained. The repo has no motion library; transitions are Flutter
`AnimatedRotation` 200ms for caret expanders and standard Material
state transitions for buttons. **No bounces, springs, parallax, or
fade‑ups.** Hover changes the background to `hover` or `selected`;
press is the same color a shade deeper. No scale or shrink presses.

### Borders & dividers

`border` (1px, primary) divides major regions; `borderSubtle` divides
internal sections; `borderInput` outlines inputs and dropdowns. Cards use
`--card-border` + shadow instead of an outline.
The vertical 1px divider between sidebar and main content uses
`border`. Dividers are always 1px, full saturation — no faded gradients.

### Transparency & blur

Transparency appears only when the **global app background** is active,
on chrome (sidebar, toolbar, scaffold). Cards/inputs/dialogs stay
opaque. No glassmorphism, no inner shadows, no protection gradients.

### Corner radii summary

| Element                      | Radius   |
|------------------------------|----------|
| Tag / chip                   | pill (999) |
| Button (all variants)        | **pill (999)** |
| Input / small card           | 12px     |
| Menu / popover               | 14px     |
| Card / panel / dialog        | **18px** |
| Chat bubble                  | 14px     |
| Avatar                       | 50%      |

### Cards

A Reveric card is: `surface` + `1px solid var(--card-border)` + 18px
radius (`--radius-2xl`; 12px for cards ≤ ~160px) + `--shadow-card` +
12–24px internal padding. Never card‑in‑card. Placeholder covers use cool,
desaturated gradients (ink‑jade, slate, plum, dusty jade) — no sepia. Never left‑border‑accent‑only cards.

---

## Iconography

See [`ICONOGRAPHY.md`](./ICONOGRAPHY.md). Short version:

- **System:** [Phosphor Icons](https://phosphoricons.com/) — `regular`
  weight only. SVGs are stored locally at `assets/icons/phosphor/*.svg`,
  monochrome, recolored via `currentColor`.
- **No emoji. No Material icons. No Unicode glyph icons.**
- **Sizes:** 14 / 16 / 18 / 20 / 24 (sidebar list items use 16; toolbar
  buttons use 18; AI avatars 20–24).
- ~165 icons are checked into the repo. A curated ~95 subset is mirrored
  here in `assets/icons/phosphor/` — pull more from `phosphor-icons.com`
  if you need them, but **keep the family consistent** (always `regular`).

---

## Index

| Path                      | Purpose                                                     |
|---------------------------|-------------------------------------------------------------|
| `README.md`               | This file — product + content + visual foundations          |
| `ICONOGRAPHY.md`          | Icon system rules and inventory                             |
| `SKILL.md`                | Agent Skill manifest — read when the skill is invoked       |
| `colors_and_type.css`     | Tokens (CSS custom properties) + semantic element classes   |
| `assets/logo/`            | Reveric mark (svg + png 128/256) + stacked lockup + app icon |
| `assets/icons/phosphor/`  | ~95 phosphor `regular` SVGs (the working subset)            |
| `assets/illustrations/`   | `ai_assistant_window.svg` — only product illustration       |
| `assets/images/background/` | Four ink‑painting backgrounds (webp)                      |
| `preview/`                | Design System tab cards (typography, colors, components)    |
| `index.html`              | Desktop entry & home page — Library / Editor / Chat (click‑through) |
| `*.jsx`, `kit.css`, `data.js` | Home page app source — React (Babel‑in‑browser)         |
| `MapStudio.jsx`, `map_studio.*` | 地图工作台 — 世界观·地图栏目（`index.html?screen=map`）     |
| `LibraryCollections.jsx`, `library_collections.*` | 作品库的集合书架 + 对齐 Flutter 的竖版作品网格：书架一行横滑、集合页、「加入集合」菜单、多选批量、添加作品选择器。深链 `?collection=<id>`、`&select=1`、`&picker=1`、`&menu=collections`；剧本页 `?screen=screenplays` |
| `UI_KIT.md`               | Component reference for the home page app                   |
| `canvas/`                 | 无限画布 — CanvasEditorPage prototype (board / inspector / AI co‑creation) |
| `screenplay/`             | 剧本写作 — 剧集项目（季 / 集 / 场次）：剧本正文、大纲（每集一份文档 + 只读节拍）、节拍、场次（列表 / 场次板 / 出场矩阵）、人物关系；制作（片段）在 `drama/` 制片页。电影形态标为第一期暂不支持 |

---

## Caveats

- **Georgia substitution.** The repo specifies Georgia (system font). No
  webfont file is bundled because Georgia ships with every major OS.
  Windows / macOS / Linux Server installs should fall back via the stack
  `Georgia, "Times New Roman", "Songti SC", serif`. If you need an
  open‑source replacement, **Source Serif 4** is the closest match in
  proportion and weight.
- **Mobile (`lib/mobile/`)** exists in the repo but is not mirrored —
  this design system covers the **desktop client only**.
- **No marketing site** exists. If you need to design one, *invent*
  using the foundations here; do not assume there is a hidden reference.
