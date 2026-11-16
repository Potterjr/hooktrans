/// Fallback engine: Google Translate's public web endpoint. No API key, but
/// it is unofficial, needs internet, and may rate-limit heavy use.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'translator.dart';

/// Language names used in the UI mapped to Google language codes.
const googleLanguageCodes = <String, String>{
  'Thai': 'th',
  'English': 'en',
  'Japanese': 'ja',
  'Chinese': 'zh-CN',
  'Korean': 'ko',
  'Vietnamese': 'vi',
  'Indonesian': 'id',
};

/// Joins the translated segments of the `translate_a/single` response.
String parseGoogleResponse(String body) {
  final json = jsonDecode(body);
  if (json is! List || json.isEmpty || json[0] is! List) {
    throw TranslatorException('Unexpected Google response');
  }
  final buf = StringBuffer();
  for (final seg in json[0] as List<dynamic>) {
    if (seg is List && seg.isNotEmpty && seg[0] is String) buf.write(seg[0]);
  }
  return buf.toString().trim();
}

class GoogleTranslator implements Translator {
  GoogleTranslator({
    this.targetLanguage = 'th',
    this.sourceLanguage = 'auto',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String targetLanguage;
  final String sourceLanguage;
  final http.Client _client;

  @override
  Stream<String> translate(String text, List<Exchange> history) async* {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': sourceLanguage,
      'tl': targetLanguage,
      'dt': 't',
      'q': text,
    });
    final http.Response res;
    try {
      res = await _client.get(uri);
    } catch (e) {
      throw TranslatorException('Cannot reach Google Translate: $e');
    }
    if (res.statusCode != 200) {
      throw TranslatorException('Google Translate returned ${res.statusCode}');
    }
    yield parseGoogleResponse(utf8.decode(res.bodyBytes));
  }
}
