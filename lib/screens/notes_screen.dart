import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/book_cover.dart';

/// The notebook: free-form notes, optionally attached to a book and page.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, this.book});

  /// When set, the screen shows only this book's notes and files new ones
  /// against it.
  final Book? book;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _store = LibraryStore.instance;
  final _searchController = TextEditingController();

  String _query = '';
  String? _tag;
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

  Future<void> _edit(Note? note) async {
    final draft =
        note ??
        Note(
          id: newId(),
          title: '',
          body: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          bookId: widget.book?.id,
        );

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: draft, isNew: note == null)),
    );
  }

  Future<void> _delete(Note note) async {
    await _store.deleteNote(note.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Note deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _store.saveNote(note),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final notes = _store.notebook(
      query: _query,
      tag: _tag,
      bookId: widget.book?.id,
    );
    final tags = _store.allNoteTags;

    return Scaffold(
      // Transparent only as a main tab (over the sakura backdrop); as a pushed
      // per-book view it needs its own opaque background.
      backgroundColor: widget.book == null ? Colors.transparent : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('New note'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: widget.book != null,
            title: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search notes…',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  )
                : Text(widget.book == null ? 'Notes' : 'Notes on this book'),
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
            ],
          ),

          if (tags.isNotEmpty && widget.book == null)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    for (final t in tags) ...[
                      ChoiceChip(
                        avatar: const Icon(Icons.tag, size: 14),
                        label: Text(t),
                        selected: _tag == t,
                        onSelected: (_) => setState(() => _tag = _tag == t ? null : t),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),

          if (notes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.edit_note,
                title: _query.isEmpty ? 'No notes yet' : 'No matching notes',
                message: _query.isEmpty
                    ? 'Write down what a book made you think. You can also select text '
                          'while reading and save it straight here.'
                    : 'Nothing matches “$_query”.',
                action: _query.isEmpty
                    ? FilledButton.icon(
                        onPressed: () => _edit(null),
                        icon: const Icon(Icons.add),
                        label: const Text('Write a note'),
                      )
                    : null,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              sliver: SliverList.separated(
                itemCount: notes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _NoteCard(
                  note: notes[i],
                  book: _store.bookById(notes[i].bookId),
                  onTap: () => _edit(notes[i]),
                  onPin: () => _store.saveNote(notes[i]..pinned = !notes[i].pinned),
                  onDelete: () => _delete(notes[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.book,
    required this.onTap,
    required this.onPin,
    required this.onDelete,
  });

  final Note note;
  final Book? book;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = note.colorValue == null
        ? theme.colorScheme.primary
        : Color(note.colorValue! | 0xFF000000);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              note.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: note.pinned ? 'Unpin' : 'Pin',
                            icon: Icon(
                              note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                              size: 18,
                              color: note.pinned ? accent : theme.colorScheme.onSurfaceVariant,
                            ),
                            onPressed: onPin,
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: onDelete,
                          ),
                        ],
                      ),
                      if (note.preview.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          note.preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (book != null)
                            Pill(
                              label: book!.title,
                              icon: Icons.menu_book,
                              color: theme.colorScheme.secondary,
                              filled: true,
                            ),
                          if (note.pageNumber != null)
                            Pill(label: 'p.${note.pageNumber}'),
                          for (final t in note.tags) Pill(label: t, icon: Icons.tag),
                          Text(
                            _ago(note.updatedAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

// ------------------------------------------------------------------ editor

/// Full-screen note editor. Saves as you leave, so nothing is lost.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.note, this.isNew = false});

  final Note note;
  final bool isNew;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _store = LibraryStore.instance;
  late final TextEditingController _title;
  late final TextEditingController _body;

  late final List<String> _tags = [...widget.note.tags];
  late int? _color = widget.note.colorValue;
  late String? _bookId = widget.note.bookId;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: widget.note.body);
    _body.addListener(_onBodyChanged);
  }

  @override
  void dispose() {
    _body.removeListener(_onBodyChanged);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onBodyChanged() => setState(() {});

  bool get _isEmpty => _title.text.trim().isEmpty && _body.text.trim().isEmpty;

  Future<void> _save() async {
    // An untouched blank note isn't worth keeping.
    if (_isEmpty) {
      if (!widget.isNew) await _store.deleteNote(widget.note.id);
      return;
    }
    widget.note
      ..title = _title.text
      ..body = _body.text
      ..tags = _tags
      ..colorValue = _color
      ..bookId = _bookId;
    await _store.saveNote(widget.note);
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add tag'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'e.g. philosophy'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            if (_store.allNoteTags.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in _store.allNoteTags.take(12))
                    ActionChip(
                      label: Text(t),
                      onPressed: () => Navigator.pop(context, t),
                    ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();

    final clean = tag?.trim();
    if (clean == null || clean.isEmpty || _tags.contains(clean)) return;
    setState(() => _tags.add(clean));
  }

  Future<void> _pickBook() async {
    final books = _store.books;
    if (books.isEmpty) return;

    final chosen = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Not about a book'),
              selected: _bookId == null,
              onTap: () => Navigator.pop(sheetContext, null),
            ),
            const Divider(),
            for (final b in books)
              ListTile(
                leading: SizedBox(
                  width: 32,
                  height: 46,
                  child: BookCover.of(b, radius: 6),
                ),
                title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(b.author ?? b.format.label),
                selected: _bookId == b.id,
                onTap: () => Navigator.pop(sheetContext, b.id),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _bookId = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = _store.bookById(_bookId);
    final words = _body.text.trim().isEmpty
        ? 0
        : _body.text.trim().split(RegExp(r'\s+')).length;

    return PopScope(
      // Saving on the way out means there is no "unsaved changes" state at all.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? 'New note' : 'Note'),
          actions: [
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _isEmpty
                  ? null
                  : () {
                      Clipboard.setData(
                        ClipboardData(text: '${_title.text}\n\n${_body.text}'.trim()),
                      );
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(content: Text('Copied')));
                    },
            ),
            IconButton(
              tooltip: 'Accent colour',
              icon: Icon(
                Icons.palette_outlined,
                color: _color == null ? null : Color(_color! | 0xFF000000),
              ),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Accent colour',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final c in kHighlightColors)
                              GestureDetector(
                                onTap: () {
                                  setState(() => _color = c);
                                  Navigator.pop(sheetContext);
                                },
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: Color(c | 0xFF000000),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _color == c
                                          ? theme.colorScheme.onSurface
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  TextField(
                    controller: _title,
                    autofocus: widget.isNew,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Title',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _body,
                    maxLines: null,
                    minLines: 12,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
                    decoration: const InputDecoration(
                      hintText: 'Start writing…',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                child: Column(
                  children: [
                    if (_tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final t in _tags)
                              InputChip(
                                label: Text(t),
                                onDeleted: () => setState(() => _tags.remove(t)),
                              ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Add tag',
                          icon: const Icon(Icons.tag),
                          onPressed: _addTag,
                        ),
                        IconButton(
                          tooltip: 'Link to a book',
                          icon: Icon(
                            book == null ? Icons.menu_book_outlined : Icons.menu_book,
                            color: book == null ? null : theme.colorScheme.secondary,
                          ),
                          onPressed: _pickBook,
                        ),
                        if (book != null)
                          Expanded(
                            child: Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        Text(
                          '$words word${words == 1 ? '' : 's'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
