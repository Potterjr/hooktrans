import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooktrans/core/pipeline.dart';
import 'package:hooktrans/core/textractor_line.dart';
import 'package:hooktrans/core/translator.dart';

class FakeTranslator implements Translator {
  final calls = <String>[];
  List<Exchange> lastHistory = const [];
  @override
  Stream<String> translate(String text, List<Exchange> history) async* {
    calls.add(text);
    lastHistory = history;
    yield 'T(';
    yield 'T($text)';
  }
}

HookLine line(int handle, String text, {String name = 'Dialog'}) => HookLine(
      handle: handle,
      pid: 1,
      addr: 0,
      ctx: 0,
      ctx2: 0,
      name: name,
      hookCode: 'HB4@0',
      text: text,
    );

void main() {
  test('translates settled text from the picked thread, with cache and history', () async {
    final fake = FakeTranslator();
    final p = HookPipeline(
      translatorFactory: () => fake,
      settleDelay: const Duration(milliseconds: 10),
    );

    // Typewriter-style growing buffer: only the final text should be sent.
    p.onLine(line(7, 'こ'));
    p.onLine(line(7, 'こん'));
    p.onLine(line(7, 'こんにちは'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(fake.calls, ['こんにちは']);
    expect(p.sourceText, 'こんにちは');
    expect(p.translation, 'T(こんにちは)');
    expect(p.translating, isFalse);
    expect(p.history.length, 1);

    // Second line carries the first as context.
    p.onLine(line(7, 'さようなら'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fake.lastHistory.map((e) => e.source), ['こんにちは']);

    // Repeating an earlier line hits the cache; no new call.
    p.onLine(line(7, 'こんにちは'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fake.calls, ['こんにちは', 'さようなら']);
    expect(p.translation, 'T(こんにちは)');
  });

  test('console lines and empty text are ignored', () async {
    final fake = FakeTranslator();
    final p = HookPipeline(translatorFactory: () => fake, settleDelay: Duration.zero);
    p.onLine(line(0, 'Textractor: ready', name: 'Console'));
    p.onLine(line(3, '   '));
    p.onLine(line(3, '1234'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fake.calls, isEmpty);
    expect(p.threads.keys, [3]);
  });

  test('manual pin overrides auto pick', () async {
    final fake = FakeTranslator();
    final p = HookPipeline(translatorFactory: () => fake, settleDelay: Duration.zero);
    p.onLine(line(1, 'This is dialogue, quite long.'));
    p.onLine(line(2, 'Menu'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(p.selectedThread, 1);

    p.selectThread(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(p.autoPick, isFalse);
    expect(p.selectedThread, 2);
    expect(fake.calls.last, 'Menu');

    p.onLine(line(1, 'Another long dialogue line here.'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(p.selectedThread, 2);
    expect(fake.calls.last, 'Menu');
  });

  test('errors are surfaced', () async {
    final p = HookPipeline(
      translatorFactory: () => _ErrorTranslator(),
      settleDelay: Duration.zero,
    );
    p.onLine(line(1, 'hello there'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(p.error, contains('boom'));
    expect(p.translating, isFalse);
  });
}

class _ErrorTranslator implements Translator {
  @override
  Stream<String> translate(String text, List<Exchange> history) =>
      Stream.error(TranslatorException('boom'));
}
