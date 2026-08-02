# Share Template Grid View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a grid-of-thumbnails view to the share template screen that the user can toggle to from the existing swipeable carousel, so all 13 `shareTemplates` can be scanned at once.

**Architecture:** Single-file change to `lib/features/news/presentation/screens/share_preview_screen.dart`. Add a `_ViewMode` enum (`carousel` | `grid`) as screen state, an `AppBar` icon button to toggle it, and a `_buildGrid()` method alongside the existing carousel builder. Both views read/write the same `_currentPage` int as the selected template index, so the bottom Share button and label work unchanged regardless of view.

**Tech Stack:** Flutter (Dart), `flutter_riverpod` (state already wired via `ConsumerStatefulWidget`), no new packages.

## Global Constraints

- No new automated tests — verification is `flutter analyze`, the existing test suite (regression only), and manual run-through in the app. (Spec: [2026-08-02-share-template-grid-view-design.md](../specs/2026-08-02-share-template-grid-view-design.md), "Out of scope")
- Default view on screen open is `carousel` — unchanged from current behavior.
- `ShareCardRenderer` / `_ShareCardPainter` are not modified — both views reuse them as-is.

---

### Task 1: Add grid view toggle to the share preview screen

**Files:**
- Modify: `lib/features/news/presentation/screens/share_preview_screen.dart` (full rewrite of the file's contents below `class _ShareCardPainter` stays untouched)

**Interfaces:**
- Consumes: `ShareCardRenderer.aspectRatio` (static double), `ShareTemplate.label`/`titlePosition`/`showTitle` (from `shareTemplates` list), `sourceAccent(String sourceId)` (from `core/theme/app_theme.dart`), `relativeTime(DateTime)` (from `core/utils/date_format.dart`) — all pre-existing, unchanged.
- Produces: nothing consumed by other files — `SharePreviewScreen` is a leaf screen pushed by navigation elsewhere in the app; its public API (constructor `SharePreviewScreen({required Article article})`) is unchanged.

- [ ] **Step 1: Replace the file contents**

Replace the entire contents of `lib/features/news/presentation/screens/share_preview_screen.dart` with:

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_format.dart';
import '../../data/share/share_card_renderer.dart';
import '../../domain/entities/article.dart';
import '../state/news_providers.dart';

enum _ViewMode { carousel, grid }

/// Lets the user browse ready-made share templates -- as a swipeable
/// carousel or a scannable grid -- and share whichever one is selected.
class SharePreviewScreen extends ConsumerStatefulWidget {
  final Article article;

  const SharePreviewScreen({super.key, required this.article});

  @override
  ConsumerState<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends ConsumerState<SharePreviewScreen> {
  late PageController _pageController;

  ui.Image? _image;
  bool _loadingImage = true;
  bool _sharing = false;
  int _currentPage = 0;
  _ViewMode _viewMode = _ViewMode.carousel;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _pageController = _newPageController(_currentPage);
  }

  PageController _newPageController(int initialPage) {
    final controller = PageController(viewportFraction: 0.82, initialPage: initialPage);
    controller.addListener(() {
      final page = controller.page?.round() ?? 0;
      if (page != _currentPage) setState(() => _currentPage = page);
    });
    return controller;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final image = await ref.read(newsNotifierProvider.notifier).loadShareImage(widget.article);
    if (!mounted) return;
    setState(() {
      _image = image;
      _loadingImage = false;
    });
  }

  double _currentPageOffset() {
    if (_pageController.hasClients && _pageController.position.haveDimensions) {
      return _pageController.page ?? _currentPage.toDouble();
    }
    return _currentPage.toDouble();
  }

  void _toggleViewMode() {
    setState(() {
      if (_viewMode == _ViewMode.carousel) {
        _viewMode = _ViewMode.grid;
      } else {
        _viewMode = _ViewMode.carousel;
        _pageController.dispose();
        _pageController = _newPageController(_currentPage);
      }
    });
  }

  void _selectTemplate(int index) {
    setState(() => _currentPage = index);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final template = shareTemplates[_currentPage];
      final config = ShareCardConfig(
        titlePosition: template.titlePosition,
        showTitle: template.showTitle,
      );
      final notifier = ref.read(newsNotifierProvider.notifier);
      final png = await notifier.composeShareCard(widget.article, _image, config);
      await notifier.shareComposedCard(widget.article, png);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not share this article')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = sourceAccent(widget.article.sourceId);
    final isGrid = _viewMode == _ViewMode.grid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a template'),
        actions: [
          IconButton(
            icon: Icon(isGrid ? Icons.view_carousel_rounded : Icons.grid_view_rounded),
            tooltip: isGrid ? 'Switch to carousel view' : 'Switch to grid view',
            onPressed: _loadingImage ? null : _toggleViewMode,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: _loadingImage
                  ? Center(child: CircularProgressIndicator(color: accent))
                  : isGrid
                      ? _buildGrid(accent)
                      : _buildCarousel(accent),
            ),
            const SizedBox(height: 18),
            if (!isGrid)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(shareTemplates.length, (index) {
                  final selected = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: selected ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: selected ? accent : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            const SizedBox(height: 10),
            Text(
              shareTemplates[_currentPage].label,
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: FilledButton.icon(
                onPressed: _loadingImage || _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(_sharing ? 'Sharing…' : 'Share this template'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarousel(Color accent) {
    return PageView.builder(
      controller: _pageController,
      itemCount: shareTemplates.length,
      itemBuilder: (context, index) => _buildCarouselCard(index, accent),
    );
  }

  Widget _buildCarouselCard(int index, Color accent) {
    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: _templateCard(index, accent),
    );

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        final diff = (index - _currentPageOffset()).abs().clamp(0.0, 1.0);
        final scale = 1 - diff * 0.12;
        final opacity = 1 - diff * 0.45;
        return Center(
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: card,
    );
  }

  Widget _buildGrid(Color accent) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: shareTemplates.length,
      itemBuilder: (context, index) {
        final selected = index == _currentPage;
        return GestureDetector(
          onTap: () => _selectTemplate(index),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? accent : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: _templateCard(index, accent),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                shareTemplates[index].label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? accent : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _templateCard(int index, Color accent) {
    final template = shareTemplates[index];
    return AspectRatio(
      aspectRatio: ShareCardRenderer.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _ShareCardPainter(
              image: _image,
              accentColor: accent,
              title: widget.article.title,
              metaText: '${widget.article.sourceName} · ${relativeTime(widget.article.pubDate)}',
              category: widget.article.category,
              config: ShareCardConfig(
                titlePosition: template.titlePosition,
                showTitle: template.showTitle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareCardPainter extends CustomPainter {
  final ui.Image? image;
  final Color accentColor;
  final String title;
  final String metaText;
  final String? category;
  final ShareCardConfig config;

  _ShareCardPainter({
    required this.image,
    required this.accentColor,
    required this.title,
    required this.metaText,
    required this.category,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    ShareCardRenderer.paint(
      canvas,
      size,
      image: image,
      accentColor: accentColor,
      title: title,
      metaText: metaText,
      category: category,
      config: config,
    );
  }

  @override
  bool shouldRepaint(covariant _ShareCardPainter oldDelegate) => true;
}
```

Notes on what changed vs. the original file:
- `_pageController` is now `late` and mutable (was `final`), because `_toggleViewMode` recreates it with a fresh `initialPage` when switching back to the carousel — a `PageController` can't have its `initialPage` changed after construction, and its `hasClients`/scroll position are only valid while a `PageView` using it is actually mounted (it isn't, while the grid is showing).
- The controller's page-change listener moved into a reusable `_newPageController()` factory so both `initState` and `_toggleViewMode` set it up identically.
- The old private `_buildCard` method (built one `PageView` item) is split into `_buildCarouselCard` (the padding + scale/opacity animation wrapper, carousel-only) and `_templateCard` (the bare `AspectRatio` + `ClipRRect` + `CustomPaint`, shared by both views).
- `_ShareCardPainter` is unchanged, copied verbatim.

- [ ] **Step 2: Statically verify the change**

Run: `flutter analyze lib/features/news/presentation/screens/share_preview_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run the existing test suite (regression check)**

Run: `flutter test`
Expected: All tests pass (`test/widget_test.dart` and `test/share_card_test.dart` don't touch this screen, so this just confirms the change didn't break app-wide wiring, e.g. via `app.dart` imports).

- [ ] **Step 4: Manual verification in the running app**

Run: `flutter run` (any connected device/emulator, or `-d chrome` for web)

Walk through:
1. Open an article and go to the share screen — it opens in carousel view (unchanged from today).
2. Tap the grid icon in the app bar — the screen switches to a 2-column grid of all 13 templates; the template that was centered in the carousel has a colored border around it.
3. Tap a different thumbnail — its border becomes highlighted, the previous one's border disappears, and the label above the Share button updates to the newly-tapped template's name.
4. Tap the carousel icon in the app bar — the screen switches back to the carousel, centered on whichever template was selected in the grid.
5. Tap "Share this template" from both grid mode and carousel mode at least once — confirm the OS share sheet opens (or, on a device without share targets configured, that no error snackbar appears) and that it's sharing the currently-selected template (spot check by comparing the composed image's layout to the selected template's `titlePosition`).

- [ ] **Step 5: Commit**

```bash
git add lib/features/news/presentation/screens/share_preview_screen.dart
git commit -m "$(cat <<'EOF'
Add grid view toggle to the share template screen

Lets users scan all templates as a 2-column thumbnail grid instead of
swiping through them one at a time, while keeping the carousel as the
default view.
EOF
)"
```
