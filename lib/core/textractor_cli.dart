/// Thin process wrapper around TextractorCLI.exe.
///
/// The CLI exits on any command it cannot parse, so every command is
/// validated here before it is written to stdin.
library;

import 'dart:async';
import 'dart:io';

import 'textractor_line.dart';
import 'utf16.dart';

class TextractorCli {
  TextractorCli(this.exePath);

  final String exePath;
  Process? _process;
  final _lines = StreamController<HookLine>.broadcast();
  final _log = StreamController<String>.broadcast();
  final _exit = Completer<int>();

  /// Parsed text events.
  Stream<HookLine> get lines => _lines.stream;

  /// Everything else the CLI prints (banner, console thread) plus our own
  /// diagnostics.
  Stream<String> get log => _log.stream;

  Future<int> get exitCode => _exit.future;
  bool get isRunning => _process != null && !_exit.isCompleted;

  Future<void> start() async {
    if (_process != null) throw StateError('already started');
    if (!File(exePath).existsSync()) {
      throw FileSystemException('TextractorCLI.exe not found', exePath);
    }
    final p = await Process.start(
      exePath,
      const [],
      workingDirectory: File(exePath).parent.path,
    );
    _process = p;
    p.stdout.transform(const Utf16LeLineDecoder()).listen(_onStdoutLine);
    p.stderr.transform(const Utf16LeLineDecoder()).listen((l) => _log.add('stderr: $l'));
    p.exitCode.then((code) {
      _log.add('TextractorCLI exited with code $code');
      if (!_exit.isCompleted) _exit.complete(code);
    });
    _log.add('started $exePath');
  }

  void _onStdoutLine(String line) {
    final hl = parseHookLine(line);
    if (hl == null) {
      if (line.trim().isNotEmpty) _log.add(line);
      return;
    }
    if (hl.isConsole) _log.add(hl.text);
    _lines.add(hl);
  }

  static final _pidRe = RegExp(r'^\d+$');
  // Hook codes: /H..., /R..., H..., R... and no whitespace.
  static final _hookCodeRe = RegExp(r'^/?[HR][^\s]*$');

  Future<void> attach(int pid) => _send('attach', pid);
  Future<void> detach(int pid) => _send('detach', pid);

  /// Sends a user-supplied hook code (H-code / R-code).
  Future<void> insertHook(String hookCode, int pid) {
    final code = hookCode.trim();
    if (!_hookCodeRe.hasMatch(code)) {
      throw ArgumentError.value(hookCode, 'hookCode', 'not a valid hook code');
    }
    return _send(code, pid);
  }

  Future<void> _send(String command, int pid) async {
    final p = _process;
    if (p == null || _exit.isCompleted) throw StateError('CLI is not running');
    if (!_pidRe.hasMatch('$pid')) throw ArgumentError('bad pid');
    final text = '$command -P$pid\n';
    _log.add('> ${text.trimRight()}');
    p.stdin.add(encodeUtf16Le(text));
    await p.stdin.flush();
  }

  Future<void> stop() async {
    final p = _process;
    if (p == null) return;
    try {
      await p.stdin.close();
    } catch (_) {}
    p.kill();
    await _lines.close();
    await _log.close();
  }
}

/// Where TextractorCLI.exe lives for each bitness, mirroring the layout of a
/// Textractor release zip (`x86/TextractorCLI.exe`, `x64/TextractorCLI.exe`).
String textractorCliPath(String textractorDir, {required bool is64Bit}) {
  final arch = is64Bit ? 'x64' : 'x86';
  return '$textractorDir${Platform.pathSeparator}$arch${Platform.pathSeparator}TextractorCLI.exe';
}
