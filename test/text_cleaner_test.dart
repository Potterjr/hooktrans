import 'package:flutter_test/flutter_test.dart';
import 'package:hooktrans/core/text_cleaner.dart';

void main() {
  test('removes characters repeated N times', () {
    expect(removeRepeatedChars('ここんんににちちはは'), 'こんにちは');
    expect(removeRepeatedChars('aaabbbccc'), 'abc');
    expect(removeRepeatedChars('こんにちは'), 'こんにちは');
    expect(removeRepeatedChars('aab'), 'aab'); // not uniform
    expect(removeRepeatedChars(''), '');
  });

  test('removes repeated phrase', () {
    expect(removeRepeatedPhrase('こんにちはこんにちは'), 'こんにちは');
    expect(removeRepeatedPhrase('abcabcabc'), 'abc');
    expect(removeRepeatedPhrase('abcab'), 'abcab');
  });

  test('normalizes whitespace and control chars', () {
    expect(normalizeWhitespace('  a\x00b\t\tc\r\n'), 'ab c');
  });

  test('full chain', () {
    expect(cleanHookText('\x01ここんんににちちははここんんににちちはは '), 'こんにちは');
  });

  test('script detection', () {
    expect(containsCjk('こんにちは'), isTrue);
    expect(containsCjk('hello'), isFalse);
    expect(containsLetters('123 ...'), isFalse);
    expect(containsLetters('สวัสดี'), isTrue);
  });
}
