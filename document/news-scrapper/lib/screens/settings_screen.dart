import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/news_source.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _tokenController;
  bool _tokenVisible = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _tokenController = TextEditingController(text: settings.openRouterToken ?? '');
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

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
                context.read<SettingsProvider>().setOpenRouterToken(value.trim()),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context
                  .read<SettingsProvider>()
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
    final settings = context.read<SettingsProvider>();

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
              settings.addSource(name, url);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final NewsSource source;

  const _SourceTile({required this.source});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(source.name),
        subtitle: Text(source.feedUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: Switch(
          value: source.enabled,
          onChanged: (value) =>
              context.read<SettingsProvider>().toggleSource(source, value),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => context.read<SettingsProvider>().removeSource(source.id),
        ),
      ),
    );
  }
}
