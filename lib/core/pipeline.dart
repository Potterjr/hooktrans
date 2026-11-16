// ignore_for_file: prefer_initializing_formals
/// Glue between hook output and the overlay: tracks threads, picks the
/// dialogue thread, waits for text to settle, then translates.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'text_cleaner.dart';
import 'textractor_line.dart';
import 'thread_picker.dart';
import 'translator.dart';

class HookPipeline extends ChangeNotifier {
  HookPipeline({
    required Translator Function() translatorFactory,
    this.settleDelay = const Duration(milliseconds: 250),
    this.maxHistory = 8,
    DateTime Function()? clock,
  })  : _translatorFactory = translatorFactory,
        _clock = clock ?? DateTime.now;

  final Translator Function() _translatorFactory;
  final Duration settleDelay;
  final int maxHistory;
  final DateTime Function() _clock;

  final Map<int, ThreadStats> threads = <int, ThreadStats>{};
  final List<Exchange> history = <Exchange>[];
  final LinkedHashMap<String, String> _cache = LinkedHashMap<String, String>();
  static const _cacheLimit = 500;

  int? _selected;
  bool autoPick = true;

  String sourceText = '';
  String translation = '';
  String? error;
  bool translating = false;
  String _lastTranslatedSource = '';

  Timer? _settle;
  StreamSubscription<String>? _inflight;
  int _generation = 0;

  int? get selectedThread => _selected;

  /// Pins a thread chosen by the user and disables automatic selection.
  void selectThread(int? handle) {
    autoPick = handle == null;
    _selected = handle;
    final t = handle == null ? null : threads[handle];
    if (t != null && t.lastText.isNotEmpty) _schedule(t.lastText);
    notifyListeners();
  }

  void onLine(HookLine line) {
    if (line.isConsole || line.isClipboard) return;
    onText(id: line.handle, name: line.name, code: line.hookCode, text: line.text);
  }

  /// Feeds raw text from any source (hook thread, OCR region).
  void onText({required int id, required String name, required String code, required String text}) {
    final cleaned = cleanHookText(text);
    if (cleaned.isEmpty) return;
    final text0 = cleaned;

    final now = _clock();
    final stats = threads.putIfAbsent(
      id,
      () => ThreadStats(id: id, name: name, hookCode: code),
    )..record(text0, now);

    if (autoPick) {
      final next = pickThread(threads.values, now, current: _selected);
      if (next != _selected) {
        _selected = next;
      }
    }
    if (stats.id == _selected) _schedule(text0);
    notifyListeners();
  }

  void _schedule(String text) {
    if (!containsLetters(text)) return;
    _settle?.cancel();
    _settle = Timer(settleDelay, () => _translate(text));
  }

  Future<void> _translate(String text) async {
    if (text == _lastTranslatedSource) return;
    // OCR jitter: a frame that differs by a character or two is the same line.
    if (_cache[text] == null && isNearDuplicate(text, _lastTranslatedSource)) return;
    _lastTranslatedSource = text;
    sourceText = text;
    error = null;

    final cached = _cache[text];
    if (cached != null) {
      translation = cached;
      translating = false;
      _pushHistory(text, cached);
      notifyListeners();
      return;
    }

    await _inflight?.cancel();
    final gen = ++_generation;
    translation = '';
    translating = true;
    notifyListeners();

    final translator = _translatorFactory();
    final completer = Completer<void>();
    _inflight = translator.translate(text, List.unmodifiable(history)).listen(
      (partial) {
        if (gen != _generation) return;
        translation = partial;
        notifyListeners();
      },
      onError: (Object e) {
        if (gen != _generation) return;
        error = e.toString();
        translating = false;
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (gen == _generation) {
          translating = false;
          if (translation.isNotEmpty) {
            _remember(text, translation);
            _pushHistory(text, translation);
          }
          notifyListeners();
        }
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  void _remember(String src, String dst) {
    _cache.remove(src);
    _cache[src] = dst;
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _pushHistory(String src, String dst) {
    if (history.isNotEmpty && history.last.source == src) return;
    history.add(Exchange(src, dst));
    while (history.length > maxHistory) {
      history.removeAt(0);
    }
  }

  /// Re-translates the current line, e.g. after the engine or language changed.
  void retranslate() {
    final t = sourceText;
    _lastTranslatedSource = '';
    _cache.remove(t);
    error = null;
    if (t.isNotEmpty) _translate(t);
    notifyListeners();
  }

  /// Forgets translation context; useful when the player loads another save.
  void clearContext() {
    history.clear();
    _lastTranslatedSource = '';
    notifyListeners();
  }

  void reset() {
    _settle?.cancel();
    _inflight?.cancel();
    _generation++;
    threads.clear();
    history.clear();
    _selected = null;
    autoPick = true;
    sourceText = '';
    translation = '';
    error = null;
    translating = false;
    _lastTranslatedSource = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _settle?.cancel();
    _inflight?.cancel();
    super.dispose();
  }
}

/// True when [a] and [b] are long enough to be a sentence and differ in at
/// most ~8% of their characters (typical OCR noise between frames).
bool isNearDuplicate(String a, String b, {double threshold = 0.08, int minLength = 12}) {
  final ra = a.runes.toList();
  final rb = b.runes.toList();
  final maxLen = ra.length > rb.length ? ra.length : rb.length;
  if (maxLen < minLength || maxLen > 400) return false;
  if ((ra.length - rb.length).abs() / maxLen > threshold) return false;
  return levenshtein(ra, rb) / maxLen <= threshold;
}

int levenshtein(List<int> a, List<int> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
      cur[j] = v;
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}
