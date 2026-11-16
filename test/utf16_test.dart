import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooktrans/core/utf16.dart';

void main() {
  test('round trips Japanese text', () {
    final bytes = encodeUtf16Le('こんにちは\n');
    expect(bytes.length, 12);
    expect(bytes[0], 0x53); // こ = U+3053
    expect(bytes[1], 0x30);
  });

  test('decodes lines across odd chunk boundaries and drops CR', () async {
    final all = encodeUtf16Le('line1\r\n日本語\r\ntail');
    final chunks = <List<int>>[
      all.sublist(0, 3),
      all.sublist(3, 14),
      all.sublist(14, 15),
      all.sublist(15),
    ];
    final out = await Stream.fromIterable(chunks)
        .transform(const Utf16LeLineDecoder())
        .toList();
    expect(out, ['line1', '日本語', 'tail']);
  });

  test('handles surrogate pairs (emoji)', () async {
    final out = await Stream<List<int>>.fromIterable([encodeUtf16Le('a😀b\n')])
        .transform(const Utf16LeLineDecoder())
        .toList();
    expect(out, ['a😀b']);
  });
}
