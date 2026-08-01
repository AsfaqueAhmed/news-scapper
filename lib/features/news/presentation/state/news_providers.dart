import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../data/datasources/news_enrichment_data_source.dart';
import '../../data/datasources/news_supabase_data_source.dart';
import '../../data/datasources/news_prefs_data_source.dart';
import '../../data/datasources/news_remote_data_source.dart';
import '../../data/datasources/share_data_source.dart';
import '../../data/repositories/news_repository_impl.dart';
import '../../domain/repositories/news_repository.dart';
import '../../domain/usecases/get_cached_articles_usecase.dart';
import '../../domain/usecases/group_siblings_usecase.dart';
import '../../domain/usecases/mark_article_read_usecase.dart';
import '../../domain/usecases/refresh_articles_usecase.dart';
import '../../domain/usecases/share_article_usecase.dart';
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

final shareArticleUseCaseProvider = Provider<ShareArticleUseCase>(
  (ref) => ShareArticleUseCase(ref.watch(newsRepositoryProvider)),
);

final groupSiblingsUseCaseProvider =
    Provider<GroupSiblingsUseCase>((ref) => GroupSiblingsUseCase());

final newsNotifierProvider =
    NotifierProvider<NewsNotifier, NewsState>(NewsNotifier.new);
