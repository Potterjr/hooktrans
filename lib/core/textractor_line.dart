/// Parser for TextractorCLI output.
///
/// The CLI (host/CLI/main.cpp) prints one line per text event:
///
/// ```
/// [%I64X:%I32X:%I64X:%I64X:%I64X:%s:%s] %s
///  handle  pid   addr  ctx   ctx2  name hookcode  text
/// ```
///
/// The hook code itself can contain ':' (for example `HS-4@1234:game.exe`),
/// so only the first six fields are split on ':' and the rest is the code.
library;

class HookLine {
  const HookLine({
    required this.handle,
    required this.pid,
    required this.addr,
    required this.ctx,
    required this.ctx2,
    required this.name,
    required this.hookCode,
    required this.text,
  });

  /// Thread handle; stable id for one text thread while the CLI runs.
  final int handle;
  final int pid;
  final int addr;
  final int ctx;
  final int ctx2;
  final String name;
  final String hookCode;
  final String text;

  bool get isConsole => name == 'Console';
  bool get isClipboard => name == 'Clipboard';

  @override
  String toString() => '[$handle:$pid:$name:$hookCode] $text';
}

final _lineRe = RegExp(r'^\[([^\]]*)\] ?(.*)$', dotAll: true);

/// Parses one CLI line. Returns null for the usage banner and anything else
/// that is not a text event.
HookLine? parseHookLine(String line) {
  final m = _lineRe.firstMatch(line);
  if (m == null) return null;
  final header = m.group(1)!;
  final parts = header.split(':');
  if (parts.length < 7) return null;

  int? hex(String s) => int.tryParse(s, radix: 16);
  final handle = hex(parts[0]);
  final pid = hex(parts[1]);
  final addr = hex(parts[2]);
  final ctx = hex(parts[3]);
  final ctx2 = hex(parts[4]);
  if (handle == null || pid == null || addr == null || ctx == null || ctx2 == null) {
    return null;
  }
  return HookLine(
    handle: handle,
    pid: pid,
    addr: addr,
    ctx: ctx,
    ctx2: ctx2,
    name: parts[5],
    hookCode: parts.sublist(6).join(':'),
    text: m.group(2)!,
  );
}
