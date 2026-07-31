import 'package:share_plus/share_plus.dart';

import '../models/article.dart';
import 'settings_service.dart';

/// Wraps the native share sheet and records when the user last shared an
/// article, for display on the dashboard.
///
/// Auto-posting to an external destination (e.g. a Facebook Page) is not
/// implemented: it needs a Facebook Page access token and app review, which
/// are out of scope for now. `SettingsService.setLastAutoShared` is wired
/// up and ready for whenever that's added.
class ShareService {
  Future<void> shareArticle(Article article) async {
    await SharePlus.instance.share(
      ShareParams(text: '${article.title}\n${article.link}'),
    );
    await SettingsService.instance.setLastShared(DateTime.now(), article.title);
  }
}
