import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

/// The kind of block a chapter is built from.
enum EpubBlockType { heading, paragraph, quote, listItem, image, rule }

/// A run of text inside a block, with the inline styling that applies to it.
class EpubSpan {
  const EpubSpan(this.text, {this.bold = false, this.italic = false, this.code = false});

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
}

/// One renderable element of a chapter.
class EpubBlock {
  const EpubBlock(this.type, {this.spans = const [], this.level = 0, this.imagePath});

  final EpubBlockType type;
  final List<EpubSpan> spans;

  /// Heading depth, 1..6.
  final int level;

  /// Absolute path of an extracted image, for [EpubBlockType.image].
  final String? imagePath;

  String get text => spans.map((s) => s.text).join();
}

/// A spine entry: one XHTML document from the book.
class EpubChapter {
  EpubChapter({required this.title, required this.href});

  final String title;
  final String href;

  /// Parsed lazily by [EpubService.loadChapter].
  List<EpubBlock>? blocks;
}

/// An opened EPUB: metadata plus its ordered chapters.
class EpubBook {
  EpubBook({
    required this.rootDir,
    required this.opfDir,
    required this.chapters,
    this.title,
    this.author,
    this.language,
    this.description,
    this.coverPath,
  });

  /// Directory the archive was unpacked into.
  final String rootDir;

  /// Directory the OPF lives in; hrefs are relative to it.
  final String opfDir;

  final List<EpubChapter> chapters;
  final String? title;
  final String? author;
  final String? language;
  final String? description;
  final String? coverPath;
}

/// Reads EPUB files: metadata, cover art, and chapter content.
///
/// EPUBs are zip archives of XHTML. Books are unpacked once into a cache
/// directory, then chapters are parsed on demand as the reader needs them.
class EpubService {
  /// Reads just the metadata and cover from an EPUB without unpacking it.
  ///
  /// Used at import time, when all we need is a title and a cover image.
  static Future<({String? title, String? author, String? language, String? description, Uint8List? cover})>
  peek(String epubPath) async {
    try {
      final archive = await _openArchive(epubPath);
      final opfPath = _findOpfPath(archive);
      if (opfPath == null) return (title: null, author: null, language: null, description: null, cover: null);

      final opfXml = _parseXml(_readString(archive, opfPath));
      if (opfXml == null) return (title: null, author: null, language: null, description: null, cover: null);

      final opfDir = _dirOf(opfPath);
      final meta = _metadata(opfXml);
      final coverHref = _coverHref(opfXml);

      Uint8List? cover;
      if (coverHref != null) {
        cover = _readBytes(archive, _resolve(opfDir, coverHref));
      }
      // Some books omit the cover declaration; fall back to the largest image.
      cover ??= _largestImage(archive);

      return (
        title: meta.title,
        author: meta.author,
        language: meta.language,
        description: meta.description,
        cover: cover,
      );
    } catch (_) {
      return (title: null, author: null, language: null, description: null, cover: null);
    }
  }

  /// Unpacks [epubPath] into a per-book cache directory and reads its spine.
  static Future<EpubBook?> open(String epubPath, String bookId) async {
    try {
      final cache = Directory(
        '${(await getApplicationSupportDirectory()).path}/epub/$bookId',
      );

      final archive = await _openArchive(epubPath);
      final opfPath = _findOpfPath(archive);
      if (opfPath == null) return null;

      // Unpack once; a marker file records that the last run finished.
      final marker = File('${cache.path}/.unpacked');
      if (!await marker.exists()) {
        if (await cache.exists()) await cache.delete(recursive: true);
        await cache.create(recursive: true);
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          final content = entry.readBytes();
          if (content == null) continue;
          final out = File('${cache.path}/${entry.name}');
          await out.parent.create(recursive: true);
          await out.writeAsBytes(content);
        }
        await marker.writeAsString('1');
      }

      final opfXml = _parseXml(_readString(archive, opfPath));
      if (opfXml == null) return null;

      final opfDir = _dirOf(opfPath);
      final meta = _metadata(opfXml);

      // manifest id -> href
      final manifest = <String, String>{};
      final mediaTypes = <String, String>{};
      for (final item in opfXml.findAllElements('item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        if (id == null || href == null) continue;
        manifest[id] = href;
        mediaTypes[id] = item.getAttribute('media-type') ?? '';
      }

      final titles = _navTitles(archive, opfXml, opfDir, manifest);

      final chapters = <EpubChapter>[];
      for (final ref in opfXml.findAllElements('itemref')) {
        final idref = ref.getAttribute('idref');
        if (idref == null) continue;
        final href = manifest[idref];
        if (href == null) continue;
        final type = mediaTypes[idref] ?? '';
        if (type.isNotEmpty && !type.contains('html')) continue;

        final full = _resolve(opfDir, href);
        chapters.add(
          EpubChapter(
            title: titles[full] ?? titles[href] ?? 'Chapter ${chapters.length + 1}',
            href: full,
          ),
        );
      }
      if (chapters.isEmpty) return null;

      String? coverPath;
      final coverHref = _coverHref(opfXml);
      if (coverHref != null) {
        final f = File('${cache.path}/${_resolve(opfDir, coverHref)}');
        if (await f.exists()) coverPath = f.path;
      }

      return EpubBook(
        rootDir: cache.path,
        opfDir: opfDir,
        chapters: chapters,
        title: meta.title,
        author: meta.author,
        language: meta.language,
        description: meta.description,
        coverPath: coverPath,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses one chapter's XHTML into renderable blocks, caching the result.
  static Future<List<EpubBlock>> loadChapter(EpubBook book, EpubChapter chapter) async {
    final cached = chapter.blocks;
    if (cached != null) return cached;

    try {
      final file = File('${book.rootDir}/${chapter.href}');
      if (!await file.exists()) return chapter.blocks = const [];

      final html = await file.readAsString();
      final blocks = _htmlToBlocks(html, '${book.rootDir}/${_dirOf(chapter.href)}');
      return chapter.blocks = blocks;
    } catch (_) {
      return chapter.blocks = const [];
    }
  }

  /// Removes the unpacked cache for a book.
  static Future<void> clearCache(String bookId) async {
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/epub/$bookId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // best effort
    }
  }

  // ------------------------------------------------------------- archive io

  static Future<Archive> _openArchive(String path) async {
    final bytes = await File(path).readAsBytes();
    return ZipDecoder().decodeBytes(bytes);
  }

  static ArchiveFile? _find(Archive archive, String name) {
    final target = name.toLowerCase();
    for (final f in archive.files) {
      if (f.isFile && f.name.toLowerCase() == target) return f;
    }
    return null;
  }

  static String? _readString(Archive archive, String name) {
    final bytes = _readBytes(archive, name);
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _readBytes(Archive archive, String name) {
    final f = _find(archive, name);
    if (f == null) return null;
    final data = f.readBytes();
    return data == null ? null : Uint8List.fromList(data);
  }

  /// Locates the OPF package document via `META-INF/container.xml`.
  static String? _findOpfPath(Archive archive) {
    final container = _readString(archive, 'META-INF/container.xml');
    if (container != null) {
      final xml = _parseXml(container);
      final rootfile = xml?.findAllElements('rootfile').firstOrNull;
      final path = rootfile?.getAttribute('full-path');
      if (path != null && path.isNotEmpty) return path;
    }
    // Malformed book: look for any .opf in the archive.
    for (final f in archive.files) {
      if (f.isFile && f.name.toLowerCase().endsWith('.opf')) return f.name;
    }
    return null;
  }

  static XmlDocument? _parseXml(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      return XmlDocument.parse(source);
    } catch (_) {
      // Real-world EPUBs carry undeclared HTML entities; neutralise them and retry.
      try {
        return XmlDocument.parse(_escapeEntities(source));
      } catch (_) {
        return null;
      }
    }
  }

  /// Replaces named HTML entities XML doesn't know about with numeric ones.
  static String _escapeEntities(String s) => s.replaceAllMapped(
    RegExp(r'&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)([a-zA-Z][a-zA-Z0-9]*);'),
    (m) => _entities[m.group(1)] ?? ' ',
  );

  static const _entities = <String, String>{
    'nbsp': ' ',
    'mdash': '—',
    'ndash': '–',
    'hellip': '…',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'deg': '°',
    'eacute': 'é',
    'egrave': 'è',
    'agrave': 'à',
    'ccedil': 'ç',
    'uuml': 'ü',
    'ouml': 'ö',
    'auml': 'ä',
    'szlig': 'ß',
    'pound': '£',
    'euro': '€',
    'sect': '§',
    'para': '¶',
    'dagger': '†',
    'bull': '•',
    'middot': '·',
    'laquo': '«',
    'raquo': '»',
    'times': '×',
    'frac12': '½',
  };

  // -------------------------------------------------------------- metadata

  static ({String? title, String? author, String? language, String? description}) _metadata(
    XmlDocument opf,
  ) {
    String? pick(String name) {
      for (final e in opf.findAllElements(name, namespaceUri: '*')) {
        final v = e.innerText.trim();
        if (v.isNotEmpty) return v;
      }
      return null;
    }

    return (
      title: pick('title'),
      author: pick('creator'),
      language: pick('language'),
      description: _stripTags(pick('description') ?? ''),
    );
  }

  /// Finds the cover image href, via EPUB 3 properties or the EPUB 2 meta tag.
  static String? _coverHref(XmlDocument opf) {
    for (final item in opf.findAllElements('item')) {
      final props = item.getAttribute('properties') ?? '';
      if (props.contains('cover-image')) return item.getAttribute('href');
    }

    String? coverId;
    for (final meta in opf.findAllElements('meta')) {
      if (meta.getAttribute('name') == 'cover') {
        coverId = meta.getAttribute('content');
        break;
      }
    }
    if (coverId != null) {
      for (final item in opf.findAllElements('item')) {
        if (item.getAttribute('id') == coverId) return item.getAttribute('href');
      }
    }

    // Last resort: a manifest image whose id or href mentions "cover".
    for (final item in opf.findAllElements('item')) {
      final type = item.getAttribute('media-type') ?? '';
      if (!type.startsWith('image/')) continue;
      final id = (item.getAttribute('id') ?? '').toLowerCase();
      final href = item.getAttribute('href') ?? '';
      if (id.contains('cover') || href.toLowerCase().contains('cover')) return href;
    }
    return null;
  }

  /// The biggest image in the archive, a decent guess at cover art.
  static Uint8List? _largestImage(Archive archive) {
    ArchiveFile? best;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final n = f.name.toLowerCase();
      if (!n.endsWith('.jpg') && !n.endsWith('.jpeg') && !n.endsWith('.png')) continue;
      if (best == null || f.size > best.size) best = f;
    }
    if (best == null || best.size < 4096) return null;
    final data = best.readBytes();
    return data == null ? null : Uint8List.fromList(data);
  }

  /// Maps chapter hrefs to their human titles, from the EPUB 3 nav or NCX.
  static Map<String, String> _navTitles(
    Archive archive,
    XmlDocument opf,
    String opfDir,
    Map<String, String> manifest,
  ) {
    final out = <String, String>{};

    void record(String? href, String title) {
      if (href == null || title.trim().isEmpty) return;
      final clean = href.split('#').first;
      out[_resolve(opfDir, clean)] = title.trim();
    }

    // EPUB 3 navigation document.
    for (final item in opf.findAllElements('item')) {
      if (!(item.getAttribute('properties') ?? '').contains('nav')) continue;
      final href = item.getAttribute('href');
      if (href == null) continue;
      final nav = _parseXml(_readString(archive, _resolve(opfDir, href)));
      if (nav == null) continue;
      final navDir = _dirOf(_resolve(opfDir, href));
      for (final a in nav.findAllElements('a')) {
        final target = a.getAttribute('href');
        if (target == null) continue;
        out[_resolve(navDir, target.split('#').first)] = a.innerText.trim();
      }
    }
    if (out.isNotEmpty) return out;

    // EPUB 2 NCX.
    for (final entry in manifest.entries) {
      if (!entry.value.toLowerCase().endsWith('.ncx')) continue;
      final ncx = _parseXml(_readString(archive, _resolve(opfDir, entry.value)));
      if (ncx == null) continue;
      for (final point in ncx.findAllElements('navPoint')) {
        final label = point.findAllElements('text').firstOrNull?.innerText ?? '';
        final content = point.findAllElements('content').firstOrNull;
        record(content?.getAttribute('src'), label);
      }
    }
    return out;
  }

  // ------------------------------------------------------------ html → blocks

  static const _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'li', 'blockquote', 'pre', 'section', 'article', 'td', 'tr', 'figcaption',
  };

  static List<EpubBlock> _htmlToBlocks(String html, String baseDir) {
    final doc = _parseXml(html) ?? _parseXml(_wrapFragment(html));
    if (doc == null) return _plainTextFallback(html);

    final body = doc.findAllElements('body').firstOrNull ?? doc.rootElement;
    final blocks = <EpubBlock>[];
    _walk(body, blocks, baseDir, const _InlineStyle());

    // Fold consecutive text into blocks; drop empties.
    return blocks.where((b) {
      if (b.type == EpubBlockType.image || b.type == EpubBlockType.rule) return true;
      return b.text.trim().isNotEmpty;
    }).toList();
  }

  static String _wrapFragment(String html) {
    // Strip doctype/processing instructions and wrap, for fragments that
    // aren't well-formed documents on their own.
    final cleaned = html
        .replaceAll(RegExp(r'<\?xml[^>]*\?>'), '')
        .replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '')
        // Void tags left unclosed are the usual reason a chapter won't parse
        // as XML. `replaceAll` takes its replacement literally, so the group
        // references have to go through `replaceAllMapped`.
        .replaceAllMapped(
          RegExp(r'<(br|hr|img|meta|link)([^>]*?)/?>', caseSensitive: false),
          (m) => '<${m[1]}${m[2]}/>',
        );
    return '<root>${_escapeEntities(cleaned)}</root>';
  }

  static void _walk(
    XmlNode node,
    List<EpubBlock> out,
    String baseDir,
    _InlineStyle style, {
    List<EpubSpan>? sink,
  }) {
    for (final child in node.children) {
      if (child is XmlText || child is XmlCDATA) {
        final raw = child.value ?? '';
        final text = raw.replaceAll(RegExp(r'\s+'), ' ');
        if (text.trim().isEmpty && sink == null) continue;
        if (sink != null) {
          sink.add(EpubSpan(text, bold: style.bold, italic: style.italic, code: style.code));
        }
        continue;
      }
      if (child is! XmlElement) continue;

      final tag = child.name.local.toLowerCase();

      if (tag == 'script' || tag == 'style' || tag == 'head') continue;

      if (tag == 'br') {
        sink?.add(const EpubSpan('\n'));
        continue;
      }
      if (tag == 'hr') {
        out.add(const EpubBlock(EpubBlockType.rule));
        continue;
      }
      if (tag == 'img' || tag == 'image') {
        final src = child.getAttribute('src') ?? child.getAttribute('xlink:href');
        if (src != null && !src.startsWith('data:')) {
          out.add(EpubBlock(EpubBlockType.image, imagePath: _resolve(baseDir, src)));
        }
        continue;
      }

      if (_blockTags.contains(tag)) {
        final spans = <EpubSpan>[];
        _walk(child, out, baseDir, style, sink: spans);

        if (spans.isNotEmpty) {
          final type = switch (tag) {
            'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' => EpubBlockType.heading,
            'blockquote' || 'pre' => EpubBlockType.quote,
            'li' => EpubBlockType.listItem,
            _ => EpubBlockType.paragraph,
          };
          final level = type == EpubBlockType.heading ? int.parse(tag.substring(1)) : 0;
          out.add(EpubBlock(type, spans: _tidy(spans), level: level));
        }
        continue;
      }

      // Inline element: carry its styling down into the current sink.
      final next = style.merge(tag);
      if (sink != null) {
        _walk(child, out, baseDir, next, sink: sink);
      } else {
        _walk(child, out, baseDir, next);
      }
    }
  }

  /// Trims leading/trailing whitespace across a block's spans.
  static List<EpubSpan> _tidy(List<EpubSpan> spans) {
    final out = <EpubSpan>[];
    for (final s in spans) {
      if (out.isEmpty && s.text.trim().isEmpty) continue;
      out.add(s);
    }
    while (out.isNotEmpty && out.last.text.trim().isEmpty) {
      out.removeLast();
    }
    if (out.isEmpty) return out;

    out[0] = EpubSpan(
      out.first.text.trimLeft(),
      bold: out.first.bold,
      italic: out.first.italic,
      code: out.first.code,
    );
    out[out.length - 1] = EpubSpan(
      out.last.text.trimRight(),
      bold: out.last.bold,
      italic: out.last.italic,
      code: out.last.code,
    );
    return out;
  }

  /// Used when a chapter won't parse as XML at all.
  static List<EpubBlock> _plainTextFallback(String html) {
    final text = _stripTags(html);
    return [
      for (final para in text.split(RegExp(r'\n\s*\n')))
        if (para.trim().isNotEmpty)
          EpubBlock(EpubBlockType.paragraph, spans: [EpubSpan(para.trim())]),
    ];
  }

  static String _stripTags(String html) => html
      .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', dotAll: true, caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
      .replaceAll(RegExp(r'&lt;', caseSensitive: false), '<')
      .replaceAll(RegExp(r'&gt;', caseSensitive: false), '>')
      .replaceAll(RegExp(r'&#\d+;'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();

  // ----------------------------------------------------------------- paths

  static String _dirOf(String path) {
    final i = path.lastIndexOf('/');
    return i == -1 ? '' : path.substring(0, i);
  }

  /// Resolves a relative href against a directory, collapsing `..` segments.
  static String _resolve(String dir, String href) {
    if (href.startsWith('/')) href = href.substring(1);
    final parts = <String>[];
    for (final segment in [...dir.split('/'), ...href.split('/')]) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    return parts.join('/');
  }
}

/// Inline styling accumulated while walking nested tags.
class _InlineStyle {
  const _InlineStyle({this.bold = false, this.italic = false, this.code = false});

  final bool bold;
  final bool italic;
  final bool code;

  _InlineStyle merge(String tag) => switch (tag) {
    'b' || 'strong' => _InlineStyle(bold: true, italic: italic, code: code),
    'i' || 'em' || 'cite' || 'dfn' => _InlineStyle(bold: bold, italic: true, code: code),
    'code' || 'kbd' || 'samp' || 'tt' => _InlineStyle(bold: bold, italic: italic, code: true),
    _ => this,
  };
}
