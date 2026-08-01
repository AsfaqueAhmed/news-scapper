import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/news_source.dart';
import '../../domain/usecases/add_source_usecase.dart';
import '../../domain/usecases/get_openrouter_token_usecase.dart';
import '../../domain/usecases/get_sources_usecase.dart';
import '../../domain/usecases/remove_source_usecase.dart';
import '../../domain/usecases/set_openrouter_token_usecase.dart';
import '../../domain/usecases/update_source_usecase.dart';
import 'settings_providers.dart';
import 'settings_state.dart';

class SettingsNotifier extends Notifier<SettingsState> {
  late final GetSourcesUseCase _getSources;
  late final AddSourceUseCase _addSource;
  late final UpdateSourceUseCase _updateSource;
  late final RemoveSourceUseCase _removeSource;
  late final GetOpenRouterTokenUseCase _getOpenRouterToken;
  late final SetOpenRouterTokenUseCase _setOpenRouterToken;

  @override
  SettingsState build() {
    _getSources = ref.watch(getSourcesUseCaseProvider);
    _addSource = ref.watch(addSourceUseCaseProvider);
    _updateSource = ref.watch(updateSourceUseCaseProvider);
    _removeSource = ref.watch(removeSourceUseCaseProvider);
    _getOpenRouterToken = ref.watch(getOpenRouterTokenUseCaseProvider);
    _setOpenRouterToken = ref.watch(setOpenRouterTokenUseCaseProvider);
    return const SettingsState();
  }

  Future<void> load() async {
    final sources = await _getSources();
    final token = await _getOpenRouterToken();
    state = state.copyWith(sources: sources, openRouterToken: token, loaded: true);
  }

  Future<void> addSource(String name, String feedUrl) async {
    await _addSource(name, feedUrl);
    state = state.copyWith(sources: await _getSources());
  }

  Future<void> updateSource(NewsSource source) async {
    await _updateSource(source);
    state = state.copyWith(sources: await _getSources());
  }

  Future<void> toggleSource(NewsSource source, bool enabled) =>
      updateSource(source.copyWith(enabled: enabled));

  Future<void> removeSource(String id) async {
    await _removeSource(id);
    state = state.copyWith(sources: await _getSources());
  }

  Future<void> setOpenRouterToken(String? token) async {
    await _setOpenRouterToken(token);
    state = state.copyWith(
      openRouterToken: token,
      clearToken: token == null || token.isEmpty,
    );
  }
}
