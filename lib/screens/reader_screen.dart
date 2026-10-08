import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'marks_screen.dart';
import 'notes_screen.dart';
import 'reader_common.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _controller = PdfViewerController();
  final _store = LibraryStore.instance;

  List<Mark> _marks = [];
  int _currentPage = 1;
  int _pageCount = 0;

  /// Reading mode: the book opens with no chrome at all — just the pages — and
  /// a triple-tap brings the toolbar back.
  bool _chromeVisible = false;
  Timer? _readingTimer;
  int _secondsRead = 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.book.lastPage;
    _marks = _store.marksFor(widget.book.id);
    _store.addListener(_onStoreChanged);

    _readingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _secondsRead += 10);
    _applySystemUi();
    showReadingModeHintOnce(context);
  }

  @override
  void dispose() {
    _readingTimer?.cancel();
    _store.addReadingTime(widget.book.id, _secondsRead);
    _store.removeListener(_onStoreChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Hides the system status/navigation bars while reading, and restores them
  /// alongside the app's own toolbar.
  void _applySystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      _chromeVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    _applySystemUi();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() => _marks = _store.marksFor(widget.book.id));
  }

  // ---------------------------------------------------------------- painting

  /// Draws saved highlights and note anchors onto each page.
  void _paintMarks(Canvas canvas, Rect pageRect, PdfPage page) {
    for (final mark in _marks) {
      if (mark.pageNumber != page.pageNumber) continue;

      final paint = Paint()..color = Color(mark.colorValue);
      for (final r in mark.rects) {
        if (r.right <= r.left || r.top <= r.bottom) continue;
        final rect = PdfRect(r.left, r.top, r.right, r.bottom)
            .toRect(page: page, scaledPageSize: pageRect.size)
            .translate(pageRect.left, pageRect.top);
        canvas.drawRect(rect, paint);

        // Notes get an underline so they read differently from a plain highlight.
        if (mark.kind == MarkKind.note) {
          canvas.drawRect(
            Rect.fromLTWH(rect.left, rect.bottom - 1.5, rect.width, 1.5),
            Paint()..color = TokyoNight.blue,
          );
        }
      }
    }
  }

  /// Merges the per-character boxes of a selection into one rect per text line.
  List<RectData> _lineRects(PdfPageTextRange range) {
    final chars = range.pageText.charRects;
    final out = <RectData>[];

    double? left, top, right, bottom;

    void flush() {
      if (left == null) return;
      out.add(RectData(left!, top!, right!, bottom!));
      left = top = right = bottom = null;
    }

    final end = math.min(range.end, chars.length);
    for (var i = range.start; i < end; i++) {
      final c = chars[i];
      if (c.right <= c.left || c.top <= c.bottom) continue; // no glyph box

      if (left == null) {
        left = c.left;
        top = c.top;
        right = c.right;
        bottom = c.bottom;
        continue;
      }

      // Same visual line when the vertical spans overlap.
      final overlaps = bottom! < c.top && c.bottom < top!;
      if (overlaps) {
        left = math.min(left!, c.left);
        top = math.max(top!, c.top);
        right = math.max(right!, c.right);
        bottom = math.min(bottom!, c.bottom);
      } else {
        flush();
        left = c.left;
        top = c.top;
        right = c.right;
        bottom = c.bottom;
      }
    }
    flush();
    return out;
  }

  // ----------------------------------------------------------- menu actions

  Future<void> _withSelection(
    PdfViewerContextMenuBuilderParams params,
    Future<void> Function(String text, List<PdfPageTextRange> ranges) action,
  ) async {
    final delegate = params.textSelectionDelegate;
    final text = await delegate.getSelectedText();
    final ranges = await delegate.getSelectedTextRanges();

    params.dismissContextMenu();
    await delegate.clearTextSelection();

    if (text.trim().isEmpty || ranges.isEmpty) return;
    await action(text.trim(), ranges);
  }

  Future<void> _highlight(PdfViewerContextMenuBuilderParams params) =>
      _withSelection(params, (text, ranges) async {
        for (final range in ranges) {
          final rects = _lineRects(range);
          if (rects.isEmpty) continue;
          await _store.addMark(
            Mark(
              id: newId(),
              bookId: widget.book.id,
              kind: MarkKind.highlight,
              pageNumber: range.pageNumber,
              text: range.text.trim(),
              rects: rects,
              colorValue: _store.highlightColor,
              createdAt: DateTime.now(),
            ),
          );
        }
        _toast('Highlighted');
      });

  Future<void> _translate(PdfViewerContextMenuBuilderParams params) =>
      _withSelection(params, (text, ranges) async {
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => TranslateSheet(
            text: text,
            onSave: (translation, lang) async {
              final range = ranges.first;
              await _store.addMark(
                Mark(
                  id: newId(),
                  bookId: widget.book.id,
                  kind: MarkKind.highlight,
                  pageNumber: range.pageNumber,
                  text: text,
                  rects: _lineRects(range),
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
      });

  Future<void> _note(PdfViewerContextMenuBuilderParams params) =>
      _withSelection(params, (text, ranges) async {
        if (!mounted) return;
        final note = await showDialog<String>(
          context: context,
          builder: (_) => NoteDialog(quote: text),
        );
        if (note == null || note.trim().isEmpty) return;

        final range = ranges.first;
        await _store.addMark(
          Mark(
            id: newId(),
            bookId: widget.book.id,
            kind: MarkKind.note,
            pageNumber: range.pageNumber,
            text: text,
            rects: _lineRects(range),
            colorValue: _store.highlightColor,
            createdAt: DateTime.now(),
            note: note.trim(),
          ),
        );
        _toast('Note added');
      });

  /// Sends the selection to the notebook as a full note.
  Future<void> _toNotebook(PdfViewerContextMenuBuilderParams params) =>
      _withSelection(params, (text, ranges) async {
        if (!mounted) return;
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
                pageNumber: ranges.first.pageNumber,
              ),
            ),
          ),
        );
      });

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Widget? _buildContextMenu(BuildContext context, PdfViewerContextMenuBuilderParams params) {
    if (params.contextMenuFor != PdfViewerPart.selectedText) return null;
    if (!params.textSelectionDelegate.hasSelectedText) return null;

    return Align(
      alignment: Alignment.topLeft,
      child: AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(
          primaryAnchor: params.anchorA,
          secondaryAnchor: params.anchorB,
        ),
        buttonItems: [
          ContextMenuButtonItem(label: 'Highlight', onPressed: () => _highlight(params)),
          ContextMenuButtonItem(label: 'Translate', onPressed: () => _translate(params)),
          ContextMenuButtonItem(label: 'Note', onPressed: () => _note(params)),
          ContextMenuButtonItem(label: 'To notebook', onPressed: () => _toNotebook(params)),
          ContextMenuButtonItem(
            label: 'Copy',
            onPressed: () {
              params.textSelectionDelegate.copyTextSelection();
              params.dismissContextMenu();
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ chrome

  Future<void> _openMarks() async {
    final page = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => MarksScreen(book: widget.book)),
    );
    if (page != null && _controller.isReady) {
      await _controller.goToPage(pageNumber: page);
    }
  }

  Future<void> _openOutline() async {
    if (!_controller.isReady) return;
    final outline = await _controller.document.loadOutline();
    if (!mounted) return;

    if (outline.isEmpty) {
      _toast('This PDF has no table of contents');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scrollController) {
          final flat = <({PdfOutlineNode node, int depth})>[];
          void walk(List<PdfOutlineNode> nodes, int depth) {
            for (final n in nodes) {
              flat.add((node: n, depth: depth));
              walk(n.children, depth + 1);
            }
          }

          walk(outline, 0);

          return ListView.builder(
            controller: scrollController,
            itemCount: flat.length,
            itemBuilder: (context, i) {
              final entry = flat[i];
              return ListTile(
                contentPadding: EdgeInsets.only(left: 20.0 + entry.depth * 16, right: 20),
                title: Text(
                  entry.node.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: entry.depth == 0 ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final dest = entry.node.dest;
                  if (dest != null) _controller.goToDest(dest);
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _jumpToPage() async {
    final controller = TextEditingController(text: '$_currentPage');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 – $_pageCount'),
          onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (page == null || _pageCount == 0) return;
    await _controller.goToPage(pageNumber: page.clamp(1, _pageCount));
  }

  /// Lays pages out left-to-right when the reader is in horizontal mode.
  PdfPageLayout _horizontalLayout(List<PdfPage> pages, PdfViewerParams params) {
    final height =
        pages.fold<double>(0, (prev, p) => math.max(prev, p.height)) + params.margin * 2;
    final rects = <Rect>[];
    var x = params.margin;
    for (final page in pages) {
      rects.add(Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height));
      x += page.width + params.margin;
    }
    return PdfPageLayout(pageLayouts: rects, documentSize: Size(x, height));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vertical = _store.readerScrollVertical;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceDim,
      body: TripleTapDetector(
        onTripleTap: _toggleChrome,
        child: Stack(
        children: [
          Positioned.fill(
            child: PdfViewer.file(
              widget.book.filePath,
              controller: _controller,
              initialPageNumber: widget.book.lastPage,
              params: PdfViewerParams(
                backgroundColor: theme.colorScheme.surfaceDim,
                margin: 10,
                // Platform-tuned momentum physics with a lighter fling friction
                // make paging through a long book feel smooth rather than stiff.
                scrollPhysics: PdfViewerParams.getScrollPhysics(context),
                interactionEndFrictionCoefficient: 0.00001,
                // A new list each build so saved highlights repaint immediately.
                pagePaintCallbacks: [_paintMarks],
                buildContextMenu: _buildContextMenu,
                textSelectionParams: const PdfTextSelectionParams(enabled: true),
                layoutPages: vertical ? null : _horizontalLayout,
                onViewerReady: (document, controller) {
                  if (!mounted) return;
                  setState(() => _pageCount = document.pages.length);
                  final book = widget.book;
                  if (book.pageCount != document.pages.length) {
                    book.pageCount = document.pages.length;
                    _store.updateBook(book);
                  }
                },
                onPageChanged: (pageNumber) {
                  if (pageNumber == null) return;
                  setState(() => _currentPage = pageNumber);
                  _store.saveLastPage(widget.book.id, pageNumber);
                },
              ),
            ),
          ),

          // A tap anywhere toggles the chrome, so the page fills the screen
          // while reading.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: const SizedBox.shrink(),
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
                subtitle: _pageCount > 0
                    ? 'Page $_currentPage of $_pageCount'
                    : 'Loading…',
                actions: [
                  IconButton(
                    tooltip: 'Contents',
                    onPressed: _openOutline,
                    icon: const Icon(Icons.list),
                  ),
                  IconButton(
                    tooltip: 'Highlight colour',
                    onPressed: () => pickHighlightColor(context),
                    icon: Icon(
                      Icons.brush,
                      color: Color(_store.highlightColor | 0xFF000000),
                    ),
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
                page: _currentPage,
                pageCount: _pageCount,
                onSeek: (p) => _controller.isReady
                    ? _controller.goToPage(pageNumber: p)
                    : Future<void>.value(),
                onJump: _jumpToPage,
                trailing: IconButton(
                  tooltip: vertical ? 'Horizontal pages' : 'Vertical pages',
                  icon: Icon(vertical ? Icons.swap_horiz : Icons.swap_vert),
                  onPressed: () => _store.setReaderScrollVertical(!vertical),
                ),
              ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}
