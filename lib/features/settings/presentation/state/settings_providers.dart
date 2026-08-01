import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../data/datasources/secure_token_data_source.dart';
import '../../data/datasources/settings_supabase_data_source.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/usecases/add_source_usecase.dart';
import '../../domain/usecases/get_openrouter_token_usecase.dart';
import '../../domain/usecases/get_sources_usecase.dart';
import '../../domain/usecases/remove_source_usecase.dart';
import '../../domain/usecases/set_openrouter_token_usecase.dart';
import '../../domain/usecases/update_source_usecase.dart';
import 'settings_notifier.dart';
import 'settings_state.dart';

final settingsSupabaseDataSourceProvider = Provider<SettingsSupabaseDataSource>(
  (ref) => SettingsSupabaseDataSource(ref.watch(supabaseClientProvider)),
);

final secureTokenDataSourceProvider =
    Provider<SecureTokenDataSource>((ref) => SecureTokenDataSource());

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(
    ref.watch(settingsSupabaseDataSourceProvider),
    ref.watch(secureTokenDataSourceProvider),
  ),
);

final getSourcesUseCaseProvider = Provider<GetSourcesUseCase>(
  (ref) => GetSourcesUseCase(ref.watch(settingsRepositoryProvider)),
);

final addSourceUseCaseProvider = Provider<AddSourceUseCase>(
  (ref) => AddSourceUseCase(ref.watch(settingsRepositoryProvider)),
);

final updateSourceUseCaseProvider = Provider<UpdateSourceUseCase>(
  (ref) => UpdateSourceUseCase(ref.watch(settingsRepositoryProvider)),
);

final removeSourceUseCaseProvider = Provider<RemoveSourceUseCase>(
  (ref) => RemoveSourceUseCase(ref.watch(settingsRepositoryProvider)),
);

final getOpenRouterTokenUseCaseProvider = Provider<GetOpenRouterTokenUseCase>(
  (ref) => GetOpenRouterTokenUseCase(ref.watch(settingsRepositoryProvider)),
);

final setOpenRouterTokenUseCaseProvider = Provider<SetOpenRouterTokenUseCase>(
  (ref) => SetOpenRouterTokenUseCase(ref.watch(settingsRepositoryProvider)),
);

final settingsNotifierProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
