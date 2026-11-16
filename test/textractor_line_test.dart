import 'package:flutter_test/flutter_test.dart';
import 'package:hooktrans/core/textractor_line.dart';

void main() {
  test('parses a CLI text line with a hook code containing colons', () {
    final l = parseHookLine(
      '[1A:2B3C:7FF6A0001234:0:0:GetGlyphOutlineA:HS-4@1234:game.exe] こんにちは',
    );
    expect(l, isNotNull);
    expect(l!.handle, 0x1A);
    expect(l.pid, 0x2B3C);
    expect(l.addr, 0x7FF6A0001234);
    expect(l.name, 'GetGlyphOutlineA');
    expect(l.hookCode, 'HS-4@1234:game.exe');
    expect(l.text, 'こんにちは');
  });

  test('console thread is flagged', () {
    final l = parseHookLine('[0:0:0:0:0:Console:] Textractor: ready');
    expect(l!.isConsole, isTrue);
    expect(l.hookCode, '');
  });

  test('ignores the usage banner', () {
    expect(parseHookLine("Usage: {'attach'|'detach'|hookcode} -Pprocessid"), isNull);
    expect(parseHookLine(''), isNull);
    expect(parseHookLine('[garbage] x'), isNull);
  });

  test('text may contain brackets', () {
    final l = parseHookLine('[1:2:3:4:5:n:HB4@0] 【太郎】「やあ[笑]」');
    expect(l!.text, '【太郎】「やあ[笑]」');
  });
}
