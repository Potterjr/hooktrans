/// UTF-16LE codec for talking to TextractorCLI, which switches both its
/// stdin and stdout to `_O_U16TEXT`.
library;

import 'dart:async';
import 'dart:typed_data';

/// Encodes a string as UTF-16LE bytes.
Uint8List encodeUtf16Le(String s) {
  final units = s.codeUnits;
  final out = Uint8List(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    out[i * 2] = units[i] & 0xFF;
    out[i * 2 + 1] = (units[i] >> 8) & 0xFF;
  }
  return out;
}

/// Decodes a byte stream as UTF-16LE text, splitting on newlines.
///
/// Chunks from a pipe can end in the middle of a code unit, so a trailing odd
/// byte is carried over to the next chunk. '\r' is dropped (the CLI runs in
/// Windows text mode, which emits "\r\n").
class Utf16LeLineDecoder extends StreamTransformerBase<List<int>, String> {
  const Utf16LeLineDecoder();

  @override
  Stream<String> bind(Stream<List<int>> stream) async* {
    int? carry;
    final units = <int>[];
    await for (final chunk in stream) {
      var i = 0;
      if (carry != null && chunk.isNotEmpty) {
        units.add(carry | (chunk[0] << 8));
        carry = null;
        i = 1;
      }
      for (; i + 1 < chunk.length; i += 2) {
        units.add(chunk[i] | (chunk[i + 1] << 8));
      }
      if (i < chunk.length) carry = chunk[i];

      // Emit complete lines.
      var start = 0;
      for (var j = 0; j < units.length; j++) {
        if (units[j] == 0x0A) {
          var end = j;
          if (end > start && units[end - 1] == 0x0D) end--;
          yield String.fromCharCodes(units, start, end);
          start = j + 1;
        }
      }
      if (start > 0) units.removeRange(0, start);
    }
    if (units.isNotEmpty) {
      if (units.last == 0x0D) units.removeLast();
      yield String.fromCharCodes(units);
    }
  }
}
