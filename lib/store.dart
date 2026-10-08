import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'theme.dart';

/// Generates the ids used for books, marks and notes.
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}';

/// Persists the library (books, highlights, notes, settings) locally.
///
/// A [ChangeNotifier] so every screen stays in sync.
class LibraryStore extends ChangeNotifier {
  LibraryStore._();

  static final LibraryStore instance = LibraryStore._();

  static const _kBooks = 'books';
  static const _kMarks = 'marks';
  static const _kNotes = 'notes';
  static const _kTargetLang = 'targetLang';
  static const _kHighlightColor = 'highlightColor';
  static const _kTheme = 'theme';
  static const _kSort = 'librarySort';
  static const _kGrid = 'libraryGrid';
  static const _kCustomFeeds = 'customFeeds';
  static const _kReaderScroll = 'readerScroll';
  static const _kKeepAwake = 'keepAwake';

  final List<Book> _books = [];
  final List<Mark> _marks = [];
  final List<Note> _notes = [];

  String _targetLang = 'ar';
  int _highlightColor = kHighlightColors.first;
  AppTheme _theme = AppTheme.night;
  LibrarySort _sort = LibrarySort.recent;
  bool _gridView = true;
  bool _readerScrollVertical = true;
  bool _keepAwake = true;
  List<CustomFeed> _customFeeds = [];
  bool _loaded = false;

  List<Book> get books => List.unmodifiable(_books);
  List<Note> get notes => List.unmodifiable(_notes);
  bool get isLoaded => _loaded;
  String get targetLang => _targetLang;
  int get highlightColor => _highlightColor;
  AppTheme get theme => _theme;
  LibrarySort get sort => _sort;
  bool get gridView => _gridView;
  bool get readerScrollVertical => _readerScrollVertical;
  bool get keepAwake => _keepAwake;
  List<CustomFeed> get customFeeds => List.unmodifiable(_customFeeds);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    _books
      ..clear()
      ..addAll(_decodeList(prefs.getString(_kBooks)).map(Book.fromJson));
    _marks
      ..clear()
      ..addAll(_decodeList(prefs.getString(_kMarks)).map(Mark.fromJson));
    _notes
      ..clear()
      ..addAll(_decodeList(prefs.getString(_kNotes)).map(Note.fromJson));

    _targetLang = prefs.getString(_kTargetLang) ?? 'ar';
    _highlightColor = prefs.getInt(_kHighlightColor) ?? kHighlightColors.first;
    _theme = AppTheme.values.firstWhere(
      (t) => t.name == prefs.getString(_kTheme),
      orElse: () => AppTheme.night,
    );
    _sort = LibrarySort.values.firstWhere(
      (s) => s.name == prefs.getString(_kSort),
      orElse: () => LibrarySort.recent,
    );
    _gridView = prefs.getBool(_kGrid) ?? true;
    _readerScrollVertical = prefs.getBool(_kReaderScroll) ?? true;
    _keepAwake = prefs.getBool(_kKeepAwake) ?? true;
    _customFeeds = _decodeList(prefs.getString(_kCustomFeeds))
        .map(CustomFeed.fromJson)
        .toList();

    // Drop books whose file has been removed from disk.
    _books.removeWhere((b) => !File(b.filePath).existsSync());

    _loaded = true;
    notifyListeners();
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveBooks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBooks, jsonEncode(_books.map((b) => b.toJson()).toList()));
  }

  Future<void> _saveMarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMarks, jsonEncode(_marks.map((m) => m.toJson()).toList()));
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNotes, jsonEncode(_notes.map((n) => n.toJson()).toList()));
  }

  // ------------------------------------------------------------------ books

  Book? bookById(String? id) {
    if (id == null) return null;
    for (final b in _books) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// True when a book installed from [sourceUrl] is already in the library.
  bool hasSourceUrl(String url) => _books.any((b) => b.sourceUrl == url);

  Future<void> addBook(Book book) async {
    _books.insert(0, book);
    await _saveBooks();
    notifyListeners();
  }

  Future<void> updateBook(Book book) async {
    final i = _books.indexWhere((b) => b.id == book.id);
    if (i == -1) return;
    _books[i] = book;
    await _saveBooks();
    notifyListeners();
  }

  /// Saves the reading position without notifying listeners, so page turns
  /// don't rebuild the viewer.
  Future<void> saveLastPage(String bookId, int page) async {
    final b = bookById(bookId);
    if (b == null || b.lastPage == page) return;
    b.lastPage = page;
    b.lastOpenedAt = DateTime.now();
    await _saveBooks();
  }

  /// Adds [seconds] to a book's reading time. Silent, like [saveLastPage].
  Future<void> addReadingTime(String bookId, int seconds) async {
    final b = bookById(bookId);
    if (b == null || seconds <= 0) return;
    b.readingSeconds += seconds;
    b.lastOpenedAt = DateTime.now();
    await _saveBooks();
  }

  Future<void> toggleFavorite(Book book) async {
    book.favorite = !book.favorite;
    await updateBook(book);
  }

  Future<void> toggleFinished(Book book) async {
    book.finished = !book.finished;
    await updateBook(book);
  }

  Future<void> deleteBook(Book book) async {
    _books.removeWhere((b) => b.id == book.id);
    _marks.removeWhere((m) => m.bookId == book.id);
    // Notes survive their book, but lose the dead link.
    for (final n in _notes) {
      if (n.bookId == book.id) n.bookId = null;
    }

    for (final path in [book.filePath, book.coverPath]) {
      if (path == null) continue;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // best effort
      }
    }

    await _saveBooks();
    await _saveMarks();
    await _saveNotes();
    notifyListeners();
  }

  /// The library, filtered, searched and sorted for display.
  List<Book> shelf({
    LibraryFilter filter = LibraryFilter.all,
    String query = '',
    String? tag,
  }) {
    final q = query.trim().toLowerCase();

    final out = _books.where((b) {
      switch (filter) {
        case LibraryFilter.reading:
          if (!b.started || b.finished) return false;
        case LibraryFilter.unread:
          if (b.started) return false;
        case LibraryFilter.finished:
          if (!b.finished) return false;
        case LibraryFilter.favorites:
          if (!b.favorite) return false;
        case LibraryFilter.all:
          break;
      }
      if (tag != null && !b.tags.contains(tag)) return false;
      if (q.isEmpty) return true;
      return b.title.toLowerCase().contains(q) ||
          (b.author ?? '').toLowerCase().contains(q) ||
          b.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    out.sort((a, b) {
      switch (_sort) {
        case LibrarySort.recent:
          return b.addedAt.compareTo(a.addedAt);
        case LibrarySort.opened:
          final ax = a.lastOpenedAt ?? a.addedAt;
          final bx = b.lastOpenedAt ?? b.addedAt;
          return bx.compareTo(ax);
        case LibrarySort.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case LibrarySort.author:
          return (a.author ?? '~').toLowerCase().compareTo((b.author ?? '~').toLowerCase());
        case LibrarySort.progress:
          return b.progress.compareTo(a.progress);
      }
    });
    return out;
  }

  /// Every tag in use across the library, alphabetically.
  List<String> get allTags {
    final set = <String>{};
    for (final b in _books) {
      set.addAll(b.tags);
    }
    final out = set.toList()..sort();
    return out;
  }

  /// Aggregate stats for the library header.
  ({int books, int reading, int finished, int marks, int notes, int minutes}) get stats => (
    books: _books.length,
    reading: _books.where((b) => b.started && !b.finished).length,
    finished: _books.where((b) => b.finished).length,
    marks: _marks.length,
    notes: _notes.length,
    minutes: _books.fold<int>(0, (sum, b) => sum + b.readingSeconds) ~/ 60,
  );

  // ------------------------------------------------------------------ marks

  List<Mark> marksFor(String bookId) =>
      _marks.where((m) => m.bookId == bookId).toList()
        ..sort((a, b) {
          final byPage = a.pageNumber.compareTo(b.pageNumber);
          return byPage != 0 ? byPage : a.createdAt.compareTo(b.createdAt);
        });

  int countFor(String bookId, MarkKind kind) =>
      _marks.where((m) => m.bookId == bookId && m.kind == kind).length;

  Future<void> addMark(Mark mark) async {
    _marks.add(mark);
    await _saveMarks();
    notifyListeners();
  }

  Future<void> updateMark(Mark mark) async {
    final i = _marks.indexWhere((m) => m.id == mark.id);
    if (i == -1) return;
    _marks[i] = mark;
    await _saveMarks();
    notifyListeners();
  }

  Future<void> deleteMark(String markId) async {
    _marks.removeWhere((m) => m.id == markId);
    await _saveMarks();
    notifyListeners();
  }

  // ------------------------------------------------------------------ notes

  Future<void> saveNote(Note note) async {
    note.updatedAt = DateTime.now();
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i == -1) {
      _notes.insert(0, note);
    } else {
      _notes[i] = note;
    }
    await _saveNotes();
    notifyListeners();
  }

  Future<void> deleteNote(String noteId) async {
    _notes.removeWhere((n) => n.id == noteId);
    await _saveNotes();
    notifyListeners();
  }

  List<Note> notesFor(String bookId) =>
      _notes.where((n) => n.bookId == bookId).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// Notes filtered by a free-text query and an optional tag, pinned first.
  List<Note> notebook({String query = '', String? tag, String? bookId}) {
    final q = query.trim().toLowerCase();

    final out = _notes.where((n) {
      if (bookId != null && n.bookId != bookId) return false;
      if (tag != null && !n.tags.contains(tag)) return false;
      if (q.isEmpty) return true;
      return n.title.toLowerCase().contains(q) ||
          n.body.toLowerCase().contains(q) ||
          n.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    out.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return out;
  }

  List<String> get allNoteTags {
    final set = <String>{};
    for (final n in _notes) {
      set.addAll(n.tags);
    }
    final out = set.toList()..sort();
    return out;
  }

  // --------------------------------------------------------------- settings

  Future<void> setTargetLang(String lang) async {
    _targetLang = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTargetLang, lang);
    notifyListeners();
  }

  Future<void> setHighlightColor(int color) async {
    _highlightColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kHighlightColor, color);
    notifyListeners();
  }

  Future<void> setTheme(AppTheme theme) async {
    _theme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, theme.name);
    notifyListeners();
  }

  Future<void> setSort(LibrarySort sort) async {
    _sort = sort;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSort, sort.name);
    notifyListeners();
  }

  Future<void> setGridView(bool grid) async {
    _gridView = grid;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGrid, grid);
    notifyListeners();
  }

  Future<void> setReaderScrollVertical(bool vertical) async {
    _readerScrollVertical = vertical;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReaderScroll, vertical);
    notifyListeners();
  }

  Future<void> setKeepAwake(bool value) async {
    _keepAwake = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepAwake, value);
    notifyListeners();
  }

  // ----------------------------------------------------------- custom feeds

  Future<void> addCustomFeed(CustomFeed feed) async {
    _customFeeds = [..._customFeeds, feed];
    await _saveFeeds();
    notifyListeners();
  }

  Future<void> removeCustomFeed(String id) async {
    _customFeeds = _customFeeds.where((f) => f.id != id).toList();
    await _saveFeeds();
    notifyListeners();
  }

  Future<void> _saveFeeds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kCustomFeeds,
      jsonEncode(_customFeeds.map((f) => f.toJson()).toList()),
    );
  }
}

/// A user-added OPDS catalog, searched alongside the built-in sources.
class CustomFeed {
  const CustomFeed({required this.id, required this.name, required this.url});

  final String id;
  final String name;

  /// OPDS search URL. `{query}` is replaced with the search terms; when the
  /// placeholder is absent the feed is fetched as-is and filtered locally.
  final String url;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};

  factory CustomFeed.fromJson(Map<String, dynamic> j) => CustomFeed(
    id: (j['id'] as String?) ?? newId(),
    name: (j['name'] as String?) ?? 'Custom catalog',
    url: (j['url'] as String?) ?? '',
  );
}
