import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models.dart';
import '../store.dart';

/// One downloadable file for a catalog result.
class DownloadOption {
  const DownloadOption({
    required this.format,
    required this.url,
    this.bytes,
    this.label,
  });

  final BookFormat format;
  final String url;
  final int? bytes;
  final String? label;

  String get sizeLabel {
    final b = bytes;
    if (b == null || b <= 0) return '';
    if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get title => label ?? format.label;
}

/// A book found in an online catalog, before it is installed.
class CatalogBook {
  CatalogBook({
    required this.id,
    required this.title,
    required this.sourceName,
    this.author,
    this.description,
    this.coverUrl,
    this.language,
    this.publisher,
    this.year,
    this.pageUrl,
    this.downloads = const [],
    this.subjects = const [],
    this.downloadCount,
    this.needsResolve = false,
  });

  final String id;
  final String title;
  final String sourceName;
  final String? author;
  final String? description;
  final String? coverUrl;
  final String? language;
  final String? publisher;
  final int? year;

  /// Human-facing page for the book on the source's website.
  final String? pageUrl;

  List<DownloadOption> downloads;
  final List<String> subjects;

  /// Popularity, where the source reports it.
  final int? downloadCount;

  /// True when [downloads] is only known after a second request.
  final bool needsResolve;

  DownloadOption? get best {
    if (downloads.isEmpty) return null;
    // Prefer EPUB: reflowable text reads far better on a phone than a
    // fixed-layout scan.
    for (final f in [BookFormat.epub, BookFormat.pdf]) {
      for (final d in downloads) {
        if (d.format == f) return d;
      }
    }
    return downloads.first;
  }
}

/// A catalog Libread can search and install books from.
abstract class CatalogSource {
  String get id;
  String get name;
  String get blurb;

  Future<List<CatalogBook>> search(String query);

  /// Fills in download links for sources that need a second request.
  Future<List<DownloadOption>> resolve(CatalogBook book) async => book.downloads;
}

/// Searches every enabled catalog at once and merges the results.
class CatalogService {
  static final List<CatalogSource> builtIn = [
    GutenbergSource(),
    StandardEbooksSource(),
    WikisourceSource(),
    InternetArchiveSource(),
    OpenLibrarySource(),
    FeedbooksSource(),
    ArxivSource(),
  ];

  /// Every source that is currently searchable, including the user's own feeds.
  static List<CatalogSource> all() => [
    ...builtIn,
    for (final f in LibraryStore.instance.customFeeds) CustomOpdsSource(f),
  ];

  static CatalogSource? byId(String id) {
    for (final s in all()) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Runs [query] against [sources] concurrently.
  ///
  /// Results stream back per source via [onResult] so the UI can fill in as
  /// each catalog answers instead of waiting for the slowest one.
  static Future<void> searchAll(
    String query,
    List<CatalogSource> sources, {
    required void Function(CatalogSource source, List<CatalogBook> books, Object? error)
    onResult,
  }) async {
    await Future.wait(
      sources.map((s) async {
        try {
          final books = await s.search(query).timeout(const Duration(seconds: 25));
          onResult(s, books, null);
        } catch (e) {
          onResult(s, const [], e);
        }
      }),
    );
  }
}

// --------------------------------------------------------------- Gutenberg

/// Project Gutenberg, via the Gutendex API. ~75,000 public domain books.
class GutenbergSource extends CatalogSource {
  @override
  String get id => 'gutenberg';
  @override
  String get name => 'Project Gutenberg';
  @override
  String get blurb => '75,000+ free public-domain classics';

  @override
  Future<List<CatalogBook>> search(String query) async {
    // The trailing slash matters: without it Gutendex answers 301.
    final uri = Uri.https('gutendex.com', '/books/', {'search': query});
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return const [];

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map) return const [];
    final results = j['results'];
    if (results is! List) return const [];

    final out = <CatalogBook>[];
    for (final r in results) {
      if (r is! Map) continue;
      final formats = r['formats'];
      if (formats is! Map) continue;

      final downloads = <DownloadOption>[];
      for (final e in formats.entries) {
        final mime = e.key.toString();
        final url = e.value?.toString();
        if (url == null || url.endsWith('.zip')) continue;

        if (mime.startsWith('application/epub')) {
          downloads.add(DownloadOption(format: BookFormat.epub, url: url));
        } else if (mime.startsWith('application/pdf')) {
          downloads.add(DownloadOption(format: BookFormat.pdf, url: url));
        }
      }
      if (downloads.isEmpty) continue;

      final authors = r['authors'];
      String? author;
      int? year;
      if (authors is List && authors.isNotEmpty && authors.first is Map) {
        final a = authors.first as Map;
        author = a['name'] as String?;
        year = (a['birth_year'] as num?)?.toInt();
      }

      final summaries = r['summaries'];
      final languages = r['languages'];
      final subjects = r['subjects'];

      out.add(
        CatalogBook(
          id: 'gutenberg:${r['id']}',
          title: (r['title'] as String?)?.trim() ?? 'Untitled',
          sourceName: name,
          author: _flipName(author),
          description: summaries is List && summaries.isNotEmpty
              ? summaries.first.toString()
              : null,
          coverUrl: formats['image/jpeg']?.toString(),
          language: languages is List && languages.isNotEmpty
              ? languages.first.toString()
              : null,
          publisher: 'Project Gutenberg',
          year: year,
          pageUrl: 'https://www.gutenberg.org/ebooks/${r['id']}',
          downloads: downloads,
          subjects: subjects is List
              ? subjects.take(6).map((e) => e.toString()).toList()
              : const [],
          downloadCount: (r['download_count'] as num?)?.toInt(),
        ),
      );
    }
    return out;
  }

  /// Gutenberg stores authors as "Tolstoy, Leo, graf".
  static String? _flipName(String? name) {
    if (name == null || !name.contains(',')) return name;
    final parts = name.split(',').map((p) => p.trim()).toList();
    if (parts.length < 2) return name;
    return '${parts[1]} ${parts[0]}';
  }
}

// ----------------------------------------------------------- Standard Ebooks

/// Standard Ebooks: public domain works, carefully typeset.
class StandardEbooksSource extends CatalogSource {
  @override
  String get id => 'standardebooks';
  @override
  String get name => 'Standard Ebooks';
  @override
  String get blurb => 'Beautifully typeset public-domain editions';

  @override
  Future<List<CatalogBook>> search(String query) async {
    final uri = Uri.https('standardebooks.org', '/feeds/opds/all', {'query': query});
    // Without this header the site negotiates to HTML.
    final res = await http
        .get(uri, headers: const {'Accept': 'application/atom+xml'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return const [];

    return OpdsParser.parse(utf8.decode(res.bodyBytes), name, baseUrl: 'https://standardebooks.org');
  }
}

// -------------------------------------------------------------- Wikisource

/// Wikisource: the free library of transcribed source texts. Full works are
/// exported to EPUB on demand by the Wikimedia `ws-export` service.
///
/// Search runs against the MediaWiki API; only top-level work pages are kept,
/// so results are whole books rather than individual chapters. Authors are left
/// blank here and filled in from the EPUB's own metadata once installed.
class WikisourceSource extends CatalogSource {
  @override
  String get id => 'wikisource';
  @override
  String get name => 'Wikisource';
  @override
  String get blurb => 'Free library of transcribed books & documents';

  @override
  Future<List<CatalogBook>> search(String query) async {
    final uri = Uri.https('en.wikisource.org', '/w/api.php', {
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'srnamespace': '0',
      'srlimit': '25',
      'srwhat': 'text',
      'format': 'json',
    });

    final res = await http
        .get(uri, headers: const {'User-Agent': 'Libread/2.0 (+flutter)'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return const [];

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map) return const [];
    final results = j['query']?['search'];
    if (results is! List) return const [];

    final out = <CatalogBook>[];
    for (final r in results) {
      if (r is! Map) continue;
      final title = (r['title'] as String?)?.trim();
      if (title == null || title.isEmpty) continue;
      // Subpages ("Work/Chapter 1") are parts of a work; keep whole works only.
      if (title.contains('/')) continue;

      // ws-export takes the page name with underscores for spaces.
      final page = title.replaceAll(' ', '_');
      final epubUrl = Uri.https('ws-export.wmcloud.org', '/', {
        'lang': 'en',
        'format': 'epub',
        'page': page,
      }).toString();

      out.add(
        CatalogBook(
          id: 'wikisource:${r['pageid'] ?? title}',
          title: title,
          sourceName: name,
          description: _stripSnippet(r['snippet'] as String?),
          language: 'en',
          publisher: 'Wikisource',
          pageUrl: 'https://en.wikisource.org/wiki/$page',
          downloads: [DownloadOption(format: BookFormat.epub, url: epubUrl)],
        ),
      );
    }
    return out;
  }

  static String? _stripSnippet(String? s) {
    if (s == null || s.isEmpty) return null;
    final text = s
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty ? null : text;
  }
}

// -------------------------------------------------------------- Feedbooks

/// Feedbooks' public-domain catalog.
class FeedbooksSource extends CatalogSource {
  @override
  String get id => 'feedbooks';
  @override
  String get name => 'Feedbooks';
  @override
  String get blurb => 'Public-domain classics in many languages';

  @override
  Future<List<CatalogBook>> search(String query) async {
    final uri = Uri.https('catalog.feedbooks.com', '/search.atom', {'query': query});
    final res = await http
        .get(uri, headers: const {'Accept': 'application/atom+xml'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return const [];

    // Feedbooks lists paid titles too; the parser keeps only free acquisitions.
    return OpdsParser.parse(utf8.decode(res.bodyBytes), name);
  }
}

// ------------------------------------------------------- Internet Archive

/// The Internet Archive's freely downloadable texts.
///
/// Lending-only collections are excluded, so everything listed can actually
/// be downloaded.
class InternetArchiveSource extends CatalogSource {
  @override
  String get id => 'archive';
  @override
  String get name => 'Internet Archive';
  @override
  String get blurb => 'Millions of scanned, freely downloadable texts';

  @override
  Future<List<CatalogBook>> search(String query) async {
    final q =
        '($query) AND mediatype:texts AND format:(pdf OR epub) '
        'AND -collection:inlibrary AND -collection:printdisabled';

    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': q,
      'fl[]': ['identifier', 'title', 'creator', 'year', 'description', 'language', 'downloads'],
      'rows': '25',
      'page': '1',
      'output': 'json',
    });

    final res = await http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return const [];

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map) return const [];
    final docs = j['response']?['docs'];
    if (docs is! List) return const [];

    return [
      for (final d in docs)
        if (d is Map && d['identifier'] != null)
          CatalogBook(
            id: 'archive:${d['identifier']}',
            title: _first(d['title']) ?? d['identifier'].toString(),
            sourceName: name,
            author: _first(d['creator']),
            description: _first(d['description']),
            coverUrl: 'https://archive.org/services/img/${d['identifier']}',
            language: _first(d['language']),
            year: int.tryParse(_first(d['year']) ?? ''),
            pageUrl: 'https://archive.org/details/${d['identifier']}',
            downloadCount: (d['downloads'] as num?)?.toInt(),
            // File names vary per item, so ask for the manifest on demand.
            needsResolve: true,
          ),
    ];
  }

  @override
  Future<List<DownloadOption>> resolve(CatalogBook book) async {
    final identifier = book.id.split(':').last;
    final uri = Uri.https('archive.org', '/metadata/$identifier');
    final res = await http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return const [];

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map) return const [];
    final files = j['files'];
    if (files is! List) return const [];

    final out = <DownloadOption>[];
    for (final f in files) {
      if (f is! Map) continue;
      final fileName = f['name']?.toString();
      if (fileName == null) continue;

      final lower = fileName.toLowerCase();
      // `_encrypted` / `_lcp` files are DRM-wrapped and won't open.
      if (lower.contains('_encrypted') || lower.contains('_lcp')) continue;

      final format = lower.endsWith('.epub')
          ? BookFormat.epub
          : lower.endsWith('.pdf')
          ? BookFormat.pdf
          : null;
      if (format == null) continue;

      out.add(
        DownloadOption(
          format: format,
          url: 'https://archive.org/download/$identifier/${Uri.encodeComponent(fileName)}',
          bytes: int.tryParse(f['size']?.toString() ?? ''),
        ),
      );
    }
    return out;
  }

  static String? _first(dynamic v) {
    if (v == null) return null;
    if (v is List) return v.isEmpty ? null : v.first?.toString();
    return v.toString();
  }
}

// -------------------------------------------------------------- Open Library

/// Open Library, limited to titles with a free full-text scan.
///
/// The file itself is served by the Internet Archive.
class OpenLibrarySource extends CatalogSource {
  @override
  String get id => 'openlibrary';
  @override
  String get name => 'Open Library';
  @override
  String get blurb => 'Catalog of free, full-text readable editions';

  @override
  Future<List<CatalogBook>> search(String query) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': query,
      'limit': '25',
      // Only editions whose full text is downloadable by anyone.
      'ebook_access': 'public',
      'fields': 'key,title,author_name,cover_i,first_publish_year,language,ia,'
          'subject,publisher,ebook_access',
    });

    final res = await http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return const [];

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map) return const [];
    final docs = j['docs'];
    if (docs is! List) return const [];

    final out = <CatalogBook>[];
    for (final d in docs) {
      if (d is! Map) continue;
      final ia = d['ia'];
      if (ia is! List || ia.isEmpty) continue;
      // Open Library honours `ebook_access` loosely and still returns
      // lending-only editions; those can't be downloaded, so drop them here.
      if (d['ebook_access'] != 'public') continue;

      final authors = d['author_name'];
      final languages = d['language'];
      final subjects = d['subject'];
      final publishers = d['publisher'];
      final coverId = d['cover_i'];

      out.add(
        CatalogBook(
          // The IA identifier is what the download resolves against.
          id: 'archive:${ia.first}',
          title: (d['title'] as String?) ?? 'Untitled',
          sourceName: name,
          author: authors is List && authors.isNotEmpty ? authors.first.toString() : null,
          coverUrl: coverId is num
              ? 'https://covers.openlibrary.org/b/id/${coverId.toInt()}-L.jpg'
              : 'https://archive.org/services/img/${ia.first}',
          language: languages is List && languages.isNotEmpty
              ? languages.first.toString()
              : null,
          publisher: publishers is List && publishers.isNotEmpty
              ? publishers.first.toString()
              : null,
          year: (d['first_publish_year'] as num?)?.toInt(),
          pageUrl: 'https://openlibrary.org${d['key']}',
          subjects: subjects is List
              ? subjects.take(6).map((e) => e.toString()).toList()
              : const [],
          needsResolve: true,
        ),
      );
    }
    return out;
  }

  /// Open Library results are Internet Archive items; reuse its manifest logic.
  @override
  Future<List<DownloadOption>> resolve(CatalogBook book) =>
      InternetArchiveSource().resolve(book);
}

// -------------------------------------------------------------------- arXiv

/// arXiv preprints, as PDFs.
class ArxivSource extends CatalogSource {
  @override
  String get id => 'arxiv';
  @override
  String get name => 'arXiv';
  @override
  String get blurb => 'Open-access research papers and preprints';

  @override
  Future<List<CatalogBook>> search(String query) async {
    final uri = Uri.https('export.arxiv.org', '/api/query', {
      'search_query': 'all:$query',
      'max_results': '25',
      'sortBy': 'relevance',
    });

    final res = await http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return const [];

    final doc = XmlDocument.parse(utf8.decode(res.bodyBytes));

    final out = <CatalogBook>[];
    for (final entry in doc.findAllElements('entry')) {
      final title = _text(entry, 'title');
      if (title == null) continue;

      String? pdf;
      String? page;
      for (final link in entry.findElements('link')) {
        final href = link.getAttribute('href');
        if (href == null) continue;
        if (link.getAttribute('title') == 'pdf') {
          pdf = href;
        } else if (link.getAttribute('rel') == 'alternate') {
          page = href;
        }
      }
      if (pdf == null) continue;

      final authors = entry
          .findElements('author')
          .map((a) => _text(a, 'name'))
          .whereType<String>()
          .toList();

      out.add(
        CatalogBook(
          id: 'arxiv:${_text(entry, 'id') ?? pdf}',
          title: _clean(title),
          sourceName: name,
          author: authors.isEmpty
              ? null
              : authors.length > 3
              ? '${authors.first} et al.'
              : authors.join(', '),
          description: _clean(_text(entry, 'summary') ?? ''),
          publisher: 'arXiv',
          year: int.tryParse((_text(entry, 'published') ?? '').split('-').first),
          pageUrl: page,
          downloads: [DownloadOption(format: BookFormat.pdf, url: pdf)],
          subjects: entry
              .findElements('category')
              .map((c) => c.getAttribute('term') ?? '')
              .where((t) => t.isNotEmpty)
              .take(4)
              .toList(),
        ),
      );
    }
    return out;
  }

  static String? _text(XmlElement parent, String tag) {
    final e = parent.findElements(tag).firstOrNull;
    final v = e?.innerText.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ------------------------------------------------------------ custom feeds

/// A user-supplied OPDS catalog.
class CustomOpdsSource extends CatalogSource {
  CustomOpdsSource(this.feed);

  final CustomFeed feed;

  @override
  String get id => 'custom:${feed.id}';
  @override
  String get name => feed.name;
  @override
  String get blurb => 'Your catalog · ${Uri.tryParse(feed.url)?.host ?? feed.url}';

  @override
  Future<List<CatalogBook>> search(String query) async {
    final hasPlaceholder = feed.url.contains('{query}');
    final url = hasPlaceholder
        ? feed.url.replaceAll('{query}', Uri.encodeQueryComponent(query))
        : feed.url;

    final res = await http
        .get(Uri.parse(url), headers: const {'Accept': 'application/atom+xml'})
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return const [];

    final books = OpdsParser.parse(utf8.decode(res.bodyBytes), name, baseUrl: url);
    if (hasPlaceholder) return books;

    // A plain feed can't search, so filter what it returned.
    final q = query.toLowerCase();
    return books
        .where(
          (b) =>
              b.title.toLowerCase().contains(q) ||
              (b.author ?? '').toLowerCase().contains(q),
        )
        .toList();
  }
}

// ------------------------------------------------------------ OPDS parsing

/// Parses OPDS/Atom catalog feeds, which several sources speak.
class OpdsParser {
  static const _acquisition = 'http://opds-spec.org/acquisition';
  static const _image = 'http://opds-spec.org/image';

  static List<CatalogBook> parse(String xml, String sourceName, {String? baseUrl}) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (_) {
      return const [];
    }

    final out = <CatalogBook>[];
    for (final entry in doc.findAllElements('entry')) {
      final title = _text(entry, 'title');
      if (title == null) continue;

      final downloads = <DownloadOption>[];
      String? cover;
      String? page;

      for (final link in entry.findElements('link')) {
        final rel = link.getAttribute('rel') ?? '';
        final type = link.getAttribute('type') ?? '';
        final href = link.getAttribute('href');
        if (href == null) continue;

        final absolute = _absolute(href, baseUrl);

        if (rel.startsWith(_image)) {
          // Prefer the full image over the thumbnail.
          if (cover == null || rel == _image) cover = absolute;
          continue;
        }
        if (rel == 'alternate' && type.contains('html')) {
          page = absolute;
          continue;
        }
        // Skip paid and sample acquisitions; we only install free files.
        if (!rel.startsWith(_acquisition)) continue;
        if (rel.contains('buy') || rel.contains('sample') || rel.contains('subscribe')) {
          continue;
        }

        // `application/kepub+zip` is a Kobo-specific EPUB variant; the plain
        // EPUB alongside it is always the better choice.
        if (type.contains('kepub')) continue;

        final format = type.contains('epub')
            ? BookFormat.epub
            : type.contains('pdf')
            ? BookFormat.pdf
            : null;
        if (format == null) continue;

        downloads.add(
          DownloadOption(
            format: format,
            url: absolute,
            bytes: int.tryParse(link.getAttribute('length') ?? ''),
            // Feeds that publish several editions name them here.
            label: link.getAttribute('title'),
          ),
        );
      }
      if (downloads.isEmpty) continue;

      final author = entry.findElements('author').firstOrNull;
      final published = _text(entry, 'issued') ?? _text(entry, 'published');

      out.add(
        CatalogBook(
          id: '${sourceName.toLowerCase()}:${_text(entry, 'id') ?? title}',
          title: title,
          sourceName: sourceName,
          author: author == null ? null : _text(author, 'name'),
          description: _stripTags(_text(entry, 'summary') ?? _text(entry, 'content') ?? ''),
          coverUrl: cover,
          language: _text(entry, 'language'),
          publisher: _text(entry, 'publisher'),
          year: int.tryParse((published ?? '').split('-').first),
          pageUrl: page,
          downloads: downloads,
          subjects: entry
              .findElements('category')
              .map((c) => c.getAttribute('label') ?? c.getAttribute('term') ?? '')
              .where((t) => t.isNotEmpty)
              .take(6)
              .toList(),
        ),
      );
    }
    return out;
  }

  /// Finds a child by local name, ignoring the namespace prefix the feed uses.
  static String? _text(XmlElement parent, String localName) {
    for (final child in parent.childElements) {
      if (child.name.local != localName) continue;
      final v = child.innerText.trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  static String _absolute(String href, String? baseUrl) {
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    if (baseUrl == null) return href;
    final base = Uri.tryParse(baseUrl);
    if (base == null) return href;
    return base.resolve(href).toString();
  }

  static String _stripTags(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#8217;', '’')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
