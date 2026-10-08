import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/covers.dart';
import '../services/importer.dart';
import '../store.dart';
import '../widgets/book_cover.dart';
import 'epub_reader_screen.dart';
import 'marks_screen.dart';
import 'reader_screen.dart';

/// Opens the right reader for a book's format.
Future<void> openBook(BuildContext context, Book book) {
  LibraryStore.instance.updateBook(book..lastOpenedAt = DateTime.now());
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => book.format == BookFormat.epub
          ? EpubReaderScreen(book: book)
          : ReaderScreen(book: book),
    ),
  );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onDiscover});

  /// Switches the shell to the Discover tab.
  final VoidCallback onDiscover;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _store = LibraryStore.instance;
  final _searchController = TextEditingController();

  /// Books whose cover is currently being fetched.
  final Set<String> _fetchingCovers = {};

  LibraryFilter _filter = LibraryFilter.all;
  String _query = '';
  String? _tag;
  bool _importing = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  // ------------------------------------------------------------------ import

  Future<void> _importBooks() async {
    setState(() => _importing = true);
    try {
      final books = await Importer.instance.importFromDevice();
      if (books.isEmpty) return;

      _snack('Imported ${books.length} book${books.length == 1 ? '' : 's'}');
      // Every book already shows its own first page; look for the published
      // artwork in the background.
      for (final book in books) {
        unawaited(_fetchCover(book));
      }
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add from link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://…/book.epub'),
            ),
            const SizedBox(height: 12),
            Text(
              'Paste a direct link to a PDF or EPUB file.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (url == null || url.trim().isEmpty) return;
    try {
      final book = await Importer.instance.installFromUrl(url);
      if (book == null) {
        _snack('Download failed. Check the link and try again.');
      } else {
        _snack('Added "${book.title}"');
        unawaited(_fetchCover(book));
      }
    } catch (e) {
      _snack(e is FormatException ? e.message : 'Download failed: $e');
    }
  }

  /// Searches the cover catalogues, keeping the current cover on a weak match.
  Future<void> _fetchCover(Book book, {bool notifyOnFail = false}) async {
    if (_fetchingCovers.contains(book.id)) return;
    if (mounted) setState(() => _fetchingCovers.add(book.id));

    try {
      final source = await CoverService.refresh(book);
      await _store.updateBook(book);
      if (notifyOnFail) {
        _snack(source == null ? 'No cover found for "${book.title}"' : 'Cover from $source');
      }
    } catch (_) {
      if (notifyOnFail) _snack('Could not fetch a cover. Check your connection.');
    } finally {
      if (mounted) setState(() => _fetchingCovers.remove(book.id));
    }
  }

  /// Falls back to the book's own first page, ignoring the online catalogues.
  Future<void> _useOwnPage(Book book) async {
    if (mounted) setState(() => _fetchingCovers.add(book.id));
    try {
      final source = await CoverService.refresh(book, preferOnline: false);
      await _store.updateBook(book);
      _snack(source == null ? 'Could not read a cover from the file' : 'Using the book’s own art');
    } finally {
      if (mounted) setState(() => _fetchingCovers.remove(book.id));
    }
  }

  Future<void> _refreshAllCovers() async {
    final missing = _store.books.where((b) => b.coverPath == null).toList();
    final target = missing.isEmpty ? _store.books : missing;
    if (target.isEmpty) return;

    _snack('Looking for ${target.length} cover${target.length == 1 ? '' : 's'}…');
    for (final book in target) {
      await _fetchCover(book);
    }
    _snack('Covers updated');
  }

  // --------------------------------------------------------------- book menu

  Future<void> _editBook(Book book) async {
    final titleController = TextEditingController(text: book.title);
    final authorController = TextEditingController(text: book.author ?? '');
    final tagsController = TextEditingController(text: book.tags.join(', '));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit book'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: authorController,
                decoration: const InputDecoration(labelText: 'Author'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  helperText: 'Comma separated',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A correct title and author give the cover search much better results.',
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
            child: const Text('Save & find cover'),
          ),
        ],
      ),
    );

    final title = titleController.text.trim();
    final author = authorController.text.trim();
    final tags = tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    titleController.dispose();
    authorController.dispose();
    tagsController.dispose();

    if (saved != true) return;

    book.title = title.isEmpty ? book.title : title;
    book.author = author.isEmpty ? null : author;
    book.tags = tags;
    await _store.updateBook(book);
    await _fetchCover(book, notifyOnFail: true);
  }

  Future<void> _confirmDelete(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove “${book.title}”?'),
        content: const Text(
          'This deletes the imported copy and its highlights. Notes you wrote are '
          'kept in the Notes tab, and your original file is untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await _store.deleteBook(book);
  }

  void _openBookMenu(Book book) {
    showModalBottomSheet<void>(
      context: context,
      // Scroll-controlled so the full list of actions — including "Remove from
      // library" at the bottom — is always reachable and clears the phone's
      // navigation bar instead of being cut off by it.
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 68,
                    child: BookCover.of(book, radius: 8),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            book.author ?? 'Unknown author',
                            book.format.label,
                            if (book.sourceName != null) book.sourceName!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(book.favorite ? Icons.favorite : Icons.favorite_border),
              title: Text(book.favorite ? 'Remove from favorites' : 'Add to favorites'),
              onTap: () {
                Navigator.pop(sheetContext);
                _store.toggleFavorite(book);
              },
            ),
            ListTile(
              leading: Icon(
                book.finished ? Icons.restart_alt : Icons.check_circle_outline,
              ),
              title: Text(book.finished ? 'Mark as unread' : 'Mark as finished'),
              onTap: () {
                Navigator.pop(sheetContext);
                _store.toggleFinished(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmarks_outlined),
              title: const Text('Highlights & notes'),
              subtitle: Text(
                '${_store.countFor(book.id, MarkKind.highlight)} highlights · '
                '${_store.countFor(book.id, MarkKind.note)} notes',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MarksScreen(book: book)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit title, author & tags'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editBook(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_search),
              title: const Text('Find cover online'),
              subtitle: Text(
                book.coverSource == null ? 'No cover yet' : 'Current: ${book.coverSource}',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _fetchCover(book, notifyOnFail: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.crop_original),
              title: const Text('Use the book’s own first page'),
              onTap: () {
                Navigator.pop(sheetContext);
                _useOwnPage(book);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(sheetContext).colorScheme.error),
              title: Text(
                'Remove from library',
                style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(book);
              },
            ),
            const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.travel_explore),
              title: const Text('Browse online catalogs'),
              subtitle: const Text('Gutenberg, Standard Ebooks, Internet Archive, arXiv…'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onDiscover();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Import from this device'),
              subtitle: const Text('Pick PDF or EPUB files'),
              onTap: () {
                Navigator.pop(sheetContext);
                _importBooks();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Add from a link'),
              subtitle: const Text('Paste a direct PDF or EPUB URL'),
              onTap: () {
                Navigator.pop(sheetContext);
                _importFromUrl();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openSortMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<LibrarySort>(
              groupValue: _store.sort,
              onChanged: (v) {
                Navigator.pop(sheetContext);
                if (v != null) _store.setSort(v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in LibrarySort.values)
                    RadioListTile<LibrarySort>(value: s, title: Text(s.label)),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh all covers'),
              onTap: () {
                Navigator.pop(sheetContext);
                _refreshAllCovers();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final books = _store.shelf(filter: _filter, query: _query, tag: _tag);
    final continueReading = _continueReading();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _openAddMenu,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add),
        label: Text(_importing ? 'Importing…' : 'Add books'),
      ),
      body: !_store.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  title: _searching
                      ? TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Search your library…',
                            border: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        )
                      : const Text('My Library'),
                  actions: [
                    IconButton(
                      tooltip: _searching ? 'Close search' : 'Search',
                      icon: Icon(_searching ? Icons.close : Icons.search),
                      onPressed: () => setState(() {
                        _searching = !_searching;
                        if (!_searching) {
                          _searchController.clear();
                          _query = '';
                        }
                      }),
                    ),
                    IconButton(
                      tooltip: _store.gridView ? 'List view' : 'Grid view',
                      icon: Icon(_store.gridView ? Icons.view_list : Icons.grid_view),
                      onPressed: () => _store.setGridView(!_store.gridView),
                    ),
                    IconButton(
                      tooltip: 'Sort',
                      icon: const Icon(Icons.sort),
                      onPressed: _openSortMenu,
                    ),
                  ],
                ),

                if (_store.books.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _StatsStrip(store: _store)),
                  if (continueReading != null && _query.isEmpty && _filter == LibraryFilter.all)
                    SliverToBoxAdapter(
                      child: _ContinueCard(
                        book: continueReading,
                        onTap: () => openBook(context, continueReading),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _FilterBar(
                      filter: _filter,
                      tag: _tag,
                      tags: _store.allTags,
                      onFilter: (f) => setState(() => _filter = f),
                      onTag: (t) => setState(() => _tag = t),
                    ),
                  ),
                ],

                if (_store.books.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.auto_stories_outlined,
                      title: 'Your library is empty',
                      message:
                          'Install books from Project Gutenberg, Standard Ebooks, the '
                          'Internet Archive and more — or import PDFs and EPUBs you '
                          'already have.',
                      action: FilledButton.icon(
                        onPressed: widget.onDiscover,
                        icon: const Icon(Icons.travel_explore),
                        label: const Text('Find books'),
                      ),
                    ),
                  )
                else if (books.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.search_off,
                      title: 'Nothing here',
                      message: 'No book matches that search or filter.',
                    ),
                  )
                else if (_store.gridView)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        childAspectRatio: 0.52,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 20,
                      ),
                      itemCount: books.length,
                      itemBuilder: (context, i) => _BookTile(
                        book: books[i],
                        fetchingCover: _fetchingCovers.contains(books[i].id),
                        highlights: _store.countFor(books[i].id, MarkKind.highlight),
                        notes: _store.notesFor(books[i].id).length +
                            _store.countFor(books[i].id, MarkKind.note),
                        onTap: () => openBook(context, books[i]),
                        onLongPress: () => _openBookMenu(books[i]),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    sliver: SliverList.separated(
                      itemCount: books.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _BookRow(
                        book: books[i],
                        fetchingCover: _fetchingCovers.contains(books[i].id),
                        onTap: () => openBook(context, books[i]),
                        onLongPress: () => _openBookMenu(books[i]),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  /// The most recently opened book that is started but not finished.
  Book? _continueReading() {
    final candidates = _store.books
        .where((b) => b.started && !b.finished && b.lastOpenedAt != null)
        .toList()
      ..sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
    return candidates.isEmpty ? null : candidates.first;
  }
}

// ------------------------------------------------------------------- pieces

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.store});

  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    final s = store.stats;
    final theme = Theme.of(context);

    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          stat('${s.books}', 'Books'),
          stat('${s.reading}', 'Reading'),
          stat('${s.finished}', 'Finished'),
          stat('${s.marks + s.notes}', 'Notes'),
          stat(s.minutes >= 60 ? '${s.minutes ~/ 60}h' : '${s.minutes}m', 'Read'),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (book.progress * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                SizedBox(width: 56, height: 82, child: BookCover.of(book, radius: 10)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CONTINUE READING',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: book.progress,
                          minHeight: 5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        book.pageCount > 0
                            ? '$percent% · page ${book.lastPage} of ${book.pageCount}'
                            : '$percent%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.play_circle_fill, size: 34, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.tag,
    required this.tags,
    required this.onFilter,
    required this.onTag,
  });

  final LibraryFilter filter;
  final String? tag;
  final List<String> tags;
  final ValueChanged<LibraryFilter> onFilter;
  final ValueChanged<String?> onTag;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final f in LibraryFilter.values) ...[
            ChoiceChip(
              label: Text(f.label),
              selected: filter == f,
              onSelected: (_) => onFilter(f),
            ),
            const SizedBox(width: 8),
          ],
          if (tags.isNotEmpty) ...[
            const VerticalDivider(width: 17, indent: 8, endIndent: 8),
            for (final t in tags) ...[
              ChoiceChip(
                avatar: Icon(
                  Icons.tag,
                  size: 14,
                  color: tag == t
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: Text(t),
                selected: tag == t,
                onSelected: (_) => onTag(tag == t ? null : t),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.fetchingCover,
    required this.highlights,
    required this.notes,
    required this.onTap,
    required this.onLongPress,
  });

  final Book book;
  final bool fetchingCover;
  final int highlights;
  final int notes;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCover.of(book, busy: fetchingCover),
                if (book.favorite)
                  const Positioned(
                    right: 7,
                    top: 7,
                    child: _CoverBadge(icon: Icons.favorite, color: Color(0xFFF7768E)),
                  ),
                if (book.finished)
                  const Positioned(
                    left: 7,
                    top: 7,
                    child: _CoverBadge(icon: Icons.check, color: Color(0xFF9ECE6A)),
                  ),
                if (highlights > 0 || notes > 0)
                  Positioned(
                    right: 7,
                    bottom: book.started ? 11 : 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${highlights + notes}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (book.started)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                      child: CoverProgressBar(progress: book.progress),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            book.author ?? book.format.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverBadge extends StatelessWidget {
  const _CoverBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 12, color: color),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.book,
    required this.fetchingCover,
    required this.onTap,
    required this.onLongPress,
  });

  final Book book;
  final bool fetchingCover;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 76,
                child: BookCover.of(book, radius: 9, busy: fetchingCover),
              ),
              const SizedBox(width: 14),
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
                      book.author ?? 'Unknown author',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Pill(label: book.format.label, filled: true),
                        const SizedBox(width: 6),
                        if (book.started)
                          Pill(
                            label: '${(book.progress * 100).round()}%',
                            icon: Icons.trending_up,
                          )
                        else
                          const Pill(label: 'Not started'),
                        if (book.favorite) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.favorite, size: 13, color: Color(0xFFF7768E)),
                        ],
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
