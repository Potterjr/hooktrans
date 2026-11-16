/// Heuristic that guesses which hook thread carries the game's dialogue.
///
/// A hooked game exposes many text threads at once (UI labels, menu entries,
/// system strings, the dialogue box). Instead of asking the user to read hex
/// addresses, the picker scores every thread from what it has emitted so far
/// and the pipeline follows the best one. The user can still pin a thread by
/// hand, which disables the automatic choice.
library;

import 'text_cleaner.dart';

/// Running statistics for one hook thread.
class ThreadStats {
  ThreadStats({required this.id, required this.name, required this.hookCode});

  final int id;
  final String name;
  final String hookCode;

  int messages = 0;
  int distinctMessages = 0;
  int totalLength = 0;
  int cjkMessages = 0;
  int letterMessages = 0;
  DateTime? lastUpdate;
  String lastText = '';
  final Set<int> _seen = <int>{};

  /// Timestamps of the last few messages, used to detect spammy threads.
  final List<DateTime> _recent = <DateTime>[];

  void record(String text, DateTime now) {
    messages++;
    totalLength += text.runes.length;
    if (_seen.add(text.hashCode)) distinctMessages++;
    if (containsCjk(text)) cjkMessages++;
    if (containsLetters(text)) letterMessages++;
    lastUpdate = now;
    lastText = text;
    _recent.add(now);
    while (_recent.length > 20) {
      _recent.removeAt(0);
    }
  }

  double get averageLength => messages == 0 ? 0 : totalLength / messages;

  /// Messages per second over the recent window.
  double rate(DateTime now) {
    if (_recent.length < 2) return 0;
    final span = now.difference(_recent.first).inMilliseconds;
    if (span <= 0) return double.infinity;
    return _recent.length * 1000 / span;
  }

  bool get isSystem =>
      name == 'Console' || name == 'Clipboard' || hookCode.isEmpty && id == 0;
}

/// Scores a thread; higher is more likely to be dialogue.
double scoreThread(ThreadStats t, DateTime now) {
  if (t.isSystem || t.messages == 0) return double.negativeInfinity;

  var score = 0.0;

  // Dialogue lines are usually a sentence or two, not a single label or a
  // whole screen of text.
  final len = t.averageLength;
  if (len >= 4 && len <= 400) {
    score += 2;
  } else if (len < 2 || len > 1500) {
    score -= 3;
  }

  // Threads that only ever repeat the same strings are menus or status text.
  final distinctRatio = t.distinctMessages / t.messages;
  score += distinctRatio * 2;

  // Real language content.
  if (t.letterMessages > 0) score += 1;
  if (t.cjkMessages > 0) score += 1;

  // Spam (several messages per second) is a buffer or render hook, not lines
  // the player reads one at a time.
  final r = t.rate(now);
  if (r > 4) score -= 3;

  // Recent activity: the dialogue thread is the one that moves when the
  // player advances text.
  final idle = now.difference(t.lastUpdate!).inSeconds;
  if (idle < 3) {
    score += 2;
  } else if (idle < 15) {
    score += 1;
  } else if (idle > 120) {
    score -= 1;
  }

  return score;
}

/// Picks the best thread, keeping the current one unless another beats it by
/// a clear margin so the overlay does not flicker between candidates.
int? pickThread(
  Iterable<ThreadStats> threads,
  DateTime now, {
  int? current,
  double hysteresis = 1.5,
}) {
  ThreadStats? best;
  var bestScore = double.negativeInfinity;
  for (final t in threads) {
    final s = scoreThread(t, now);
    if (s > bestScore) {
      best = t;
      bestScore = s;
    }
  }
  if (best == null || bestScore == double.negativeInfinity) return current;

  if (current != null && current != best.id) {
    for (final t in threads) {
      if (t.id == current) {
        final cur = scoreThread(t, now);
        if (bestScore - cur < hysteresis) return current;
      }
    }
  }
  return best.id;
}
