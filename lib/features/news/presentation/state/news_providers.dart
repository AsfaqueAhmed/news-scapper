import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../data/datasources/news_enrichment_data_source.dart';
import '../../data/datasources/news_supabase_data_source.dart';
import '../../data/datasources/news_prefs_data_source.dart';
import '../../data/datasources/news_remote_data_source.dart';
import '../../data/datasources/share_data_source.dart';
import '../../data/repositories/news_repository_impl.dart';
import '../../domain/repositories/news_repository.dart';
import '../../domain/usecases/compose_share_card_usecase.dart';
import '../../domain/usecases/get_cached_articles_usecase.dart';
import '../../domain/usecases/group_siblings_usecase.dart';
import '../../domain/usecases/load_share_image_usecase.dart';
import '../../domain/usecases/mark_article_read_usecase.dart';
import '../../domain/usecases/refresh_articles_usecase.dart';
import '../../domain/usecases/share_composed_card_usecase.dart';
import '../../domain/usecases/subscribe_to_updates_usecase.dart';
import 'news_notifier.dart';
import 'news_state.dart';

final newsSupabaseDataSourceProvider = Provider<NewsSupabaseDataSource>(
  (ref) => NewsSupabaseDataSource(ref.watch(supabaseClientProvider)),
);

final newsRemoteDataSourceProvider = Provider<NewsRemoteDataSource>(
  (ref) => NewsRemoteDataSource(ref.watch(httpClientProvider)),
);

final newsEnrichmentDataSourceProvider = Provider<NewsEnrichmentDataSource>(
  (ref) => NewsEnrichmentDataSource(ref.watch(supabaseClientProvider)),
);

final newsPrefsDataSourceProvider =
    Provider<NewsPrefsDataSource>((ref) => NewsPrefsDataSource());

final shareDataSourceProvider = Provider<ShareDataSource>(
  (ref) => ShareDataSource(ref.watch(httpClientProvider)),
);

final newsRepositoryProvider = Provider<NewsRepository>(
  (ref) => NewsRepositoryImpl(
    ref.watch(newsSupabaseDataSourceProvider),
    ref.watch(newsRemoteDataSourceProvider),
    ref.watch(newsEnrichmentDataSourceProvider),
    ref.watch(newsPrefsDataSourceProvider),
    ref.watch(shareDataSourceProvider),
  ),
);

final getCachedArticlesUseCaseProvider = Provider<GetCachedArticlesUseCase>(
  (ref) => GetCachedArticlesUseCase(ref.watch(newsRepositoryProvider)),
);

final refreshArticlesUseCaseProvider = Provider<RefreshArticlesUseCase>(
  (ref) => RefreshArticlesUseCase(ref.watch(newsRepositoryProvider)),
);

final markArticleReadUseCaseProvider = Provider<MarkArticleReadUseCase>(
  (ref) => MarkArticleReadUseCase(ref.watch(newsRepositoryProvider)),
);

final loadShareImageUseCaseProvider = Provider<LoadShareImageUseCase>(
  (ref) => LoadShareImageUseCase(ref.watch(newsRepositoryProvider)),
);

final composeShareCardUseCaseProvider = Provider<ComposeShareCardUseCase>(
  (ref) => ComposeShareCardUseCase(ref.watch(newsRepositoryProvider)),
);

final shareComposedCardUseCaseProvider = Provider<ShareComposedCardUseCase>(
  (ref) => ShareComposedCardUseCase(ref.watch(newsRepositoryProvider)),
);

final groupSiblingsUseCaseProvider =
    Provider<GroupSiblingsUseCase>((ref) => GroupSiblingsUseCase());

final subscribeToUpdatesUseCaseProvider = Provider<SubscribeToUpdatesUseCase>(
  (ref) => SubscribeToUpdatesUseCase(ref.watch(newsRepositoryProvider)),
);

final newsNotifierProvider =
    NotifierProvider<NewsNotifier, NewsState>(NewsNotifier.new);
