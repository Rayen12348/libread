import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../store.dart';
import 'catalog.dart';
import 'covers.dart';
import 'epub.dart';

enum DownloadState { queued, downloading, processing, done, failed }

/// A single in-flight (or finished) book install.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.title,
    required this.sourceName,
    required this.format,
  });

  final String id;
  final String title;
  final String sourceName;
  final BookFormat format;

  DownloadState state = DownloadState.queued;

  /// 0..1, or null when the server doesn't report a content length.
  double? progress;
  int received = 0;
  int? total;
  String? error;
  String? bookId;

  String get sizeLabel {
    String fmt(int b) => b < 1024 * 1024
        ? '${(b / 1024).round()} KB'
        : '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    final t = total;
    return t == null ? fmt(received) : '${fmt(received)} / ${fmt(t)}';
  }
}

/// Downloads books from catalogs and imports files from the device.
///
/// Installs run here rather than in a screen so they keep going when the user
/// navigates away.
class Importer extends ChangeNotifier {
  Importer._();

  static final Importer instance = Importer._();

  final List<DownloadTask> _tasks = [];

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  List<DownloadTask> get active => _tasks
      .where((t) => t.state == DownloadState.downloading || t.state == DownloadState.queued)
      .toList();

  bool isInstalling(String catalogId) =>
      _tasks.any((t) => t.id == catalogId && t.state != DownloadState.failed);

  void clearFinished() {
    _tasks.removeWhere(
      (t) => t.state == DownloadState.done || t.state == DownloadState.failed,
    );
    notifyListeners();
  }

  // ------------------------------------------------------------- catalog

  /// Downloads [option] and adds the resulting book to the library.
  Future<Book?> install(CatalogBook catalog, DownloadOption option) async {
    final task = DownloadTask(
      id: catalog.id,
      title: catalog.title,
      sourceName: catalog.sourceName,
      format: option.format,
    );
    _tasks.insert(0, task);
    notifyListeners();

    try {
      task.state = DownloadState.downloading;
      task.total = option.bytes;
      notifyListeners();

      final id = newId();
      final dest = await _bookFile(id, option.format);

      await _download(
        option.url,
        dest,
        onProgress: (received, total) {
          task.received = received;
          task.total = total ?? option.bytes;
          final t = task.total;
          task.progress = (t != null && t > 0) ? received / t : null;
          notifyListeners();
        },
      );

      task.state = DownloadState.processing;
      task.progress = null;
      notifyListeners();

      final book = Book(
        id: id,
        title: catalog.title,
        author: catalog.author,
        description: catalog.description,
        filePath: dest.path,
        addedAt: DateTime.now(),
        format: option.format,
        sourceName: catalog.sourceName,
        sourceUrl: option.url,
        language: catalog.language,
        year: catalog.year,
        tags: catalog.subjects.take(3).toList(),
      );

      // The catalog's own artwork is the most accurate cover available.
      if (catalog.coverUrl != null) {
        final path = await CoverService.download(id, catalog.coverUrl!);
        if (path != null) {
          book.coverPath = path;
          book.coverUrl = catalog.coverUrl;
          book.coverSource = catalog.sourceName;
        }
      }
      if (book.coverPath == null) {
        await CoverService.refresh(book, preferOnline: false);
      }

      await _fillMetadata(book);
      await LibraryStore.instance.addBook(book);

      task.state = DownloadState.done;
      task.bookId = book.id;
      notifyListeners();
      return book;
    } catch (e) {
      task.state = DownloadState.failed;
      task.error = _friendlyError(e);
      notifyListeners();
      return null;
    }
  }

  /// Installs a book straight from a download URL the user supplied.
  Future<Book?> installFromUrl(String rawUrl, {String? title}) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const FormatException('That does not look like a http(s) link.');
    }

    final fileName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final format = BookFormat.fromPath(fileName);

    final catalog = CatalogBook(
      id: 'url:$url',
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : CoverService.titleFromFilename(fileName.isEmpty ? 'Untitled' : fileName),
      sourceName: uri.host,
      downloads: [DownloadOption(format: format, url: url)],
    );

    return install(catalog, catalog.downloads.first);
  }

  // --------------------------------------------------------------- device

  /// Copies PDFs and EPUBs picked from the device into the library.
  ///
  /// Returns the imported books; the caller can then upgrade their covers.
  Future<List<Book>> importFromDevice() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'epub'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return const [];

    final out = <Book>[];
    for (final picked in result.files) {
      final srcPath = picked.path;
      if (srcPath == null) continue;

      final format = BookFormat.fromPath(picked.name);
      final id = newId();

      // Copy into app storage so the book survives the picker's temp grant.
      final dest = await _bookFile(id, format);
      await File(srcPath).copy(dest.path);

      final book = Book(
        id: id,
        title: CoverService.titleFromFilename(picked.name),
        filePath: dest.path,
        addedAt: DateTime.now(),
        format: format,
        sourceName: 'This device',
      );

      await _fillMetadata(book);
      // Give every book a real cover immediately; the online lookup that
      // follows can only improve on it.
      await CoverService.refresh(book, preferOnline: false);

      await LibraryStore.instance.addBook(book);
      out.add(book);
    }
    return out;
  }

  /// Reads the title, author and page count out of the file itself.
  Future<void> _fillMetadata(Book book) async {
    try {
      if (book.format == BookFormat.epub) {
        final meta = await EpubService.peek(book.filePath);
        final title = meta.title?.trim();
        if (title != null && title.isNotEmpty && _looksWeak(book.title)) {
          book.title = title;
        }
        book.author ??= meta.author?.trim();
        book.language ??= meta.language?.split('-').first;
        book.description ??= meta.description;
      }
    } catch (_) {
      // metadata is a nicety; never block an import on it
    }
  }

  /// True when a filename-derived title is poor enough to prefer the file's own.
  static bool _looksWeak(String title) =>
      title.length < 4 ||
      title == 'Untitled' ||
      RegExp(r'^[\d\s\-_.]+$').hasMatch(title);

  // ------------------------------------------------------------- plumbing

  static Future<File> _bookFile(String id, BookFormat format) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/books');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$id.${format == BookFormat.epub ? 'epub' : 'pdf'}');
  }

  /// Streams [url] to [dest], reporting progress as bytes arrive.
  static Future<void> _download(
    String url,
    File dest, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..headers['User-Agent'] = 'Libread/2.0 (+flutter)';

      final response = await client.send(request).timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw HttpException('Server answered ${response.statusCode}', uri: Uri.parse(url));
      }

      final total = response.contentLength;
      var received = 0;

      sink = dest.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final size = await dest.length();
      if (size < 1024) {
        await dest.delete();
        throw const FileSystemException('The download was empty.');
      }
    } catch (_) {
      await sink?.close();
      if (await dest.exists()) {
        try {
          await dest.delete();
        } catch (_) {
          // best effort
        }
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  static String _friendlyError(Object e) {
    if (e is TimeoutException) return 'The download timed out.';
    if (e is SocketException) return 'No connection to the server.';
    if (e is HttpException) return e.message;
    if (e is FormatException) return e.message;
    if (e is FileSystemException) return e.message;
    return e.toString().replaceFirst('Exception: ', '');
  }
}
