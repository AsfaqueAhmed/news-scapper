# Share Templates Batch 2 — Design

## Goal

Add 6 new share templates to `shareTemplates` ([share_card_renderer.dart](../../../lib/features/news/data/share/share_card_renderer.dart)), matching the visual style of 8 reference designs the user supplied. Per user decision during brainstorming, the 8 references collapse into:

- **2 already covered**, no new template: Editorial (matches the EMT/ambulance reference) and Minimal (matches the dark-minimal reference, minus per-word keyword highlighting, which isn't reliably derivable from arbitrary real headlines).
- **6 new templates**: Field Report, Impact, Special Report, Alert, Update, Highlight.

Dropped from every reference per user decision: social icon rows, website URL, "Read More" links, "Source: url" bylines, vertical side text, quote-bubble icon, "..." menu.

## Global change: meta line shows post date, not relative time

Per user decision, share-card meta text changes from `"Source Name · 2 hours ago"` to `"Source Name · Aug 2, 2026"` — an absolute date, not relative time. This applies to **all** templates (existing and new), since it's the shared `metaText` string built before calling `ShareCardRenderer.paint`.

Add `postDate(DateTime time)` to [date_format.dart](../../../lib/core/utils/date_format.dart) using `intl`'s `DateFormat` (already a direct pubspec dependency). Format: `'MMM d, y'` (e.g. "Aug 2, 2026").

Only the two share-card call sites switch from `relativeTime` to `postDate`:
- `share_data_source.dart:61` (`composeCard`)
- `share_preview_screen.dart:304` (`_templateCard`)

`relativeTime` itself is untouched and stays in use elsewhere (dashboard "Updated Xh ago", article list freshness, etc.) — those are unrelated to share cards and out of scope.

## Bug fix: `ShareTemplate.paletteColor` was never applied

While tracing how a new template's fixed color would reach the renderer, found that `_SharePreviewScreenState._configFor` never sets `paletteColor` on the `ShareCardConfig` it builds — it only sets `titlePosition`, `showTitle`, `showBadge`. This means `ShareCardConfig.paletteColor` is always `null` in the running app today, so `ShareCardRenderer.paint`'s `palette = config.paletteColor ?? accentColor` **always** falls back to the article source's accent color. "Breaking Red" has silently never actually forced red — it's been rendering in whatever color the source's `sourceAccent()` returns.

This must be fixed as part of this work, since several new templates below depend on their fixed palette color actually reaching the canvas. Fix: `_configFor` adds `paletteColor: template.paletteColor`.

## New shared helpers in `ShareCardRenderer`

Two small drawing helpers get extracted, both reused by multiple templates below (avoids duplicating circle-clip / pill-badge code across 4+ draw methods):

- **`_drawCircularLogo(canvas, center, radius, logo, {required fallbackColor})`** — draws the app logo clipped to a circle at the given center/radius (falls back to the old colored-circle-with-"F" if `logo` is null), plus the white stroke ring. `_drawBrandMark` (existing corner mark) becomes a thin wrapper around this; `_drawHighlight` (new, below) reuses it at a larger size for its bottom-center logo.
- **`_drawPill(canvas, label, color, {required anchor, required centered})`** — draws a filled, fully-rounded pill (rounded-rect with radius = height/2) with white bold uppercase label text, positioned either top-left at `anchor` or centered on `anchor`. Returns the drawn `Rect` so callers can lay out content relative to it. Reused by the ribbon's new pill banner shape, Field Report's over-photo badge, and Update's centered pill.

## `TitlePosition.ribbon` gets a banner shape option

New enum:

```dart
enum BannerShape { notch, pill }
```

New field on both `ShareCardConfig` and `ShareTemplate`: `bannerShape` (default `BannerShape.notch` — existing "Breaking Red" template is visually unchanged). `_drawRibbon` branches: `notch` keeps today's diagonal-cut banner exactly as-is; `pill` draws the badge via the new `_drawPill` helper instead, inset from the left edge by the same 48px padding used elsewhere (rather than flush to the edge like the notch cut).

This covers **Special Report** (red pill) and **Alert** (yellow pill) — both are the existing ribbon layout (headline + meta over a bottom scrim), just with `bannerShape: pill` and different `paletteColor`.

## Field Report (revives `TitlePosition.panel`)

`panel` exists in the enum today but has no active template and a bare-bones `_drawPanel` (title + meta only, fixed 36%-of-height band, no description). Enhancing it:

- Add `description` (rendered like Editorial's, max 3 lines) and `showBadge` params.
- The color band's height becomes content-driven (topInset + title + description-if-present + meta + bottomInset), same technique used for Editorial's card, instead of a fixed `bounds.height * 0.36`.
- When `showBadge` is true, draws a badge pill *over the photo*, above the band (via `_drawPill`), using a fixed dark color (`_nearBlack` at 85% alpha) rather than the template's palette color — this keeps the over-photo badge legible regardless of what the band's flat color is, and gives every "badge over photo, colored block below" template (Field Report today, any more added later) a consistent look.

New palette color: `_khaki = Color(0xFFC7B693)`.

## Impact (new `TitlePosition.boxedHeadline`)

A new layout: not a full-width band (that's Field Report) but a solid-color **rounded box floating** over the lower photo, sized to fit just the headline, inset from both edges by the standard 48px padding. Above the box: a dark badge pill (same style as Field Report's, reusing `_drawPill`). Below the box, directly on the photo over a bottom scrim: an optional 2-line description, then the meta line.

Reuses `_breakingRed` as its palette color (no new const).

## Update (new `TitlePosition.updatePill`)

A new layout: a pill badge (via `_drawPill`, using the template's palette color) centered horizontally, positioned in the upper-middle of the photo (`bounds.top + bounds.height * 0.3`). Below it, left-aligned over a bottom scrim: the bold headline and the meta line — no separate description (keeps this one visually distinct from Field Report/Impact/Highlight, which already use description).

Reuses `_breakingRed`.

## Highlight (new `TitlePosition.highlight`)

The most distinct new layout: full-bleed photo, no category badge. The headline is drawn with a colored "highlighter" bar behind each wrapped line (via `TextPainter.computeLineMetrics()` — draw one rect per line, inset slightly, before painting the text on top), using the template's palette color. Below that: an optional description, then the meta line, then — instead of the usual small top-right corner brand mark — the actual logo shown large (90px vs the usual 64px) and centered at the bottom, via the new `_drawCircularLogo` helper. Because Highlight draws its own big logo, `ShareCardRenderer.paint` skips the normal corner `_drawBrandMark` call specifically for `TitlePosition.highlight` (avoids showing the logo twice).

Reuses `_breakingRed`.

## Screen wiring

- `_configFor` (in [share_preview_screen.dart](../../../lib/features/news/presentation/screens/share_preview_screen.dart)) passes `paletteColor: template.paletteColor` (the bug fix above) and `bannerShape: template.bannerShape`.
- The "show/hide badge" switch's visibility condition expands from `{ribbon, card}` to `{ribbon, card, panel, boxedHeadline, updatePill}` — every template that actually draws a badge. `spotlight`, `minimal`, and `highlight` are excluded (spotlight's tag isn't wired to `showBadge` — pre-existing, out of scope; minimal and highlight have no badge at all).

## Final template list (10 total)

```dart
ShareTemplate(id: 'ribbon_red', label: 'Breaking Red', titlePosition: TitlePosition.ribbon, paletteColor: _breakingRed),
ShareTemplate(id: 'card_source', label: 'Editorial', titlePosition: TitlePosition.card),
ShareTemplate(id: 'spotlight_source', label: 'Spotlight', titlePosition: TitlePosition.spotlight),
ShareTemplate(id: 'image', label: 'Photo only', titlePosition: TitlePosition.minimal, showTitle: false),
ShareTemplate(id: 'panel_khaki', label: 'Field Report', titlePosition: TitlePosition.panel, paletteColor: _khaki),
ShareTemplate(id: 'boxed_headline', label: 'Impact', titlePosition: TitlePosition.boxedHeadline, paletteColor: _breakingRed),
ShareTemplate(id: 'ribbon_pill_red', label: 'Special Report', titlePosition: TitlePosition.ribbon, paletteColor: _breakingRed, bannerShape: BannerShape.pill),
ShareTemplate(id: 'ribbon_pill_yellow', label: 'Alert', titlePosition: TitlePosition.ribbon, paletteColor: _alertYellow, bannerShape: BannerShape.pill),
ShareTemplate(id: 'update_pill', label: 'Update', titlePosition: TitlePosition.updatePill, paletteColor: _breakingRed),
ShareTemplate(id: 'highlight', label: 'Highlight', titlePosition: TitlePosition.highlight, paletteColor: _breakingRed),
```

New palette consts: `_khaki = Color(0xFFC7B693)`, `_alertYellow = Color(0xFFE8B923)`.

## Out of scope

- No new automated tests beyond extending the existing `share_card_test.dart` loop (it already iterates `shareTemplates`, so the 6 new entries get exercised automatically for free — with and without an image, with the existing test article's description).
- No changes to Spotlight or Minimal's drawing code.
- No per-word keyword color-highlighting in any headline (not reliably derivable from real article titles).
