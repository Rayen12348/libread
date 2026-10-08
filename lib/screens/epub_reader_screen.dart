import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/epub.dart';
import '../store.dart';
import 'marks_screen.dart';
import 'notes_screen.dart';
import 'reader_common.dart';

/// Reads EPUB books one chapter at a time, with reflowing text.
class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  final _store = LibraryStore.instance;
  final _scrollController = ScrollController();

  EpubBook? _epub;
  List<EpubBlock> _blocks = const [];
  int _chapter = 0;
  bool _loading = true;

  /// Reading mode: opens with nothing but the text; a triple-tap reveals the
  /// toolbar again.
  bool _chromeVisible = false;
  String? _error;

  /// The current text selection, tracked so the toolbar actions can use it.
  String _selection = '';

  Timer? _readingTimer;
  int _secondsRead = 0;

  /// Reading comfort, persisted per device rather than per book.
  double _fontSize = 18;
  double _lineHeight = 1.7;

  @override
  void initState() {
    super.initState();
    _chapter = (widget.book.lastPage - 1).clamp(0, 1 << 30);
    _readingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _secondsRead += 10);
    _applySystemUi();
    showReadingModeHintOnce(context);
    _open();
  }

  @override
  void dispose() {
    _readingTimer?.cancel();
    _store.addReadingTime(widget.book.id, _secondsRead);
    _scrollController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Hides the system status/navigation bars while reading, restoring them with
  /// the app's own toolbar.
  void _applySystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      _chromeVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    _applySystemUi();
  }

  Future<void> _open() async {
    final epub = await EpubService.open(widget.book.filePath, widget.book.id);
    if (!mounted) return;

    if (epub == null) {
      setState(() {
        _loading = false;
        _error = 'This EPUB could not be opened. The file may be damaged or '
            'protected by DRM.';
      });
      return;
    }

    // Fill in details the catalog may not have provided.
    final book = widget.book;
    var changed = false;
    if (book.pageCount != epub.chapters.length) {
      book.pageCount = epub.chapters.length;
      changed = true;
    }
    if ((book.author == null || book.author!.isEmpty) && epub.author != null) {
      book.author = epub.author;
      changed = true;
    }
    if (changed) await _store.updateBook(book);

    setState(() {
      _epub = epub;
      _chapter = _chapter.clamp(0, epub.chapters.length - 1);
    });
    await _loadChapter(_chapter, restoreScroll: false);
  }

  Future<void> _loadChapter(int index, {bool restoreScroll = true}) async {
    final epub = _epub;
    if (epub == null) return;

    setState(() {
      _loading = true;
      _chapter = index.clamp(0, epub.chapters.length - 1);
    });

    final blocks = await EpubService.loadChapter(epub, epub.chapters[_chapter]);
    if (!mounted) return;

    setState(() {
      _blocks = blocks;
      _loading = false;
    });

    await _store.saveLastPage(widget.book.id, _chapter + 1);
    if (restoreScroll && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  // ------------------------------------------------------------- selection

  /// The toolbar shown when the reader selects text in a chapter.
  Widget _selectionToolbar(BuildContext context, SelectableRegionState state) {
    /// Runs [action] on the current selection, then dismisses the toolbar.
    ContextMenuButtonItem item(String label, void Function(String text) action) =>
        ContextMenuButtonItem(
          label: label,
          onPressed: () {
            final text = _selection;
            state.hideToolbar();
            if (text.isEmpty) return;
            action(text);
          },
        );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        item('Highlight', (t) => _saveMark(t, MarkKind.highlight)),
        item('Translate', _translate),
        item('Note', _note),
        item('To notebook', _toNotebook),
        item('Copy', (t) {
          Clipboard.setData(ClipboardData(text: t));
          _toast('Copied');
        }),
      ],
    );
  }

  /// EPUB has no page geometry, so marks carry the text and chapter only.
  Future<void> _saveMark(String text, MarkKind kind, {String? note}) async {
    await _store.addMark(
      Mark(
        id: newId(),
        bookId: widget.book.id,
        kind: kind,
        pageNumber: _chapter + 1,
        text: text,
        rects: const [],
        colorValue: _store.highlightColor,
        createdAt: DateTime.now(),
        note: note,
      ),
    );
    _toast(kind == MarkKind.note ? 'Note added' : 'Highlighted');
  }

  Future<void> _translate(String text) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TranslateSheet(
        text: text,
        onSave: (translation, lang) async {
          await _store.addMark(
            Mark(
              id: newId(),
              bookId: widget.book.id,
              kind: MarkKind.highlight,
              pageNumber: _chapter + 1,
              text: text,
              rects: const [],
              colorValue: _store.highlightColor,
              createdAt: DateTime.now(),
              translation: translation,
              targetLang: lang,
            ),
          );
          _toast('Saved translation');
        },
      ),
    );
  }

  Future<void> _note(String text) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => NoteDialog(quote: text),
    );
    if (note == null || note.trim().isEmpty) return;
    await _saveMark(text, MarkKind.note, note: note.trim());
  }

  Future<void> _toNotebook(String text) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          isNew: true,
          note: Note(
            id: newId(),
            title: '',
            body: '“$text”\n\n',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            bookId: widget.book.id,
            pageNumber: _chapter + 1,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- chrome

  void _openContents() {
    final epub = _epub;
    if (epub == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => ListView.builder(
          controller: controller,
          itemCount: epub.chapters.length,
          itemBuilder: (context, i) => ListTile(
            selected: i == _chapter,
            leading: Text(
              '${i + 1}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            title: Text(
              epub.chapters[i].title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              _loadChapter(i);
            },
          ),
        ),
      ),
    );
  }

  void _openTypeSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Text size',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Slider(
                  value: _fontSize,
                  min: 13,
                  max: 30,
                  divisions: 17,
                  label: _fontSize.round().toString(),
                  onChanged: (v) => setSheetState(() => setState(() => _fontSize = v)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Line spacing',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Slider(
                  value: _lineHeight,
                  min: 1.2,
                  max: 2.4,
                  divisions: 12,
                  label: _lineHeight.toStringAsFixed(1),
                  onChanged: (v) => setSheetState(() => setState(() => _lineHeight = v)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMarks() async {
    final page = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => MarksScreen(book: widget.book)),
    );
    if (page != null) await _loadChapter(page - 1);
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final epub = _epub;
    final chapterCount = epub?.chapters.length ?? 0;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: TripleTapDetector(
              onTripleTap: _toggleChrome,
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : _loading && _blocks.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : SelectionArea(
                      contextMenuBuilder: _selectionToolbar,
                      onSelectionChanged: (content) =>
                          _selection = (content?.plainText ?? '').trim(),
                      child: ListView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: EdgeInsets.fromLTRB(
                          22,
                          MediaQuery.of(context).padding.top + 70,
                          22,
                          120,
                        ),
                        children: [
                          if (epub != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Text(
                                epub.chapters[_chapter].title.toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ),
                          for (final block in _blocks) _blockWidget(block, theme),
                          const SizedBox(height: 28),
                          _ChapterNav(
                            hasPrevious: _chapter > 0,
                            hasNext: _chapter < chapterCount - 1,
                            onPrevious: () => _loadChapter(_chapter - 1),
                            onNext: () => _loadChapter(_chapter + 1),
                          ),
                        ],
                      ),
                    ),
            ),
          ),

          if (_chromeVisible) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ReaderTopBar(
                title: widget.book.title,
                subtitle: chapterCount == 0
                    ? 'Opening…'
                    : 'Chapter ${_chapter + 1} of $chapterCount',
                actions: [
                  IconButton(
                    tooltip: 'Contents',
                    onPressed: _openContents,
                    icon: const Icon(Icons.list),
                  ),
                  IconButton(
                    tooltip: 'Text size',
                    onPressed: _openTypeSettings,
                    icon: const Icon(Icons.text_fields),
                  ),
                  IconButton(
                    tooltip: 'Highlights & notes',
                    onPressed: _openMarks,
                    icon: const Icon(Icons.bookmarks_outlined),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ReaderBottomBar(
                page: _chapter + 1,
                pageCount: chapterCount,
                unitLabel: 'chapter',
                onSeek: (p) => _loadChapter(p - 1),
                onJump: _openContents,
                trailing: IconButton(
                  tooltip: 'Highlight colour',
                  icon: Icon(
                    Icons.brush,
                    color: Color(_store.highlightColor | 0xFF000000),
                  ),
                  onPressed: () => pickHighlightColor(context),
                ),
              ),
            ),
          ],

          if (_loading && _blocks.isNotEmpty)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  Widget _blockWidget(EpubBlock block, ThemeData theme) {
    switch (block.type) {
      case EpubBlockType.rule:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Center(
            child: Container(
              width: 60,
              height: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
        );

      case EpubBlockType.image:
        final path = block.imagePath;
        if (path == null || !File(path).existsSync()) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        );

      case EpubBlockType.heading:
        final scale = switch (block.level) {
          1 => 1.6,
          2 => 1.38,
          3 => 1.2,
          _ => 1.08,
        };
        return Padding(
          padding: EdgeInsets.only(top: block.level <= 2 ? 26 : 20, bottom: 10),
          child: Text(
            block.text,
            style: TextStyle(
              fontSize: _fontSize * scale,
              fontWeight: FontWeight.w800,
              height: 1.3,
              color: theme.colorScheme.onSurface,
            ),
          ),
        );

      case EpubBlockType.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 3),
            ),
          ),
          child: _richText(block, theme, italic: true),
        );

      case EpubBlockType.listItem:
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: _fontSize * 0.45),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _richText(block, theme)),
            ],
          ),
        );

      case EpubBlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _richText(block, theme),
        );
    }
  }

  Widget _richText(EpubBlock block, ThemeData theme, {bool italic = false}) {
    final base = TextStyle(
      fontSize: _fontSize,
      height: _lineHeight,
      color: theme.colorScheme.onSurface,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );

    return Text.rich(
      TextSpan(
        children: [
          for (final span in block.spans)
            TextSpan(
              text: span.text,
              style: TextStyle(
                fontWeight: span.bold ? FontWeight.w700 : null,
                fontStyle: span.italic ? FontStyle.italic : null,
                fontFamily: span.code ? 'monospace' : null,
                color: span.code ? theme.colorScheme.tertiary : null,
              ),
            ),
        ],
      ),
      style: base,
      textAlign: TextAlign.start,
    );
  }
}

class _ChapterNav extends StatelessWidget {
  const _ChapterNav({
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasPrevious)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Previous'),
            ),
          ),
        if (hasPrevious && hasNext) const SizedBox(width: 12),
        if (hasNext)
          Expanded(
            child: FilledButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Next chapter'),
            ),
          ),
      ],
    );
  }
}
