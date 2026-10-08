import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/book_cover.dart';
import 'notes_screen.dart';
import 'reader_common.dart';

/// Lists every highlight and note for a book. Tapping one returns its page
/// number so the reader can jump there.
class MarksScreen extends StatefulWidget {
  const MarksScreen({super.key, required this.book});

  final Book book;

  @override
  State<MarksScreen> createState() => _MarksScreenState();
}

class _MarksScreenState extends State<MarksScreen> {
  final _store = LibraryStore.instance;
  MarkKind? _filter;
  String _query = '';

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

  String get _unit => widget.book.format == BookFormat.epub ? 'ch.' : 'p.';

  void _copyAll(List<Mark> marks) {
    final buffer = StringBuffer('${widget.book.title}\n\n');
    for (final m in marks) {
      buffer.writeln('$_unit${m.pageNumber} — ${m.text}');
      if (m.translation != null) buffer.writeln('  → ${m.translation}');
      if (m.note != null) buffer.writeln('  note: ${m.note}');
      buffer.writeln();
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied ${marks.length} items')));
  }

  @override
  Widget build(BuildContext context) {
    final all = _store.marksFor(widget.book.id);
    final q = _query.trim().toLowerCase();

    final marks = all.where((m) {
      if (_filter != null && m.kind != _filter) return false;
      if (q.isEmpty) return true;
      return m.text.toLowerCase().contains(q) ||
          (m.note ?? '').toLowerCase().contains(q) ||
          (m.translation ?? '').toLowerCase().contains(q);
    }).toList();

    final bookNotes = _store.notesFor(widget.book.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Highlights & notes'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: marks.isEmpty ? null : () => _copyAll(marks),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search in this book’s marks…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                _chip('All', null, all.length),
                const SizedBox(width: 8),
                _chip(
                  'Highlights',
                  MarkKind.highlight,
                  all.where((m) => m.kind == MarkKind.highlight).length,
                ),
                const SizedBox(width: 8),
                _chip(
                  'Notes',
                  MarkKind.note,
                  all.where((m) => m.kind == MarkKind.note).length,
                ),
              ],
            ),
          ),
          if (bookNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => NotesScreen(book: widget.book)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${bookNotes.length} notebook '
                            'entr${bookNotes.length == 1 ? 'y' : 'ies'} about this book',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: marks.isEmpty
                ? EmptyState(
                    icon: Icons.bookmarks_outlined,
                    title: q.isEmpty ? 'Nothing saved yet' : 'No matches',
                    message: q.isEmpty
                        ? 'While reading, select a passage and choose Highlight, '
                              'Translate or Note.'
                        : 'Nothing matches “$_query”.',
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      24 + MediaQuery.of(context).viewPadding.bottom,
                    ),
                    itemCount: marks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _MarkTile(
                      mark: marks[i],
                      unit: _unit,
                      onTap: () => Navigator.pop(context, marks[i].pageNumber),
                      onDelete: () => _store.deleteMark(marks[i].id),
                      onEdit: () => _editNote(marks[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _editNote(Mark mark) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => NoteDialog(quote: mark.text),
    );
    if (note == null) return;
    mark.note = note.trim().isEmpty ? null : note.trim();
    await _store.updateMark(mark);
  }

  Widget _chip(String label, MarkKind? kind, int count) {
    return ChoiceChip(
      label: Text('$label · $count'),
      selected: _filter == kind,
      onSelected: (_) => setState(() => _filter = kind),
    );
  }
}

class _MarkTile extends StatelessWidget {
  const _MarkTile({
    required this.mark,
    required this.unit,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
  });

  final Mark mark;
  final String unit;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Color(mark.colorValue | 0xFF000000);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    mark.kind == MarkKind.note ? 'Note' : 'Highlight',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(label: '$unit${mark.pageNumber}'),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Edit note',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  mark.text,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              if (mark.translation != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.translate, size: 15, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mark.translation!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          height: 1.5,
                        ),
                        textDirection: isRtl(mark.targetLang ?? 'en')
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                      ),
                    ),
                  ],
                ),
              ],
              if (mark.note != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    mark.note!,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
