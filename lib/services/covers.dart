import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models.dart';
import 'epub.dart';

class CoverCandidate {
  const CoverCandidate({
    required this.url,
    required this.source,
    this.title,
    this.author,
    this.publisher,
    this.popularity = 0,
    this.score = 0,
  });

  final String url;
  final String source;
  final String? title;
  final String? author;
  final String? publisher;
  final int popularity;

  /// How well the candidate's title matches what we searched for, 0..1.
  final double score;

  CoverCandidate withScore(double s) => CoverCandidate(
    url: url,
    source: source,
    title: title,
    author: author,
    publisher: publisher,
    popularity: popularity,
    score: s,
  );
}

/// Finds cover art for a book.
///
/// Every book gets a real cover: the book's own first page is rendered locally,
/// which needs no network and cannot fail on a bad title. Online catalogues are
/// then searched to upgrade that to the published artwork when a confident
/// match exists.
class CoverService {
  /// Renders the book's own first page (PDF) or embedded cover (EPUB) to a
  /// local PNG. Returns the file path.
  static Future<String?> generateLocal(Book book) async {
    try {
      final bytes = book.format == BookFormat.epub
          ? await _epubCoverBytes(book.filePath)
          : await _renderFirstPage(book.filePath);
      if (bytes == null || bytes.isEmpty) return null;
      return _write(book.id, bytes, extension: 'png');
    } catch (_) {
      return null;
    }
  }

  /// Rasterises page 1 of a PDF at a size suitable for a cover thumbnail.
  static Future<Uint8List?> _renderFirstPage(String path) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(path, useProgressiveLoading: true);
      if (doc.pages.isEmpty) return null;

      final page = doc.pages.first;
      // Target ~1000px on the long edge: sharp on any phone, still small on disk.
      final scale = 1000 / (page.height <= 0 ? 1000 : page.height);
      final width = (page.width * scale).round().clamp(1, 2000);
      final height = (page.height * scale).round().clamp(1, 2000);

      final rendered = await page.render(
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        width: width,
        height: height,
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered == null) return null;

      ui.Image? image;
      try {
        image = await rendered.createImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image?.dispose();
        rendered.dispose();
      }
    } catch (_) {
      return null;
    } finally {
      await doc?.dispose();
    }
  }

  static Future<Uint8List?> _epubCoverBytes(String path) async =>
      (await EpubService.peek(path)).cover;

  // ------------------------------------------------------------ online search

  /// Looks up cover candidates for a title across every catalogue, best first.
  ///
  /// Sources are queried concurrently and merged, so one being down or rate
  /// limited never costs us the others.
  static Future<List<CoverCandidate>> search(String title, {String? author}) async {
    final results = await Future.wait([
      _guard(() => _openLibrary(title, author)),
      _guard(() => _googleBooks(title, author)),
      _guard(() => _appleBooks(title, author)),
    ]);

    final candidates = [for (final list in results) ...list];
    final wanted = _normalize(title);

    final scored = [
      for (final c in candidates) c.withScore(_similarity(wanted, _normalize(c.title ?? ''))),
    ];

    scored.sort((a, b) {
      // A confidently matching title beats everything else.
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0 && (b.score - a.score).abs() > 0.08) return byScore;

      final ap = _isPenguin(a.publisher) ? 1 : 0;
      final bp = _isPenguin(b.publisher) ? 1 : 0;
      if (ap != bp) return bp - ap; // Penguin editions first
      return b.popularity.compareTo(a.popularity); // then most popular
    });

    return scored;
  }

  /// Searches online and installs the best confident match as [book]'s cover.
  ///
  /// Falls back to rendering the book's own first page. Returns the source name
  /// that ended up being used, or null if nothing worked.
  static Future<String?> refresh(Book book, {bool preferOnline = true}) async {
    if (preferOnline) {
      try {
        final candidates = await search(book.title, author: book.author);
        for (final c in candidates.take(5)) {
          // A weak title match is worse than the book's real first page.
          if (c.score < 0.55) break;
          final path = await download(book.id, c.url);
          if (path == null) continue;

          book.coverPath = path;
          book.coverUrl = c.url;
          book.coverSource = c.source;
          if (c.author != null && (book.author == null || book.author!.isEmpty)) {
            book.author = c.author;
          }
          return c.source;
        }
      } catch (_) {
        // fall through to the local cover
      }
    }

    final local = await generateLocal(book);
    if (local == null) return null;

    book.coverPath = local;
    book.coverUrl = null;
    book.coverSource = book.format == BookFormat.epub ? 'Book cover' : 'First page';
    return book.coverSource;
  }

  static Future<List<CoverCandidate>> _guard(
    Future<List<CoverCandidate>> Function() fetch,
  ) async {
    try {
      return await fetch();
    } catch (_) {
      return const [];
    }
  }

  static bool _isPenguin(String? publisher) =>
      publisher != null && publisher.toLowerCase().contains('penguin');

  static Future<List<CoverCandidate>> _googleBooks(String title, String? author) async {
    var query = 'intitle:$title';
    if (author != null && author.trim().isNotEmpty) {
      query += ' inauthor:$author';
    }

    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': query,
      'maxResults': '20',
      'printType': 'books',
    });

    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    // Google's keyless quota is shared and often exhausted (429); the other
    // sources cover for it.
    if (res.statusCode != 200) return const [];

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map) return const [];
    final items = j['items'];
    if (items is! List) return const [];

    final out = <CoverCandidate>[];
    for (final item in items) {
      if (item is! Map) continue;
      final info = item['volumeInfo'];
      if (info is! Map) continue;

      final links = info['imageLinks'];
      if (links is! Map) continue;

      var url = (links['thumbnail'] ?? links['smallThumbnail']) as String?;
      if (url == null || url.isEmpty) continue;

      // Ask Google for a larger, flat cover image.
      url = url
          .replaceFirst('http://', 'https://')
          .replaceAll('&edge=curl', '')
          .replaceAll('zoom=1', 'zoom=2');

      final authors = info['authors'];
      final ratings = info['ratingsCount'];

      out.add(
        CoverCandidate(
          url: url,
          source: _isPenguin(info['publisher'] as String?) ? 'Penguin' : 'Google Books',
          title: info['title'] as String?,
          author: authors is List && authors.isNotEmpty ? authors.first as String? : null,
          publisher: info['publisher'] as String?,
          popularity: ratings is num ? ratings.toInt() : 0,
        ),
      );
    }
    return out;
  }

  static Future<List<CoverCandidate>> _openLibrary(String title, String? author) async {
    final params = {
      'title': title,
      'limit': '20',
      'fields': 'title,author_name,cover_i,publisher,edition_count',
    };
    if (author != null && author.trim().isNotEmpty) params['author'] = author;

    final uri = Uri.https('openlibrary.org', '/search.json', params);
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return const [];

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map) return const [];
    final docs = j['docs'];
    if (docs is! List) return const [];

    final out = <CoverCandidate>[];
    for (final d in docs) {
      if (d is! Map) continue;
      final coverId = d['cover_i'];
      if (coverId is! num) continue;

      final publishers = d['publisher'];
      String? publisher;
      if (publishers is List && publishers.isNotEmpty) {
        publisher =
            publishers.firstWhere(
                  (p) => p is String && p.toLowerCase().contains('penguin'),
                  orElse: () => publishers.first,
                )
                as String?;
      }

      final authors = d['author_name'];
      final editions = d['edition_count'];

      out.add(
        CoverCandidate(
          url: 'https://covers.openlibrary.org/b/id/${coverId.toInt()}-L.jpg',
          source: _isPenguin(publisher) ? 'Penguin' : 'Open Library',
          title: d['title'] as String?,
          author: authors is List && authors.isNotEmpty ? authors.first as String? : null,
          publisher: publisher,
          // More editions is a reasonable popularity proxy on Open Library.
          popularity: editions is num ? editions.toInt() : 0,
        ),
      );
    }
    return out;
  }

  /// Apple Books, via the public iTunes Search API. Good, high-resolution art
  /// for modern titles and no quota to exhaust.
  static Future<List<CoverCandidate>> _appleBooks(String title, String? author) async {
    final term = author == null || author.trim().isEmpty ? title : '$title $author';

    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'entity': 'ebook',
      'limit': '20',
    });

    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return const [];

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map) return const [];
    final items = j['results'];
    if (items is! List) return const [];

    final out = <CoverCandidate>[];
    for (final r in items) {
      if (r is! Map) continue;
      final art = r['artworkUrl100'] as String?;
      if (art == null || art.isEmpty) continue;

      out.add(
        CoverCandidate(
          url: art.replaceAll(RegExp(r'/\d+x\d+bb'), '/900x900bb'),
          source: 'Apple Books',
          title: r['trackName'] as String?,
          author: r['artistName'] as String?,
          publisher: null,
          // Apple returns results in relevance order; approximate popularity.
          popularity: (r['userRatingCount'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return out;
  }

  /// Downloads [url] into the app's covers directory. Returns the local path.
  static Future<String?> download(String bookId, String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      // Open Library serves a tiny 1x1 placeholder when it has no art.
      if (res.statusCode != 200 || res.bodyBytes.length < 2048) return null;
      return _write(bookId, res.bodyBytes, extension: 'jpg');
    } catch (_) {
      return null;
    }
  }

  static Future<String> _write(
    String bookId,
    Uint8List bytes, {
    required String extension,
  }) async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/covers');
    if (!await dir.exists()) await dir.create(recursive: true);

    // A fresh filename each time so Flutter's image cache can't serve the old art.
    final file = File(
      '${dir.path}/${bookId}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes);

    // Drop older covers for this book.
    try {
      await for (final e in dir.list()) {
        if (e is File &&
            e.path != file.path &&
            e.uri.pathSegments.last.startsWith('${bookId}_')) {
          await e.delete();
        }
      }
    } catch (_) {
      // best effort
    }
    return file.path;
  }

  // ------------------------------------------------------------------ titles

  /// Turns a filename into a reasonable search title.
  static String titleFromFilename(String filename) {
    var name = filename;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);

    name = name.replaceAll(RegExp(r'[_\-]+'), ' ');
    // Drop common noise from scanned/downloaded files.
    name = name.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    name = name.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    name = name.replaceAll(
      RegExp(
        r'\b(pdf|epub|ebook|z lib|zlib|libgen|annas archive|retail|v\d+)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Trim leftover punctuation from stripped brackets and dotted filenames.
    name = name.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '').trim();

    // Anything without a letter or digit is not a usable title.
    if (!RegExp(r'[A-Za-z0-9]').hasMatch(name)) return 'Untitled';
    return name;
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\b(the|a|an|of|and)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Word-overlap similarity between two normalised titles, 0..1.
  static double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;

    final wa = a.split(' ').toSet();
    final wb = b.split(' ').toSet();
    final shared = wa.intersection(wb).length;
    if (shared == 0) return 0;

    // Bias towards covering the query rather than the candidate, so a longer
    // subtitle on the published edition isn't penalised.
    final coverage = shared / wa.length;
    final precision = shared / wb.length;
    return coverage * 0.75 + precision * 0.25;
  }
}
