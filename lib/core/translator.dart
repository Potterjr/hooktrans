/// Local LLM translation through LM Studio's OpenAI-compatible server
/// (default http://localhost:1234/v1).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One previously translated line, sent back as context.
class Exchange {
  const Exchange(this.source, this.target);
  final String source;
  final String target;
}

/// Options that shape the prompt.
class TranslateOptions {
  const TranslateOptions({
    this.targetLanguage = 'Thai',
    this.sourceLanguage = 'auto',
    this.historyLines = 4,
    this.glossary = const {},
    this.noThink = true,
  });

  final String targetLanguage;
  final String sourceLanguage;
  final int historyLines;

  /// Fixed term translations (character names, places) the model must keep.
  final Map<String, String> glossary;

  /// Appends `/no_think` so Qwen3-style models skip chain of thought, which
  /// otherwise adds seconds of latency per line.
  final bool noThink;
}

/// Builds the system prompt. Kept separate so tests can pin it down.
String buildSystemPrompt(TranslateOptions o) {
  final src = o.sourceLanguage == 'auto'
      ? 'the source language (usually Japanese or English)'
      : o.sourceLanguage;
  final buf = StringBuffer()
    ..writeln(
      'You are a professional video game localizer. Translate each line of '
      'game dialogue from $src into ${o.targetLanguage}.',
    )
    ..writeln('Rules:')
    ..writeln('- Output only the translation, nothing else. No notes, no quotes, '
        'no romanization, no source text.')
    ..writeln('- Keep the tone, register and character voice. Casual stays '
        'casual, rude stays rude.')
    ..writeln('- Keep speaker names, placeholders and symbols as they are.')
    ..writeln('- Previous lines are given only for context; translate only '
        'the last user message.');
  if (o.glossary.isNotEmpty) {
    buf.writeln('Glossary (always use these):');
    o.glossary.forEach((k, v) => buf.writeln('- $k = $v'));
  }
  if (o.noThink) buf.writeln('/no_think');
  return buf.toString().trim();
}

/// Builds the chat message list (OpenAI format).
List<Map<String, String>> buildMessages(
  String text,
  List<Exchange> history,
  TranslateOptions o,
) {
  final msgs = <Map<String, String>>[
    {'role': 'system', 'content': buildSystemPrompt(o)},
  ];
  final start = history.length > o.historyLines
      ? history.length - o.historyLines
      : 0;
  for (final e in history.sublist(start)) {
    msgs.add({'role': 'user', 'content': e.source});
    msgs.add({'role': 'assistant', 'content': e.target});
  }
  msgs.add({'role': 'user', 'content': text});
  return msgs;
}

/// Removes thinking blocks and wrapping quotes some models add.
String postProcess(String raw) {
  var t = raw.replaceAll(RegExp(r'<think>[\s\S]*?(</think>|$)'), '').trim();
  if (t.length >= 2) {
    const pairs = {'"': '"', '「': '」', '“': '”', "'": "'"};
    final first = t[0];
    final last = t[t.length - 1];
    if (pairs[first] == last) t = t.substring(1, t.length - 1).trim();
  }
  return t;
}

/// Extracts the text delta from one SSE `data:` payload of
/// /v1/chat/completions. Returns null for `[DONE]` and non-content chunks.
String? parseSseDelta(String line) {
  if (!line.startsWith('data:')) return null;
  final payload = line.substring(5).trim();
  if (payload.isEmpty || payload == '[DONE]') return null;
  final json = jsonDecode(payload) as Map<String, dynamic>;
  if (json['error'] != null) throw TranslatorException('${json['error']}');
  final choices = json['choices'] as List<dynamic>?;
  if (choices == null || choices.isEmpty) return null;
  final delta = (choices.first as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
  return delta?['content'] as String?;
}

abstract class Translator {
  /// Streams the translation as the model produces it. Each element is the
  /// full text so far; consumers just show the latest.
  Stream<String> translate(String text, List<Exchange> history);
}

class LmStudioTranslator implements Translator {
  LmStudioTranslator({
    required this.baseUrl,
    required this.model,
    this.token = '',
    this.options = const TranslateOptions(),
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// e.g. http://localhost:1234/v1
  final String baseUrl;
  final String model;

  /// Optional LM Studio API token (Developer → Server settings → API tokens).
  final String token;
  final TranslateOptions options;
  final http.Client _client;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token.trim().isNotEmpty) 'authorization': 'Bearer ${token.trim()}',
      };

  static String _describe(int status, String body) {
    if (status == 401 || status == 403) {
      return 'LM Studio ต้องการ API token (ใส่ในช่อง token หรือปิด Require authentication ใน Developer → Server settings)';
    }
    return 'LM Studio $status: $body';
  }

  Uri _uri(String path) {
    var base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (!base.endsWith('/v1')) base = '$base/v1';
    return Uri.parse('$base$path');
  }

  /// Model ids loaded or available in LM Studio.
  Future<List<String>> listModels() async {
    final http.Response res;
    try {
      res = await _client.get(_uri('/models'), headers: _headers);
    } catch (e) {
      throw TranslatorException('Cannot reach LM Studio at $baseUrl: $e');
    }
    if (res.statusCode != 200) {
      throw TranslatorException(_describe(res.statusCode, res.body));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? const [];
    return data.map((m) => (m as Map<String, dynamic>)['id'] as String).toList();
  }

  @override
  Stream<String> translate(String text, List<Exchange> history) async* {
    final req = http.Request('POST', _uri('/chat/completions'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'temperature': 0.2,
        'max_tokens': 512,
        // Qwen3.x / reasoning models: skip chain of thought, otherwise the
        // whole token budget goes to thinking and the content comes back empty.
        if (options.noThink) 'reasoning_effort': 'none',
        'messages': buildMessages(text, history, options),
      });

    final http.StreamedResponse res;
    try {
      res = await _client.send(req);
    } catch (e) {
      throw TranslatorException('Cannot reach LM Studio at $baseUrl: $e');
    }
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      throw TranslatorException(_describe(res.statusCode, body));
    }

    final buf = StringBuffer();
    var sawReasoning = false;
    await for (final line in res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!sawReasoning && line.contains('"reasoning')) sawReasoning = true;
      final delta = parseSseDelta(line);
      if (delta == null || delta.isEmpty) continue;
      buf.write(delta);
      yield postProcess(buf.toString());
    }
    final out = postProcess(buf.toString());
    if (out.isEmpty && sawReasoning) {
      throw TranslatorException(
        'โมเดลใช้ thinking จนหมดโควตา token ก่อนตอบ เปิดสวิตช์ "ปิด thinking" หรือเลือกโมเดลที่ไม่ใช่ reasoning',
      );
    }
    yield out;
  }
}

class TranslatorException implements Exception {
  TranslatorException(this.message);
  final String message;
  @override
  String toString() => message;
}
