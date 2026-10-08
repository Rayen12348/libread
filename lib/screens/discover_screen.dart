import 'package:flutter/material.dart';

import '../models.dart';
import '../services/catalog.dart';
import '../services/importer.dart';
import '../store.dart';
import '../widgets/book_cover.dart';
import 'library_screen.dart';

/// Searches every enabled catalog and installs books into the library.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _store = LibraryStore.instance;
  final _importer = Importer.instance;
  final _controller = TextEditingController();

  /// Source ids the user has switched off for this session.
  final Set<String> _disabled = {};

  final Map<String, List<CatalogBook>> _results = {};
  final Set<String> _pending = {};
  final Map<String, String> _errors = {};

  String _query = '';
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    _importer.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _importer.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<CatalogSource> get _sources =>
      CatalogService.all().where((s) => !_disabled.contains(s.id)).toList();

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    final sources = _sources;
    if (sources.isEmpty) {
      _snack('Enable at least one source first.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _query = query;
      _searched = true;
      _results.clear();
      _errors.clear();
      _pending
        ..clear()
        ..addAll(sources.map((s) => s.id));
    });

    await CatalogService.searchAll(
      query,
      sources,
      onResult: (source, books, error) {
        if (!mounted) return;
        setState(() {
          _pending.remove(source.id);
          if (error != null) {
            _errors[source.id] = 'Unavailable right now';
          } else {
            _results[source.id] = books;
          }
        });
      },
    );
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  /// All results, interleaved so no single catalog dominates the top.
  List<CatalogBook> get _merged {
    final lists = _results.values.where((l) => l.isNotEmpty).toList();
    final out = <CatalogBook>[];
    for (var round = 0; ; round++) {
      var added = false;
      for (final list in lists) {
        if (round < list.length) {
          out.add(list[round]);
          added = true;
        }
      }
      if (!added) break;
    }
    return out;
  }

  Future<void> _openBook(CatalogBook book) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CatalogBookSheet(book: book, onSnack: _snack),
    );
  }

  void _openSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sources',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${_sources.length} on',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                for (final s in CatalogService.all())
                  SwitchListTile(
                    value: !_disabled.contains(s.id),
                    title: Text(s.name),
                    subtitle: Text(s.blurb),
                    onChanged: (on) {
                      setSheetState(() {
                        setState(() {
                          if (on) {
                            _disabled.remove(s.id);
                          } else {
                            _disabled.add(s.id);
                          }
                        });
                      });
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = _merged;
    final busy = _pending.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Discover'),
            actions: [
              IconButton(
                tooltip: 'Sources',
                icon: const Icon(Icons.tune),
                onPressed: _openSourcePicker,
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Search title, author or subject…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
          ),

          if (_importer.tasks.isNotEmpty)
            SliverToBoxAdapter(child: _DownloadStrip(importer: _importer)),

          if (busy || _errors.isNotEmpty)
            SliverToBoxAdapter(
              child: _SourceStatus(
                sources: _sources,
                pending: _pending,
                results: _results,
                errors: _errors,
              ),
            ),

          if (!_searched)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _SuggestionPanel(
                onPick: (term) {
                  _controller.text = term;
                  _search();
                },
              ),
            )
          else if (books.isEmpty && !busy)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off,
                title: 'No results for “$_query”',
                message:
                    'Try a different spelling, search by author, or turn on more '
                    'sources from the tune icon.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              sliver: SliverList.separated(
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _CatalogTile(
                  book: books[i],
                  installed: _store.hasSourceUrl(books[i].best?.url ?? ''),
                  onTap: () => _openBook(books[i]),
                ),
              ),
            ),

          if (busy && books.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 100, top: 8),
                child: Center(
                  child: Text(
                    'Still searching ${_pending.length} more…',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- pieces

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({required this.onPick});

  final ValueChanged<String> onPick;

  static const _terms = [
    'Dostoyevsky',
    'Sherlock Holmes',
    'Jane Austen',
    'Philosophy',
    'Kafka',
    'Poetry',
    'Machine learning',
    'History of Rome',
    'Shakespeare',
    'Nietzsche',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Search these catalogs',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (final s in CatalogService.all())
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.library_books_outlined, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.blurb,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Text(
              'Try a search',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _terms)
                  ActionChip(label: Text(t), onPressed: () => onPick(t)),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.rss_feed, size: 20, color: theme.colorScheme.secondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Have another catalog? Add its OPDS feed in Settings and it is '
                      'searched here alongside the rest.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceStatus extends StatelessWidget {
  const _SourceStatus({
    required this.sources,
    required this.pending,
    required this.results,
    required this.errors,
  });

  final List<CatalogSource> sources;
  final Set<String> pending;
  final Map<String, List<CatalogBook>> results;
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final s in sources) ...[
            _chip(context, s),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, CatalogSource s) {
    final scheme = Theme.of(context).colorScheme;

    if (pending.contains(s.id)) {
      return Chip(
        avatar: const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: Text(s.name),
      );
    }
    if (errors.containsKey(s.id)) {
      return Chip(
        avatar: Icon(Icons.cloud_off, size: 14, color: scheme.error),
        label: Text(s.name),
      );
    }
    final count = results[s.id]?.length ?? 0;
    return Chip(
      avatar: Icon(
        count > 0 ? Icons.check_circle : Icons.remove_circle_outline,
        size: 14,
        color: count > 0 ? scheme.tertiary : scheme.onSurfaceVariant,
      ),
      label: Text('${s.name} · $count'),
    );
  }
}

class _DownloadStrip extends StatelessWidget {
  const _DownloadStrip({required this.importer});

  final Importer importer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = importer.tasks.take(4).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Downloads',
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (importer.active.isEmpty)
                TextButton(
                  onPressed: importer.clearFinished,
                  child: const Text('Clear'),
                ),
            ],
          ),
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: switch (t.state) {
                      DownloadState.done => Icon(
                        Icons.check_circle,
                        size: 18,
                        color: theme.colorScheme.tertiary,
                      ),
                      DownloadState.failed => Icon(
                        Icons.error_outline,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      _ => CircularProgressIndicator(strokeWidth: 2, value: t.progress),
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          switch (t.state) {
                            DownloadState.done => 'Added to your library',
                            DownloadState.failed => t.error ?? 'Failed',
                            DownloadState.processing => 'Preparing…',
                            _ => t.sizeLabel,
                          },
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t.state == DownloadState.failed
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.book,
    required this.installed,
    required this.onTap,
  });

  final CatalogBook book;
  final bool installed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                height: 78,
                child: BookCover(
                  title: book.title,
                  author: book.author,
                  imageUrl: book.coverUrl,
                  radius: 9,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        book.author ?? 'Unknown author',
                        if (book.year != null) '${book.year}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(
                          label: book.sourceName,
                          icon: Icons.public,
                          color: theme.colorScheme.secondary,
                          filled: true,
                        ),
                        for (final d in {for (final d in book.downloads) d.format})
                          Pill(label: d.label),
                        if (book.needsResolve) const Pill(label: 'PDF / EPUB'),
                        if (installed)
                          Pill(
                            label: 'In library',
                            icon: Icons.check,
                            color: theme.colorScheme.tertiary,
                            filled: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The install sheet: description, formats, and the download button.
class _CatalogBookSheet extends StatefulWidget {
  const _CatalogBookSheet({required this.book, required this.onSnack});

  final CatalogBook book;
  final void Function(String message, {SnackBarAction? action}) onSnack;

  @override
  State<_CatalogBookSheet> createState() => _CatalogBookSheetState();
}

class _CatalogBookSheetState extends State<_CatalogBookSheet> {
  bool _resolving = false;
  bool _installing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.book.needsResolve && widget.book.downloads.isEmpty) _resolve();
  }

  Future<void> _resolve() async {
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final source = CatalogService.byId(widget.book.id.split(':').first) ??
          InternetArchiveSource();
      final options = await source.resolve(widget.book);
      if (!mounted) return;
      setState(() {
        widget.book.downloads = options;
        _resolving = false;
        if (options.isEmpty) _error = 'No downloadable file for this item.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'Could not read this item’s files.';
      });
    }
  }

  Future<void> _install(DownloadOption option) async {
    setState(() => _installing = true);
    final book = await Importer.instance.install(widget.book, option);
    if (!mounted) return;

    Navigator.pop(context);
    if (book == null) {
      widget.onSnack('Download failed. Try another format or source.');
      return;
    }
    widget.onSnack(
      'Added “${book.title}”',
      action: SnackBarAction(
        label: 'Read',
        onPressed: () => openBook(context, book),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = widget.book;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.94,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                height: 128,
                child: BookCover(
                  title: book.title,
                  author: book.author,
                  imageUrl: book.coverUrl,
                  radius: 12,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      book.author ?? 'Unknown author',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(
                          label: book.sourceName,
                          icon: Icons.public,
                          color: theme.colorScheme.secondary,
                          filled: true,
                        ),
                        if (book.year != null) Pill(label: '${book.year}'),
                        if (book.language != null)
                          Pill(label: book.language!.toUpperCase()),
                        if (book.downloadCount != null)
                          Pill(
                            label: '${book.downloadCount} downloads',
                            icon: Icons.download,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (book.subjects.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final s in book.subjects) Pill(label: s, icon: Icons.tag)],
            ),
          ],

          if ((book.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              book.description!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ],

          const SizedBox(height: 22),
          Text(
            'Download',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),

          if (_resolving)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Row(
              children: [
                Expanded(
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
                TextButton(onPressed: _resolve, child: const Text('Retry')),
              ],
            )
          else
            for (final d in book.downloads)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: _installing ? null : () => _install(d),
                  child: Row(
                    children: [
                      Icon(
                        d.format == BookFormat.epub
                            ? Icons.menu_book
                            : Icons.picture_as_pdf_outlined,
                        size: 19,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.title,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (d.sizeLabel.isNotEmpty)
                              Text(
                                d.sizeLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_installing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.download, size: 19),
                    ],
                  ),
                ),
              ),

          if (book.downloads.length > 1) ...[
            const SizedBox(height: 4),
            Text(
              'EPUB reflows to your screen and is usually the better read; PDF keeps '
              'the original page layout.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
