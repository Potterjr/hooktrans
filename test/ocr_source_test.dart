
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooktrans/core/pipeline.dart';
import 'package:hooktrans/core/screen_channel.dart';
import 'package:hooktrans/core/screen_ocr_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('joinOcrLines glues CJK and spaces Latin', () {
    expect(joinOcrLines('今日は\nいい天気\n'), '今日はいい天気');
    expect(joinOcrLines('Hello\n world '), 'Hello world');
    expect(joinOcrLines('\n\n'), '');
  });

  test('near duplicate detection tolerates OCR jitter', () {
    expect(isNearDuplicate('The quick brown fox jumps', 'The quick brown fox jumps.'), isTrue);
    expect(isNearDuplicate('今日はいい天気ですね、散歩に行こう', '今日はいい天気ですね、散歩に行こラ'), isTrue);
    expect(isNearDuplicate('はい', 'いいえ'), isFalse); // too short to guess
    expect(isNearDuplicate('A completely different sentence', 'Nothing alike here at all!'), isFalse);
    expect(levenshtein('kitten'.runes.toList(), 'sitting'.runes.toList()), 3);
  });

  test('source emits only changed text and feeds the pipeline', () async {
    const ch = MethodChannel('hooktrans/screen');
    final responses = <dynamic>[
      {'changed': true, 'text': 'こん\nにちは'},
      {'changed': false, 'text': null},
      {'changed': true, 'text': 'こん\nにちは'},
      {'changed': true, 'text': 'さようなら'},
    ];
    final calls = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
      expect(call.method, 'captureText');
      calls.add(call.arguments as Map);
      return responses.isEmpty ? {'changed': false, 'text': null} : responses.removeAt(0);
    });

    final src = ScreenOcrSource(ScreenChannel(ch))
      ..rect = const Rect.fromLTWH(10, 20, 300, 80)
      ..displayId = 7
      ..languages = ['ja']
      ..interval = const Duration(milliseconds: 5);
    final got = <String>[];
    src.text.listen(got.add);
    await src.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    src.stop();

    expect(got, ['こんにちは', 'さようなら']);
    expect(calls.first['force'], true);
    expect(calls[1]['force'], false);
    expect(calls.first['x'], 10.0);
    expect(calls.first['languages'], ['ja']);
    expect(calls.first['displayId'], 7);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null);
  });

  test('errors are reported and polling continues', () async {
    const ch = MethodChannel('hooktrans/screen');
    var n = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
      n++;
      if (n == 1) throw PlatformException(code: 'ocr', message: 'denied');
      return {'changed': true, 'text': 'ok'};
    });
    final src = ScreenOcrSource(ScreenChannel(ch))
      ..rect = const Rect.fromLTWH(0, 0, 10, 10)
      ..interval = const Duration(milliseconds: 5);
    final errors = <String>[];
    final texts = <String>[];
    src.errors.listen(errors.add);
    src.text.listen(texts.add);
    await src.start();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    src.stop();
    expect(errors.single, contains('denied'));
    expect(texts, ['ok']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null);
  });
}
