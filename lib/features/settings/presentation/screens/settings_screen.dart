import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SectionHeader(icon: Icons.auto_awesome_rounded, label: 'AI enrichment'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OpenRouter API token', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Used to categorize articles and group the same story across sources.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    obscureText: !_tokenVisible,
                    decoration: InputDecoration(
                      hintText: 'sk-or-v1-...',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _tokenVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        ),
                        onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
                      ),
                    ),
                    onSubmitted: (value) => ref
                        .read(settingsNotifierProvider.notifier)
                        .setOpenRouterToken(value.trim()),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () => ref
                          .read(settingsNotifierProvider.notifier)
                          .setOpenRouterToken(_tokenController.text.trim()),
                      child: const Text('Save token'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionHeader(icon: Icons.rss_feed_rounded, label: 'News sources'),
              IconButton.filledTonal(
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Add source',
                onPressed: () => _showAddSourceDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < settings.sources.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _SourceTile(source: settings.sources[i]),
                ],
              ],
            ),
          ),
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
            const SizedBox(height: 12),
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _SourceTile extends ConsumerWidget {
  final NewsSource source;

  const _SourceTile({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = sourceAccent(source.id);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      ),
      title: Text(source.name),
      subtitle: Text(source.feedUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: source.enabled,
            onChanged: (value) =>
                ref.read(settingsNotifierProvider.notifier).toggleSource(source, value),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () =>
                ref.read(settingsNotifierProvider.notifier).removeSource(source.id),
          ),
        ],
      ),
    );
  }
}
