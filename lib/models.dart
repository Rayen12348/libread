// Data models for the library, persisted as JSON in shared_preferences.

/// Highlight colours, stored as ARGB ints so we never depend on a Flutter
/// Color API that may change across SDK versions. Drawn from Tokyo Night.
const List<int> kHighlightColors = [
  0x66E0AF68, // yellow
  0x669ECE6A, // green
  0x667AA2F7, // blue
  0x66BB9AF7, // magenta
  0x66FF9E64, // orange
  0x66F7768E, // red
  0x6673DACA, // teal
];

/// A rectangle in PDF page coordinates (origin bottom-left, `top` > `bottom`).
class RectData {
  const RectData(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, dynamic> toJson() => {'l': left, 't': top, 'r': right, 'b': bottom};

  factory RectData.fromJson(Map<String, dynamic> j) => RectData(
    (j['l'] as num).toDouble(),
    (j['t'] as num).toDouble(),
    (j['r'] as num).toDouble(),
    (j['b'] as num).toDouble(),
  );
}

enum MarkKind { highlight, note }

/// A highlight or a note anchored to a text range on a page.
class Mark {
  Mark({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.pageNumber,
    required this.text,
    required this.rects,
    required this.colorValue,
    required this.createdAt,
    this.note,
    this.translation,
    this.targetLang,
  });

  final String id;
  final String bookId;
  final MarkKind kind;
  final int pageNumber;
  final String text;
  final List<RectData> rects;
  int colorValue;
  final DateTime createdAt;
  String? note;
  String? translation;
  String? targetLang;

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'kind': kind.name,
    'page': pageNumber,
    'text': text,
    'rects': rects.map((r) => r.toJson()).toList(),
    'color': colorValue,
    'createdAt': createdAt.toIso8601String(),
    'note': note,
    'translation': translation,
    'targetLang': targetLang,
  };

  factory Mark.fromJson(Map<String, dynamic> j) => Mark(
    id: j['id'] as String,
    bookId: j['bookId'] as String,
    kind: MarkKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => MarkKind.highlight,
    ),
    pageNumber: (j['page'] as num).toInt(),
    text: (j['text'] as String?) ?? '',
    rects: ((j['rects'] as List?) ?? const [])
        .map((e) => RectData.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    colorValue: (j['color'] as num?)?.toInt() ?? kHighlightColors.first,
    createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now(),
    note: j['note'] as String?,
    translation: j['translation'] as String?,
    targetLang: j['targetLang'] as String?,
  );
}

/// A free-form note in the notebook. Optionally attached to a book and page.
class Note {
  Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.bookId,
    this.pageNumber,
    this.tags = const [],
    this.pinned = false,
    this.colorValue,
  });

  final String id;
  String title;
  String body;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Set when the note was written from inside a book.
  String? bookId;
  int? pageNumber;

  List<String> tags;
  bool pinned;

  /// Optional accent, as an ARGB int.
  int? colorValue;

  /// First non-empty line, used when the note has no explicit title.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    for (final line in body.split('\n')) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return 'Untitled note';
  }

  String get preview => body.replaceAll(RegExp(r'\s+'), ' ').trim();

  int get wordCount =>
      body.trim().isEmpty ? 0 : body.trim().split(RegExp(r'\s+')).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'bookId': bookId,
    'page': pageNumber,
    'tags': tags,
    'pinned': pinned,
    'color': colorValue,
  };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? '',
    body: (j['body'] as String?) ?? '',
    createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? '') ?? DateTime.now(),
    bookId: j['bookId'] as String?,
    pageNumber: (j['page'] as num?)?.toInt(),
    tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
    pinned: (j['pinned'] as bool?) ?? false,
    colorValue: (j['color'] as num?)?.toInt(),
  );
}

/// File formats the reader can open.
enum BookFormat {
  pdf('PDF'),
  epub('EPUB');

  const BookFormat(this.label);

  final String label;

  static BookFormat fromPath(String path) =>
      path.toLowerCase().endsWith('.epub') ? BookFormat.epub : BookFormat.pdf;

  static BookFormat fromName(String? name) => BookFormat.values.firstWhere(
    (f) => f.name == name,
    orElse: () => BookFormat.pdf,
  );
}

/// A book in the library: the imported file plus its cover and reading position.
class Book {
  Book({
    required this.id,
    required this.title,
    required this.filePath,
    required this.addedAt,
    this.format = BookFormat.pdf,
    this.author,
    this.description,
    this.coverPath,
    this.coverUrl,
    this.coverSource,
    this.sourceName,
    this.sourceUrl,
    this.language,
    this.year,
    this.tags = const [],
    this.favorite = false,
    this.finished = false,
    this.lastPage = 1,
    this.pageCount = 0,
    this.readingSeconds = 0,
    this.lastOpenedAt,
  });

  final String id;
  String title;
  String? author;
  String? description;
  final String filePath;
  final DateTime addedAt;
  BookFormat format;

  /// Local file holding the cover image.
  String? coverPath;

  /// Remote URL the cover came from, when it was downloaded.
  String? coverUrl;

  /// Where the cover came from, e.g. "Open Library" or "First page".
  String? coverSource;

  /// Catalog the book itself was installed from, e.g. "Project Gutenberg".
  String? sourceName;
  String? sourceUrl;

  String? language;
  int? year;
  List<String> tags;
  bool favorite;
  bool finished;

  int lastPage;
  int pageCount;

  /// Total time spent in the reader, in seconds.
  int readingSeconds;
  DateTime? lastOpenedAt;

  /// Reading progress in the range 0..1.
  double get progress {
    if (finished) return 1;
    if (pageCount <= 1) return 0;
    return (lastPage.clamp(1, pageCount) - 1) / (pageCount - 1);
  }

  bool get started => lastPage > 1 || finished;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'description': description,
    'filePath': filePath,
    'addedAt': addedAt.toIso8601String(),
    'format': format.name,
    'coverPath': coverPath,
    'coverUrl': coverUrl,
    'coverSource': coverSource,
    'sourceName': sourceName,
    'sourceUrl': sourceUrl,
    'language': language,
    'year': year,
    'tags': tags,
    'favorite': favorite,
    'finished': finished,
    'lastPage': lastPage,
    'pageCount': pageCount,
    'readingSeconds': readingSeconds,
    'lastOpenedAt': lastOpenedAt?.toIso8601String(),
  };

  factory Book.fromJson(Map<String, dynamic> j) {
    final path = j['filePath'] as String;
    return Book(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? 'Untitled',
      author: j['author'] as String?,
      description: j['description'] as String?,
      filePath: path,
      addedAt: DateTime.tryParse((j['addedAt'] as String?) ?? '') ?? DateTime.now(),
      // Older libraries predate the format field; infer it from the extension.
      format: j['format'] == null
          ? BookFormat.fromPath(path)
          : BookFormat.fromName(j['format'] as String?),
      coverPath: j['coverPath'] as String?,
      coverUrl: j['coverUrl'] as String?,
      coverSource: j['coverSource'] as String?,
      sourceName: j['sourceName'] as String?,
      sourceUrl: j['sourceUrl'] as String?,
      language: j['language'] as String?,
      year: (j['year'] as num?)?.toInt(),
      tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
      favorite: (j['favorite'] as bool?) ?? false,
      finished: (j['finished'] as bool?) ?? false,
      lastPage: (j['lastPage'] as num?)?.toInt() ?? 1,
      pageCount: (j['pageCount'] as num?)?.toInt() ?? 0,
      readingSeconds: (j['readingSeconds'] as num?)?.toInt() ?? 0,
      lastOpenedAt: DateTime.tryParse((j['lastOpenedAt'] as String?) ?? ''),
    );
  }
}

/// How the library grid is ordered.
enum LibrarySort {
  recent('Recently added'),
  opened('Recently opened'),
  title('Title'),
  author('Author'),
  progress('Progress');

  const LibrarySort(this.label);

  final String label;
}

/// Which subset of the library is shown.
enum LibraryFilter {
  all('All'),
  reading('Reading'),
  unread('Unread'),
  finished('Finished'),
  favorites('Favorites');

  const LibraryFilter(this.label);

  final String label;
}
