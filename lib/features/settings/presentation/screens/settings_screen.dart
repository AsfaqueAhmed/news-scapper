import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/news_source.dart';
import '../state/settings_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _tokenController;
  bool _tokenVisible = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsNotifierProvider);
    _tokenController = TextEditingController(text: settings.openRouterToken ?? '');
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('OpenRouter API token', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Used to categorize articles and group the same story across sources.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenController,
            obscureText: !_tokenVisible,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'sk-or-v1-...',
              suffixIcon: IconButton(
                icon: Icon(_tokenVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
              ),
            ),
            onSubmitted: (value) =>
                ref.read(settingsNotifierProvider.notifier).setOpenRouterToken(value.trim()),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => ref
                  .read(settingsNotifierProvider.notifier)
                  .setOpenRouterToken(_tokenController.text.trim()),
              child: const Text('Save token'),
            ),
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('News sources', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add source',
                onPressed: () => _showAddSourceDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...settings.sources.map((source) => _SourceTile(source: source)),
        ],
      ),
    );
  }

  Future<void> _showAddSourceDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final notifier = ref.read(settingsNotifierProvider.notifier);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add RSS source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'RSS feed URL'),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              if (name.isEmpty || url.isEmpty) return;
              notifier.addSource(name, url);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends ConsumerWidget {
  final NewsSource source;

  const _SourceTile({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(source.name),
        subtitle: Text(source.feedUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: Switch(
          value: source.enabled,
          onChanged: (value) =>
              ref.read(settingsNotifierProvider.notifier).toggleSource(source, value),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () =>
              ref.read(settingsNotifierProvider.notifier).removeSource(source.id),
        ),
      ),
    );
  }
}
