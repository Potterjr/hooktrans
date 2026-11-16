/// Polls a screen region with OCR and emits the text whenever it changes.
library;

import 'dart:async';
import 'dart:ui';

import 'screen_channel.dart';
import 'text_cleaner.dart';

/// Joins OCR lines: CJK text wraps mid-sentence, so lines are glued without a
/// space; other scripts get one.
String joinOcrLines(String raw) {
  final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return '';
  final cjk = containsCjk(raw);
  return lines.join(cjk ? '' : ' ');
}

class ScreenOcrSource {
  ScreenOcrSource(this.channel);

  final ScreenChannel channel;
  final _text = StreamController<String>.broadcast();
  final _errors = StreamController<String>.broadcast();

  Stream<String> get text => _text.stream;
  Stream<String> get errors => _errors.stream;

  bool _running = false;
  bool get running => _running;
  int _generation = 0;
  String _last = '';

  /// Most recent OCR text (after line joining), for display.
  String get lastText => _last;
  Rect? rect;
  int? displayId;
  List<String> languages = const ['ja', 'en'];
  Duration interval = const Duration(milliseconds: 200);

  Future<void> start() async {
    if (_running) return;
    if (rect == null) throw StateError('no region selected');
    _running = true;
    _last = '';
    unawaited(_loop(++_generation));
  }

  void stop() {
    _running = false;
    _generation++;
  }

  Future<void> _loop(int gen) async {
    var force = true;
    while (_running && gen == _generation) {
      final started = DateTime.now();
      try {
        final r = rect;
        if (r == null) break;
        final raw = await channel.captureText(r, languages, force: force, displayId: displayId);
        force = false;
        if (gen != _generation) break;
        if (raw != null) {
          final joined = joinOcrLines(raw);
          if (joined != _last) {
            _last = joined;
            _text.add(joined);
          }
        }
      } catch (e) {
        _errors.add(e.toString());
        // Back off a bit after an error (e.g. permission not yet granted).
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      final elapsed = DateTime.now().difference(started);
      final wait = interval - elapsed;
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }

  Future<void> dispose() async {
    stop();
    await _text.close();
    await _errors.close();
  }
}
