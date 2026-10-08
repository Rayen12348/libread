import 'dart:convert';

import 'package:http/http.dart' as http;

class TranslationResult {
  const TranslationResult({
    required this.text,
    required this.sourceLang,
    required this.provider,
  });

  final String text;
  final String sourceLang;
  final String provider;
}

/// Languages offered in the translate sheet.
const Map<String, String> kLanguages = {
  'ar': 'Arabic',
  'en': 'English',
  'fr': 'French',
  'es': 'Spanish',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'tr': 'Turkish',
  'ru': 'Russian',
  'zh-CN': 'Chinese',
  'ja': 'Japanese',
  'hi': 'Hindi',
};

/// Translates text using Google's public endpoint, falling back to MyMemory.
/// Neither requires an API key.
class TranslateService {
  static Future<TranslationResult> translate(String text, String targetLang) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const TranslationResult(text: '', sourceLang: '', provider: '');
    }

    try {
      final r = await _google(trimmed, targetLang);
      if (r != null) return r;
    } catch (_) {
      // fall through to the backup provider
    }

    try {
      final r = await _myMemory(trimmed, targetLang);
      if (r != null) return r;
    } catch (_) {
      // handled below
    }

    throw Exception('Could not translate. Check your internet connection.');
  }

  static Future<TranslationResult?> _google(String text, String target) async {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'auto',
      'tl': target,
      'dt': 't',
      'q': text,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! List || decoded.isEmpty) return null;

    final segments = decoded[0];
    if (segments is! List) return null;

    final buffer = StringBuffer();
    for (final seg in segments) {
      if (seg is List && seg.isNotEmpty && seg[0] is String) {
        buffer.write(seg[0] as String);
      }
    }

    final source = decoded.length > 2 && decoded[2] is String ? decoded[2] as String : 'auto';
    final out = buffer.toString().trim();
    if (out.isEmpty) return null;

    return TranslationResult(text: out, sourceLang: source, provider: 'Google');
  }

  static Future<TranslationResult?> _myMemory(String text, String target) async {
    // MyMemory needs an explicit source language; English is the common case.
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': text,
      'langpair': 'en|${target.split('-').first}',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map) return null;
    final data = j['responseData'];
    if (data is! Map) return null;
    final out = (data['translatedText'] as String?)?.trim();
    if (out == null || out.isEmpty) return null;

    return TranslationResult(text: out, sourceLang: 'en', provider: 'MyMemory');
  }
}
