import 'package:flutter/material.dart';

import '../models.dart';
import '../services/catalog.dart';
import '../services/translate.dart';
import '../store.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _store = LibraryStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addFeed() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add OPDS catalog'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Feed URL',
                  hintText: 'https://example.org/opds?q={query}',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Any OPDS catalog works. Put {query} where the search terms belong; '
                'without it the whole feed is fetched and filtered on the device.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final name = nameController.text.trim();
    final url = urlController.text.trim();
    nameController.dispose();
    urlController.dispose();

    if (ok != true || url.isEmpty) return;
    await _store.addCustomFeed(
      CustomFeed(
        id: newId(),
        name: name.isEmpty ? (Uri.tryParse(url)?.host ?? 'Custom catalog') : name,
        url: url,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _store.stats;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(pinned: true, title: Text('Settings')),
          SliverList(
            delegate: SliverChildListDelegate([
              _Section(
                title: 'Appearance',
                children: [
                  RadioGroup<AppTheme>(
                    groupValue: _store.theme,
                    onChanged: (v) {
                      if (v != null) _store.setTheme(v);
                    },
                    child: Column(
                      children: [
                        for (final t in AppTheme.values)
                          RadioListTile<AppTheme>(
                            value: t,
                            title: Text(t.label),
                            subtitle: Text(t.blurb),
                            secondary: _ThemeSwatch(theme: t),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              _Section(
                title: 'Reading',
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.swap_vert),
                    title: const Text('Vertical scrolling'),
                    subtitle: Text(
                      _store.readerScrollVertical
                          ? 'Pages scroll up and down'
                          : 'Pages turn left and right',
                    ),
                    value: _store.readerScrollVertical,
                    onChanged: _store.setReaderScrollVertical,
                  ),
                  ListTile(
                    leading: const Icon(Icons.brush_outlined),
                    title: const Text('Highlight colour'),
                    trailing: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Color(_store.highlightColor | 0xFF000000),
                        shape: BoxShape.circle,
                      ),
                    ),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (sheetContext) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final c in kHighlightColors)
                                GestureDetector(
                                  onTap: () {
                                    _store.setHighlightColor(c);
                                    Navigator.pop(sheetContext);
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Color(c | 0xFF000000),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _store.highlightColor == c
                                            ? theme.colorScheme.onSurface
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.translate),
                    title: const Text('Translate into'),
                    subtitle: Text(kLanguages[_store.targetLang] ?? _store.targetLang),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (sheetContext) => DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: 0.6,
                        builder: (context, controller) => RadioGroup<String>(
                          groupValue: _store.targetLang,
                          onChanged: (v) {
                            if (v != null) _store.setTargetLang(v);
                            Navigator.pop(sheetContext);
                          },
                          child: ListView(
                            controller: controller,
                            children: [
                              for (final e in kLanguages.entries)
                                RadioListTile<String>(
                                  value: e.key,
                                  title: Text(e.value),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              _Section(
                title: 'Sources',
                subtitle:
                    'Libread installs books from these open catalogs. Add any other '
                    'OPDS feed you have the right to use.',
                children: [
                  for (final s in CatalogService.builtIn)
                    ListTile(
                      leading: const Icon(Icons.public),
                      title: Text(s.name),
                      subtitle: Text(s.blurb),
                    ),
                  for (final f in _store.customFeeds)
                    ListTile(
                      leading: const Icon(Icons.rss_feed),
                      title: Text(f.name),
                      subtitle: Text(f.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _store.removeCustomFeed(f.id),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: OutlinedButton.icon(
                      onPressed: _addFeed,
                      icon: const Icon(Icons.add),
                      label: const Text('Add OPDS catalog'),
                    ),
                  ),
                ],
              ),

              _Section(
                title: 'Library',
                children: [
                  ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('Your reading'),
                    subtitle: Text(
                      '${stats.books} books · ${stats.finished} finished · '
                      '${stats.marks} highlights · ${stats.notes} notes · '
                      '${stats.minutes >= 60 ? '${stats.minutes ~/ 60}h ${stats.minutes % 60}m' : '${stats.minutes}m'} read',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('About Libread'),
                    subtitle: const Text(
                      'An offline-first reader for PDF and EPUB, with highlights, '
                      'translation and notes.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 90),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// A three-dot preview of what each theme looks like.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final (bg, a, b) = switch (theme) {
      AppTheme.night => (TokyoNight.nightBg, TokyoNight.blue, TokyoNight.magenta),
      AppTheme.storm => (TokyoNight.stormBg, TokyoNight.blue, TokyoNight.green1),
      AppTheme.day => (TokyoNight.dayBg, TokyoNight.dayBlue, TokyoNight.dayMagenta),
      AppTheme.system => (TokyoNight.nightBg, TokyoNight.dayBg, TokyoNight.blue),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: a, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: b, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}
