# Share Template Grid View — Design

## Goal

[SharePreviewScreen](../../../lib/features/news/presentation/screens/share_preview_screen.dart) currently shows the 13 entries in `shareTemplates` ([share_card_renderer.dart](../../../lib/features/news/data/share/share_card_renderer.dart)) as a swipeable, one-at-a-time carousel (`PageView`, 82% viewport). Swiping through 13 templates one by one is slow. Add a grid view the user can switch to, showing all templates as thumbnails at once, while keeping the carousel as the default.

## View switching

- Add a `_ViewMode { carousel, grid }` enum to `_SharePreviewScreenState`. Default: `carousel` (unchanged existing behavior).
- An `IconButton` in the `AppBar.actions` toggles the mode:
  - In carousel mode, shows `Icons.grid_view_rounded` (tap → switch to grid).
  - In grid mode, shows `Icons.view_carousel_rounded` (tap → switch to carousel).
- `_currentPage` remains the single source of truth for "which template is selected," shared by both views. Neither view owns a separate selection state.
- Switching *carousel → grid*: no animation needed, the grid just renders with the current selection highlighted.
- Switching *grid → carousel*: call `_pageController.jumpToPage(_currentPage)` (no animation) so the carousel opens centered on whatever was selected in the grid.

## Grid view UI

- `GridView.builder`, 2 columns (`SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2)`), scrollable, in the same `Expanded` slot the `PageView` occupies today.
- Each cell reuses the existing `_ShareCardPainter` / `ShareCardRenderer.paint` unchanged (it already scales to any canvas size) inside an `AspectRatio(aspectRatio: ShareCardRenderer.aspectRatio)`, plus the template's `label` as a caption below the thumbnail, styled like the current carousel's label text.
- The selected cell (`index == _currentPage`) gets a colored border ring (source accent color, ~3px, rounded to match the card's `BorderRadius.circular(20)`) so the active pick is visually obvious.
- Tapping any cell just updates the selection: `setState(() => _currentPage = index)`. No navigation, no view switch.

## Bottom bar behavior

- The bottom `FilledButton` ("Share this template") is unchanged: it always shares `shareTemplates[_currentPage]`, regardless of which view is active.
- Carousel mode: keep today's paging dots + label text under the carousel.
- Grid mode: hide the paging dots (nothing is "paging" — selection isn't tied to scroll position). Keep the label text showing the currently-selected template's name above the Share button, so the user always sees what they're about to share.

## Out of scope

- No persistence of the chosen view mode across app sessions — it always resets to carousel when the screen opens.
- No new automated tests. [share_card_test.dart](../../../test/share_card_test.dart) tests the renderer/painter directly and is unaffected since `ShareCardRenderer` itself doesn't change. Verification is manual: run the app, toggle grid ↔ carousel, confirm selection carries over both directions, confirm Share always sends the currently-selected template's config.
