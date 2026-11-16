/// Text cleanup for hook output.
///
/// Textractor hooks often deliver noisy text: every character repeated N times
/// ("ここんんににちちはは"), the whole phrase doubled ("hellohello"), stray
/// control characters, or ruby/furigana markup. This file mirrors the two most
/// useful Textractor extensions (Remove Repeated Characters / Phrases) in pure
/// Dart so the pipeline does not depend on the GUI extension loader.
library;

/// Collapses text where every character is repeated the same number of times.
///
/// "ここんんににちちはは" -> "こんにちは". Returns the input unchanged when the
/// pattern does not hold for the whole string.
String removeRepeatedChars(String text) {
  final runes = text.runes.toList();
  if (runes.length < 2) return text;

  // Count how many times the first character repeats.
  var n = 1;
  while (n < runes.length && runes[n] == runes[0]) {
    n++;
  }
  if (n < 2 || runes.length % n != 0) return text;

  final out = <int>[];
  for (var i = 0; i < runes.length; i += n) {
    final c = runes[i];
    for (var j = 1; j < n; j++) {
      if (runes[i + j] != c) return text;
    }
    out.add(c);
  }
  return String.fromCharCodes(out);
}

/// Collapses a string that is the same phrase repeated back to back.
///
/// "こんにちはこんにちは" -> "こんにちは". Also handles 3+ repeats.
String removeRepeatedPhrase(String text) {
  final runes = text.runes.toList();
  final len = runes.length;
  if (len < 2) return text;

  // Try the smallest period first so "abab" -> "ab", not "abab".
  for (var period = 1; period <= len ~/ 2; period++) {
    if (len % period != 0) continue;
    var ok = true;
    for (var i = period; i < len && ok; i++) {
      if (runes[i] != runes[i - period]) ok = false;
    }
    if (ok) return String.fromCharCodes(runes.sublist(0, period));
  }
  return text;
}

final _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
final _multiSpace = RegExp(r'[ \t]{2,}');

/// Strips control characters and collapses whitespace.
String normalizeWhitespace(String text) {
  return text
      .replaceAll(_controlChars, '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(_multiSpace, ' ')
      .trim();
}

/// Full cleanup chain used by the pipeline.
String cleanHookText(String text) {
  var t = normalizeWhitespace(text);
  t = removeRepeatedChars(t);
  t = removeRepeatedPhrase(t);
  return t;
}

final _cjk = RegExp(
  r'[぀-ヿ㐀-䶿一-鿿豈-﫿ｦ-ﾟ가-힯]',
);

/// True when the text contains Japanese, Chinese or Korean characters.
bool containsCjk(String text) => _cjk.hasMatch(text);

/// True when the text contains at least one letter in any script.
bool containsLetters(String text) => RegExp(r'\p{L}', unicode: true).hasMatch(text);
