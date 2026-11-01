# Iconography — Reveric

## System

Reveric uses **[Phosphor Icons](https://phosphoricons.com/)**, `regular`
weight only. Phosphor is monolinear with a 1.5‑unit stroke, rounded
caps/joins, and a 256×256 viewBox — its quiet, slightly‑literary
character matches the parchment/Georgia surfaces of the app without
fighting for attention.

The repo wraps phosphor SVGs in a `RevericIcon` widget and maps them
through a static `RevericIcons` registry (see
`lib/shared/theme/reveric_icons.dart`). Each icon is loaded as an SVG
asset and recolored via `currentColor` (Flutter: `ColorFilter.mode(
color, BlendMode.srcIn)`) — there is no icon font.

## What is NOT used

- ❌ **Emoji.** No `🚀✨🤖` anywhere. Ever.
- ❌ **Material Icons** (`Icon(Icons.*)`). The codebase enforces this
  via `.agents/rules/icons.md`.
- ❌ **Unicode glyphs as icons** (`✓ ✗ ← →` etc.). Use the SVG.
- ❌ **Filled / duotone / bold phosphor weights** — only `regular`.
- ❌ **Custom hand‑drawn SVGs** — find a phosphor match, even if the
  semantic fit is imperfect. Consistency > literal accuracy.

## Sizing

| Context                   | Size  |
|---------------------------|-------|
| Caret / chevron in row    | 14px  |
| Sidebar list item / chip  | 16px  |
| Section header            | 16px  |
| Toolbar button            | 18px  |
| AI chat avatar            | 20px  |
| AI agent picker avatar    | 24px  |
| Empty‑state hero icon     | 32px  |

Icons inherit color from text — `color: var(--text-secondary)` for
neutral icons, `color: var(--accent)` for active state, `color:
var(--text-subtle)` for low‑emphasis decorative icons (timestamps,
metadata).

## HTML usage

Because the SVGs use `currentColor`, you can inline them and color them
with normal CSS. Two recommended patterns:

**Inline SVG (preferred — color responds to `color`):**

```html
<!-- fetch the file and inject its contents inline -->
<span style="color: var(--text-secondary); display: inline-flex;">
  <!-- <svg> contents from assets/icons/phosphor/book-open.svg here -->
</span>
```

**Static `<img>` (simpler — but stuck at the default ink color):**

```html
<img src="assets/icons/phosphor/book-open.svg" width="16" height="16">
```

A ready-to-use React helper is provided in
`Icon.jsx` — it fetches the SVG once, caches it,
and inlines it so `color` works through normal CSS inheritance.

## Inventory (working subset, ~95 icons)

A complete list of phosphor names with their Reveric semantic usage:

- **Navigation / app:** `house`, `gear-six`, `magnifying-glass`,
  `caret-{up,down,left,right}`, `arrow-{left,right}`, `dots-three`,
  `dots-three-vertical`, `x`, `arrows-out`, `arrows-in`
- **Writing surfaces:** `book-open`, `books`, `book`, `note-pencil`,
  `pencil-simple`, `pencil-line`, `article`, `file-text`,
  `quotes`, `text-t`, `text-b`, `text-italic`
- **Lists & structure:** `list`, `list-bullets`, `list-checks`,
  `squares-four`, `grid-nine`, `stack`, `tree-structure`, `path`,
  `folder`, `tag`, `flag`
- **AI & council:** `sparkle`, `magic-wand`, `brain`, `robot`,
  `mask-happy`, `lightbulb`, `chat-{circle-text,centered}`, `chats`,
  `paper-plane`, `paperclip`
- **Characters & world:** `user`, `users`, `users-three`, `compass`,
  `map-trifold`, `map-pin`, `mountains`, `city`, `buildings`,
  `tree-evergreen`, `plant`, `waves`, `drop`, `boat`, `door`,
  `globe`
- **Status / state:** `check`, `check-circle`, `x-circle`,
  `warning`, `warning-circle`, `info`, `question`, `clock`,
  `clock-counter-clockwise`, `eye`, `eye-slash`, `heart`, `star`,
  `shield`, `diamond`
- **Editing / actions:** `plus`, `floppy-disk`, `copy`,
  `trash-simple`, `faders`, `palette`, `sun-dim`, `moon-stars`,
  `play`, `stop`, `cursor-click`, `trend-up`, `circle`, `square`,
  `circles-three`

If you need a phosphor icon that isn't checked in here, download it
from [phosphoricons.com](https://phosphoricons.com/) (regular weight,
SVG export) and drop it into `assets/icons/phosphor/`. **Do not**
substitute Heroicons / Lucide / Material — the line weight and corner
treatment will visibly clash.

## Logo & brand mark

The Reveric logo — "Reverie Fold" (source of truth: the repo's `assets/logo/reveric-raw.png`; vector: `assets/logo/reveric_mark.svg`):

- A sweeping **ink‑blue ribbon** (`#283B5E`) rising from lower left to
  upper right, its right edge cut straight.
- A separate **folded periwinkle shape** (`#8797D2`) tucked beneath it,
  separated from the ribbon by a thin canvas‑colored gap. Keep the gap;
  never let the two shapes touch or overlap.
- Both shapes are flat fills — no outlines, gradients or shadows.
- The **wordmark** "Reveric" set in Literata Regular with light tracking,
  roughly 1.75× the mark's width, with a hairline periwinkle divider
  centered below.

Variants in `assets/logo/`:

- `reveric_mark.svg` — square mark only, 1024×1024
- `reveric_mark_128.png` / `reveric_mark_256.png` — square mark raster
- `reveric_logo_stacked_transparent.png` / `_cream.png` — mark + wordmark
  lockup, rendered from the mark SVG and the wordmark PNG
- `reveric_app_icon_512.png` — app icon

Minimum mark size: 32px square. Wordmark minimum: 120px wide.

The logo never sits on a saturated background; surfaces should be
`canvas`, `surface`, `surface-dim`, or one of the bundled background
photographs.
