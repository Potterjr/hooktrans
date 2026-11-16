import 'package:flutter_test/flutter_test.dart';
import 'package:hooktrans/core/thread_picker.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  ThreadStats make(int id, String name, List<String> msgs, {Duration gap = const Duration(seconds: 2)}) {
    final t = ThreadStats(id: id, name: name, hookCode: 'HB4@0');
    var now = t0;
    for (final m in msgs) {
      t.record(m, now);
      now = now.add(gap);
    }
    return t;
  }

  test('prefers varied sentence-length thread over a menu label thread', () {
    final dialogue = make(1, 'Dialog', ['今日はいい天気ですね。', 'そうだね、散歩に行こうか。', 'うん、行こう！']);
    final menu = make(2, 'Menu', ['セーブ', 'セーブ', 'セーブ']);
    final now = t0.add(const Duration(seconds: 6));
    expect(pickThread([dialogue, menu], now), 1);
  });

  test('penalizes spammy threads', () {
    final spam = make(3, 'Render', List.filled(20, 'x').asMap().entries.map((e) => 'frame ${e.key}').toList(),
        gap: const Duration(milliseconds: 20));
    final dialogue = make(1, 'Dialog', ['Hello there, traveler.', 'Welcome to the village.']);
    final now = t0.add(const Duration(seconds: 3));
    expect(pickThread([spam, dialogue], now), 1);
  });

  test('ignores console thread', () {
    final console = make(0, 'Console', ['Textractor: hooked', 'Textractor: inserted hook']);
    final now = t0.add(const Duration(seconds: 3));
    expect(pickThread([console], now), isNull);
  });

  test('keeps current thread unless beaten by a margin', () {
    final a = make(1, 'A', ['Some line of dialogue here.']);
    final b = make(2, 'B', ['Another line of dialogue here.']);
    final now = t0.add(const Duration(seconds: 1));
    expect(pickThread([a, b], now, current: 2), 2);
    expect(pickThread([a, b], now, current: 1), 1);
  });
}
