import 'package:share_plus/share_plus.dart';

import '../models/article_model.dart';

/// Wraps the native share sheet.
///
/// Auto-posting to an external destination (e.g. a Facebook Page) is not
/// implemented: it needs a Facebook Page access token and app review, which
/// are out of scope for now. `NewsPrefsDataSource.setLastAutoShared` is
/// wired up and ready for whenever that's added.
class ShareDataSource {
  Future<void> shareArticle(ArticleModel article) async {
    await SharePlus.instance.share(
      ShareParams(text: '${article.title}\n${article.link}'),
    );
  }
}
