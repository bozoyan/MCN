---
name: "Reveric"
description: "A warm, literary product UI for AI-assisted long-form fiction writing."
colors:
  canvas: "#FFFBF5"
  surface: "#FCFAF6"
  surface-dim: "#F5F0E8"
  surface-container: "#F5F1EB"
  surface-container-high: "#FAF6F0"
  border: "#E0D8CC"
  border-subtle: "#E8E2D8"
  border-input: "#E0D6CC"
  text-primary: "#2C2418"
  text-secondary: "#4A3F35"
  text-muted: "#8A7D6B"
  text-subtle: "#9E9484"
  accent: "#8B7355"
  accent-warm: "#C4956A"
  accent-amber: "#F6AD55"
  selected: "#E8E0D4"
  hover: "#EDE7DD"
  deletion-bg: "#FDE8E8"
  deletion-border: "#C53030"
  addition-bg: "#E8FDE8"
  addition-border: "#2F855A"
  warning-bg: "#FEF3C7"
  warning-text: "#D97706"
  blockquote-border: "#D4A574"
  on-accent: "#FFFBF5"
typography:
  display:
    fontFamily: "Georgia, serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.3
  heading:
    fontFamily: "Georgia, serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Georgia, serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.75
  body-small:
    fontFamily: "Georgia, serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  ui:
    fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.4
  ui-small:
    fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.4
  ui-tiny:
    fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1.3
rounded:
  small: "4px"
  medium: "6px"
  large: "8px"
  xl: "10px"
  x2l: "12px"
  full: "14px"
  pill: "16px"
  button: "8px"
spacing:
  xxs: "4px"
  xs: "6px"
  sm: "8px"
  md: "10px"
  lg: "12px"
  xl: "14px"
  x2l: "16px"
  x3l: "20px"
  x4l: "24px"
  x5l: "28px"
  x6l: "40px"
  editor-padding-h: "72px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.button}"
    padding: "0 16px"
    height: "36px"
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-secondary}"
    rounded: "{rounded.button}"
    padding: "0 16px"
    height: "36px"
  input:
    backgroundColor: "{colors.surface-container-high}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.large}"
    padding: "10px 12px"
  panel:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.large}"
    padding: "24px"
---

# Design System: Reveric

## 1. Overview

**Creative North Star: "The Cartographer's Desk"**

Reveric is a product interface for long-form writing, so the design serves repeated concentration rather than first-impression spectacle. The surface should feel like a careful desk for planning, drafting, revising, and consulting AI agents: warm, legible, structured, and quiet.

The default visual language is literary and cartographic. Parchment-like surfaces, sepia ink, aged brass accents, and Georgia text create a manuscript atmosphere, while compact sans-serif UI controls keep management workflows precise.

The system rejects generic SaaS polish, neon AI branding, glassmorphism, purple-blue gradients, noisy card grids, and decorative dashboards. AI is present as tooling, not as the hero.

**Key Characteristics:**

- Warm parchment surfaces with low-contrast panel layering.
- Serif typography for reading and writing, system sans for controls.
- Restrained accent use for primary actions, selection, and state.
- Dense but calm management panels for providers, agents, settings, and assets.
- Standard product controls with consistent radius, spacing, and states.

## 2. Colors

The palette is warm, literary, and intentionally low-glare, built from parchment, ink, muted leather, and aged brass.

### Primary

- **Aged Brass Accent** (`#8B7355`): Primary actions, active indicators, selected controls, and meaningful icon emphasis. Use sparingly.
- **Warm Brass Accent** (`#C4956A`): Secondary warmth for avatars and supportive highlights.
- **Amber Highlight** (`#F6AD55`): AI avatar accents and small emphasis moments, not broad backgrounds.

### Neutral

- **Parchment Canvas** (`#FFFBF5`): The outermost app background.
- **Manuscript Surface** (`#FCFAF6`): Editor and primary content surfaces.
- **Dim Parchment** (`#F5F0E8`): Sidebars and secondary zones.
- **Toolbar Parchment** (`#F5F1EB`): Toolbars, title bars, and status surfaces.
- **Raised Parchment** (`#FAF6F0`): Inputs, AI panels, and elevated content containers.
- **Ink Primary** (`#2C2418`): Body copy, headings, and primary manuscript text.
- **Ink Secondary** (`#4A3F35`): Labels, sidebar copy, and quieter controls.
- **Muted Ink** (`#8A7D6B`): Hints, metadata, inactive icons, and placeholder-like copy.
- **Subtle Ink** (`#9E9484`): Timestamps, word counts, and low-priority metadata.
- **Panel Border** (`#E0D8CC`): Primary dividers between major regions.
- **Subtle Border** (`#E8E2D8`): Internal dividers and quiet outlines.
- **Input Border** (`#E0D6CC`): Input, card, dropdown, and field borders.

### Semantic

- **Deletion Red** (`#C53030`) and **Deletion Wash** (`#FDE8E8`): Destructive confirmations and deletion diffs.
- **Addition Green** (`#2F855A`) and **Addition Wash** (`#E8FDE8`): Addition diffs and positive confirmations.
- **Warning Amber** (`#D97706`) and **Warning Wash** (`#FEF3C7`): Validation warnings, caution copy, and warning icons.
- **Blockquote Brass** (`#D4A574`): Markdown blockquote treatment and literary annotation accents.

### Named Rules

**The Writer-First Rule.** Accent color is for action and state, not decoration. Most screens should be carried by neutral surfaces and text hierarchy.

**The Warm Neutral Rule.** Do not introduce stark black or pure white into product surfaces. Use the theme's ink and parchment tokens.

## 3. Typography

**Display Font:** Georgia, with serif fallback.
**Body Font:** Georgia, with serif fallback.
**Label/Control Font:** Platform system sans-serif.

**Character:** The type system separates manuscript from mechanism. Georgia gives chapters, summaries, and prose a literary rhythm; system sans keeps controls, labels, tabs, and metadata compact and scannable.

### Hierarchy

- **Display** (700, 28px, 1.3): Page titles and primary panel headings. Use inside content surfaces, not dense rows.
- **Heading** (700, 22px, 1.3): Section headings and dialog titles.
- **Body** (400, 16px, 1.75): Long-form editor text and primary reading copy. Keep prose line length comfortable, ideally around 65 to 75 characters.
- **Body Small** (400, 14px, 1.5): Summaries, secondary prose, chat bubbles, and descriptive text.
- **UI** (400 to 600, 13px, 1.4): Labels, nav items, form controls, buttons, menus, and panel chrome.
- **UI Small** (400 to 600, 12px, 1.4): Metadata, helper text, tab labels, and validation copy.
- **UI Tiny** (500 to 600, 11px, 1.3): Badges, compact headers, and status chips.

### Named Rules

**The Manuscript vs. Mechanism Rule.** Use Georgia for authored or story-facing content. Use system sans for product controls and management UI.

**The No Fluid Type Rule.** Product UI uses fixed token sizes. Do not scale font size with viewport width.

## 4. Elevation

Reveric is flat by default. Depth is conveyed through tonal layers, borders, selected states, and spacing rather than shadows. The app should feel like stacked paper and panels, not floating glass.

### Shadow Vocabulary

- **None at rest:** Standard panels, cards, inputs, and sidebars use backgrounds plus 1px borders.
- **Modal separation:** Dialogs may use the platform Material elevation if already provided by Flutter, but custom widget surfaces should not invent shadows.
- **Interactive depth:** Hover and selected states use `hover` and `selected` colors rather than lift.

### Named Rules

**The Tonal Layer Rule.** Choose `canvas`, `surface`, `surfaceDim`, `surfaceContainer`, or `surfaceContainerHigh` before adding a border or shadow.

**The Canvas Exception.** Infinite canvases (production canvas, ideation canvas) are spatial workbenches, not stacked paper, so they may use layered glass, soft shadows, and motion. Inside a canvas view:

- **Nodes** are translucent layers with a hairline border and a large radius; media wells inside them are concentric and one step deeper. Nodes do not blur.
- **Floating chrome** (toolbar pills, zoom and tool clusters, add dock, the selected node's action bar and composer) uses backdrop blur, a hairline border, and one large, faint shadow.
- **Light and dark derive differently.** Dark canvases separate layers with slightly lighter translucent fills (shadows are invisible, so nodes get none). Light canvases separate layers with hairline borders plus a very faint shadow. Shadows are always dark ink, never a light glow.
- **Motion** is short and one-shot: about 120ms for small elements, 150ms for hover, 180ms for overlays entering, ease-out. Hover changes fill, border, and a small lift or scale, never layout. No looping, breathing, or shimmer effects.

**Chrome next to a canvas follows as needed.** The exception starts at the canvas, but it can extend to chrome that the canvas shares with neighboring views. If such chrome stayed flat, it would visibly change every time the user switched into or out of the canvas. Such chrome may use the same floating chrome treatment as the canvas when all of these hold:

- **Shared with the canvas.** The same control floats over the canvas and stays in place when the user switches to an adjacent non-canvas view, such as a top bar that switches between canvas and list views. Toolbars, headers, and dialogs that never appear over a canvas stay flat.
- **The chrome follows, not the content.** Lists, cards, and forms in non-canvas views stay flat. Content starts below the following chrome instead of scrolling under the glass.
- **Opt-in, not default.** Chrome follows only when staying flat would cause a visible jump on view switch. `.agents/rules/design-system.md` lists every chrome that currently follows. Today that is the production workspace top bar shared by the canvas, storyboard, and list views.

All values come from the canvas helpers in `lib/shared/theme/canvas_colors.dart`; `.agents/rules/design-system.md` lists the implementation rules. Everything else stays flat.

## 5. Components

### Buttons

- **Shape:** 8px radius via `RevericRadius.button`.
- **Size:** Desktop buttons are 36px tall so they line up with 36px fields; mobile buttons are 40px. A page's single main action (for example "Continue writing" on the home page) uses the 40px prominent size. Toolbars and inline row actions use the 32px compact size.
- **Primary:** `FilledButton`, `accent` background, `onAccent` foreground, 16px horizontal padding.
- **Secondary:** `OutlinedButton`, `borderInput` stroke, `textSecondary` foreground.
- **Text:** `TextButton`, transparent background, `textSecondary` foreground, 12px horizontal padding.
- **Danger:** Destructive confirmation uses `FilledButton` with `deletionBorder`; inline destructive actions use `OutlinedButton` with `warningText`.
- **Hover / Focus:** Use Flutter theme states and token colors. Do not restyle individual buttons unless the semantic role changes.

### Chips

- **Style:** Small, token-based, and restrained. Use selected state for active filters or tool selections.
- **State:** Selected chips should read as state, not decoration. Avoid saturated inactive chips.

### Cards / Containers

- **Corner Style:** 8px for repeated cards, 10 to 12px for larger framed surfaces when already established.
- **Background:** Prefer `surface`, `surfaceContainer`, or `surfaceContainerHigh` depending on layer.
- **Shadow Strategy:** No custom shadows by default.
- **Border:** 1px `borderInput` for framed tools and cards, `borderSubtle` for quieter internal structure.
- **Internal Padding:** 12 to 24px for panels and repeated items; editor content uses 72px horizontal padding.

### Inputs / Fields

- **Style:** Filled fields use `surfaceContainerHigh`, 1px `borderInput`, 8px radius, and compact UI text.
- **Focus:** Focus moves the border to `accent`.
- **Error:** Error borders and copy use `warningText` unless the action is destructive.
- **Disabled:** Disabled fields retain structure but reduce visual weight through muted text and lower-emphasis surface.

### Navigation

- **Sidebar:** 280px desktop width, `surfaceDim` background, `ui` text, `uiTiny` section labels, selected row in `selected`, hover row in `hover`.
- **Desktop Frame:** Desktop page bodies use `DesktopWindowFrame` so title-bar and platform safe areas remain consistent.
- **Mobile:** Use the same semantic tokens, but collapse structure instead of shrinking type.

### Editor And Markdown

- **Editor:** `surface` background, Georgia 16px body, 1.75 line height, 72px horizontal padding, 40px vertical padding.
- **Markdown Blockquote:** `blockquoteBorder` at 3px with 20px left padding.
- **Markdown Toolbars:** Compact icon buttons, 32px hit target, `textSecondary` default icon color.

### Agent And AI Panels

- **AI Chat Panel:** 360px desktop width, `surfaceContainerHigh` background, 300px max bubble width, 14px bubble radius.
- **Agent Avatars:** 20 to 24px in chat, 64px in profile edit headers. Use token backgrounds and borders.
- **Agent Forms:** Keep controls dense, grouped, and consistent. Prompt editors get vertical space; identity and model controls stay compact.

## 6. Do's and Don'ts

### Do:

- **Do** use `RevericTheme.colorsOf(context)` and `RevericTheme.typographyOf(context)` for widget styling.
- **Do** use `RevericSpacing`, `RevericRadius`, and `RevericSizes` instead of local magic numbers.
- **Do** keep manuscript and authored content visually dominant over side panels and AI controls.
- **Do** use `FilledButton` for save/create/confirm, `OutlinedButton` for secondary choices, and `TextButton` for cancel/link-like actions.
- **Do** keep form fields and dropdowns aligned with `revericInputDecoration`.
- **Do** preserve i18n for user-visible copy in widgets.

### Don't:

- **Don't** use hardcoded colors such as `Color(0xFF...)`, `Colors.white`, or `Colors.transparent` in product widgets when a theme token can express the role.
- **Don't** use purple-blue gradients, neon AI effects, glassmorphism, decorative metrics, or generic SaaS dashboard patterns. Canvas views, and the chrome that follows them, are the one exception for glass and motion; see The Canvas Exception in Elevation.
- **Don't** use Material `Icon(Icons.*)` for UI icons. Use `RevericIcon` and `RevericIcons`.
- **Don't** put cards inside cards or wrap every section in a decorative container.
- **Don't** use side-stripe borders, gradient text, or full-saturation accents for inactive states.
- **Don't** make AI visually louder than the writer's manuscript, outline, and story assets.
