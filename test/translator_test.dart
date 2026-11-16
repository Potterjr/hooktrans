import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooktrans/core/google_translator.dart';
import 'package:hooktrans/core/translator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('prompt', () {
    test('includes glossary, target language and history window', () {
      const o = TranslateOptions(targetLanguage: 'Thai', historyLines: 1, glossary: {'太郎': 'ทาโร่'});
      final msgs = buildMessages('c', const [Exchange('a', 'A'), Exchange('b', 'B')], o);
      expect(msgs.first['role'], 'system');
      expect(msgs.first['content'], contains('into Thai'));
      expect(msgs.first['content'], contains('太郎 = ทาโร่'));
      expect(msgs.first['content'], endsWith('/no_think'));
      // only the last history pair is kept
      expect(msgs.map((m) => m['content']).toList(), ['' , 'b', 'B', 'c'].map((s) => s == '' ? msgs.first['content'] : s).toList());
    });

    test('postProcess strips think blocks and quotes', () {
      expect(postProcess('<think>hmm</think>「สวัสดี」'), 'สวัสดี');
      expect(postProcess('<think>unterminated'), '');
      expect(postProcess('"hi"'), 'hi');
      expect(postProcess('he said "hi"'), 'he said "hi"');
    });
  });

  group('LM Studio SSE', () {
    test('parses deltas and DONE', () {
      expect(parseSseDelta('data: {"choices":[{"delta":{"content":"สวั"}}]}'), 'สวั');
      expect(parseSseDelta('data: [DONE]'), isNull);
      expect(parseSseDelta(''), isNull);
      expect(parseSseDelta('data: {"choices":[{"delta":{"role":"assistant"}}]}'), isNull);
    });

    test('streams a full translation', () async {
      final client = MockClient.streaming((req, body) async {
        expect(req.url.toString(), 'http://localhost:1234/v1/chat/completions');
        final payload = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        expect(payload['model'], 'qwen3-4b');
        expect(payload['stream'], true);
        expect(payload['reasoning_effort'], 'none');
        final sse = [
          'data: {"choices":[{"delta":{"content":"สวัส"}}]}',
          '',
          'data: {"choices":[{"delta":{"content":"ดี"}}]}',
          '',
          'data: [DONE]',
        ].join('\n');
        return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
      });
      final t = LmStudioTranslator(baseUrl: 'http://localhost:1234', model: 'qwen3-4b', client: client);
      final out = await t.translate('こんにちは', const []).toList();
      expect(out.last, 'สวัสดี');
      expect(out, ['สวัส', 'สวัสดี', 'สวัสดี']);
    });

    test('sends bearer token and explains 401', () async {
      final client = MockClient((req) async {
        expect(req.headers['authorization'], 'Bearer abc');
        return http.Response('{"error":"nope"}', 401);
      });
      final t = LmStudioTranslator(baseUrl: 'http://localhost:1234', model: '', token: 'abc', client: client);
      await expectLater(t.listModels(), throwsA(predicate((e) => e.toString().contains('API token'))));
    });

    test('explains an all-thinking empty answer', () async {
      final client = MockClient.streaming((req, body) async {
        final sse = [
          'data: {"choices":[{"delta":{"reasoning_content":"thinking..."}}]}',
          'data: {"choices":[{"delta":{},"finish_reason":"length"}]}',
          'data: [DONE]',
        ].join('\n');
        return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
      });
      final t = LmStudioTranslator(baseUrl: 'http://localhost:1234', model: 'm', client: client);
      await expectLater(t.translate('x', const []).toList(),
          throwsA(predicate((e) => e.toString().contains('thinking'))));
    });

    test('lists models', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/v1/models');
        return http.Response(jsonEncode({'data': [{'id': 'a'}, {'id': 'b'}]}), 200);
      });
      final t = LmStudioTranslator(baseUrl: 'http://localhost:1234/v1/', model: '', client: client);
      expect(await t.listModels(), ['a', 'b']);
    });
  });

  group('Google', () {
    test('parses segments', () {
      const body = '[[["สวัสดี ","こんにちは ",null,null,10],["โลก","世界",null,null,3]],null,"ja"]';
      expect(parseGoogleResponse(body), 'สวัสดี โลก');
    });

    test('calls the gtx endpoint', () async {
      final client = MockClient((req) async {
        expect(req.url.host, 'translate.googleapis.com');
        expect(req.url.queryParameters['tl'], 'th');
        expect(req.url.queryParameters['q'], 'hello');
        return http.Response.bytes(utf8.encode('[[["สวัสดี","hello",null,null,1]],null,"en"]'), 200);
      });
      final t = GoogleTranslator(targetLanguage: 'th', client: client);
      expect(await t.translate('hello', const []).last, 'สวัสดี');
    });
  });
}
