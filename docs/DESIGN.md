# Design System: Notion-inspired Open Workspace

Planning specification for Stitch-assisted prototyping and Flutter implementation. This is not a claim that every current Notion Android screen has been measured yet.

## 1. Visual Theme & Atmosphere

A calm, compact workspace for daily writing. It feels immediate and mostly invisible while the user thinks: a quiet canvas, dense but breathable hierarchy, small controls near the work, and restrained motion. The screen carries the familiar logic of a block-based personal workspace without carrying another product’s brand.

- Density: 6/10 — everyday app balanced; mobile puts the editor first.
- Variance: 2/10 — predictable navigation and stable information placement.
- Motion: 2/10 — utility motion only; no visual spectacle.
- Visual goal: screen and interaction parity is evaluated against an approved reference ledger, one state at a time. Use the same workflow clarity, not copied logos, illustrations, content or wording.

## 2. Color Palette & Roles

- **Paper Canvas** (#FBFBFA) — main light-mode writing surface.
- **Panel Mist** (#F1F1EF) — sidebar, hover surface, selected list row.
- **Sheet White** (#FFFFFF) — popovers, menus and active editable containers.
- **Ink Graphite** (#37352F) — primary text and icons.
- **Muted Graphite** (#787774) — secondary text, metadata and empty-state hints.
- **Divider Sand** (#E9E9E7) — structural 1 px rules and input boundaries.
- **Focus Blue** (#2F6FEB) — one accent: primary action, focus ring, active selection and links.
- **Warning Amber** (#A85D00) — non-destructive warnings only.
- **Danger Red** (#D14343) — destructive confirmation and error only.

Dark mode preserves roles rather than blindly inverting colours:

- **Night Canvas** (#191919)
- **Night Panel** (#202020)
- **Night Sheet** (#252525)
- **Night Ink** (#EBEBEB)
- **Night Muted** (#9B9B9B)
- **Night Divider** (#373737)
- **Focus Blue** (#5B9DFF) for accessible dark-mode focus.

No gradients, no glow, no pure black and no decorative colour noise.

## 3. Typography Rules

- **UI and body:** Geist, Noto Sans Bengali, system sans-serif. Use Noto Sans Bengali whenever text contains Bangla.
- **Mono:** Geist Mono, Noto Sans Bengali, monospace — code blocks, timestamps, API keys, IDs and dense numeric data.
- **Page title:** 30 px mobile / 36 px desktop, weight 650, line height 1.16, letter spacing -0.02 em.
- **Headings:** H1 24 px / 650; H2 20 px / 620; H3 16 px / 620.
- **Editor body:** 16 px, line height 1.62, readable column max 720 px. Compact-density option may use 15 px.
- **Metadata:** 13 px, never below 12 px.
- **Bangla gate:** test conjuncts, vowel signs, punctuation, English/Bangla mixing, emoji, pasted Unicode and Android IME composition. A fallback font must not change line height mid-paragraph.
- **Banned:** Inter, generic serif typography, all-caps controls for ordinary actions and oversized marketing headings inside the app.

## 4. Information Architecture

### Desktop

- A 264 px resizable left sidebar: workspace switcher, search, inbox, favorites, private/shared page tree, trash and settings.
- A 48 px top bar: sidebar toggle, breadcrumb/page history, sync state and page actions.
- Main editor is left-aligned in the available work area; default readable text column is 720 px. Databases may expand to 1,400 px.
- A right utility panel is opt-in for backlinks, page properties, history or later features.
- Keyboard shortcuts always have visible menu equivalents. Hover controls are never the only way to act.

### Mobile

- Top bar: sidebar trigger, contextual page title/breadcrumb, sync state and overflow.
- Sidebar opens as a full-height sheet.
- Editor receives the screen; block actions live in a bottom sheet or selected-block toolbar.
- Bottom navigation is limited to stable top-level destinations: Home, Search, New Page, Inbox and Settings.
- Every touch target is at least 44 x 44 px.
- Ordinary pages never horizontally scroll. Wide database tables scroll inside a dedicated table region with persistent first column.

## 5. Component Stylings

### Navigation and page tree

- Rows are 28–32 px tall on desktop and 44 px touch targets on mobile.
- Current page uses Panel Mist fill and Ink Graphite; no large rounded card.
- Disclosure chevrons have a separate hit target. Drag indicator appears only during reordering.
- Page icon is optional; the system never adds placeholder emoji.

### Editor blocks

- Paragraph blocks are visually unboxed.
- Desktop hover shows a low-contrast drag handle and block actions to the left without shifting text. Mobile long-press opens selection/action controls.
- Slash menu is compact, searchable and grouped by task.
- Checklist, quote, code, callout, divider, image and database blocks have distinct semantics without decorative cards.
- Code has role-aware fill, horizontal scroll only inside code, copy button and accessible language label.
- Images load with exact-size skeletons; a failed image shows inline error and retry.

### Inputs, menus and databases

- Inline title and paragraph editing have no permanent border.
- Property inputs use a light border only when focused or hovered.
- Menus use 8 px radius, 1 px Divider Sand, short soft elevation and 8 px internal padding.
- Buttons are compact 28–32 px desktop / 44 px mobile. Primary uses Focus Blue; secondary stays neutral.
- Table is the primary database view: sticky header, readable cells, explicit empty/loading state. Board, calendar and gallery are alternate views of the same records.

### System states

- **Loading:** skeleton matching the actual page/tree/table layout.
- **Empty:** one useful action and a contextual project-owned illustration.
- **Offline:** quiet status chip; local editing remains available.
- **Sync conflict:** dedicated review screen shows both versions, context and keep/merge actions.
- **Destructive action:** clear consequence, affected-item count and recovery window.

## 6. Interaction and Motion

- Motion uses transform and opacity only. Default duration 120–180 ms; page/sheet transition 180–240 ms.
- Use soft deceleration for menus and sheets. No perpetual animation.
- Page tree state, selected block and drag placement update immediately. Persistence/sync happens asynchronously and is truthfully shown.
- Android keyboard must not cover the focused editor block. Scrolling keeps the active line in a safe reading zone.
- Undo/redo is available through keyboard shortcuts, editor menu and mobile action surface.
- Respect OS reduced-motion setting.

## 7. Notion-Parity Acceptance Method

For every approved reference screen, keep a private evidence ledger:

| Reference | Target platform/size | Observed state | Flutter implementation | Acceptance checks |
|---|---|---|---|---|
| Page editor | Android phone | empty/editing/keyboard | page editor | title entry, slash menu, Android back, Bangla IME |
| Page tree | Android + desktop | nested/selected/reorder | sidebar/sheet | open, close, create, move, restore |
| Search | Android + desktop | empty/results | command/search screen | keyboard focus, ranking, no-result action |
| Database | Android + desktop | table edit/filter | data view | visible fields, row editing, offline save |

Use references only from public sources or the user’s own account. Stitch can produce a prototype after the state is documented; it does not prove target behaviour has been understood.

## 8. Stitch Prompting Rules

Give Stitch one screen or one connected micro-flow per request. Every prompt includes:

1. User goal and state.
2. Target device and viewport.
3. Navigation context and available actions.
4. Components, content density, accessibility and empty/error/offline variants.
5. This document’s role colours and typography.
6. Explicit instruction to use this app’s own name/assets; no Notion logo, wording or illustration.

Reject a concept if it introduces a dashboard-card look, hero layout, large marketing copy, emoji, generic AI imagery, gradients, rounded glass panels, or motion that harms text entry.

## 9. Anti-Patterns (Banned)

- No copied Notion brand assets, logos, text, screenshots or proprietary content in the shipped app.
- No generic dashboard card grids for editor content.
- No neon blue/purple, gradients, glow shadows or glassmorphism.
- No circular page-loading spinners, inaccessible icon-only actions or unannounced offline/sync failure.
- No animation that moves layout dimensions, blocks keyboard input or obscures text selection.
- No “100% identical” claim until a named reference screen and its relevant states have been measured and passed.
