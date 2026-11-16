/// User settings, persisted as JSON under %APPDATA%\hooktrans.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

enum Engine { lmStudio, google }

const supportedLanguages = ['Thai', 'English', 'Japanese', 'Chinese', 'Korean', 'Vietnamese', 'Indonesian'];

class AppSettings extends ChangeNotifier {
  String textractorDir = _defaultTextractorDir();
  Engine engine = Engine.lmStudio;
  String lmStudioUrl = 'http://localhost:1234/v1';
  String lmStudioToken = '';
  String model = '';
  String targetLanguage = 'Thai';
  String sourceLanguage = 'auto';
  int historyLines = 4;
  bool noThink = true;
  double fontSize = 22;
  double overlayOpacity = 0.85;
  bool showSource = true;
  Map<String, String> glossary = {};

  // Screen OCR mode (macOS)
  List<String> ocrLanguages = ['ja', 'en'];
  int captureIntervalMs = 200;
  Rect? region;
  int? displayId;

  static String _defaultTextractorDir() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}textractor';
  }

  static File _file() {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return File('$base${Platform.pathSeparator}hooktrans${Platform.pathSeparator}settings.json');
  }

  Map<String, dynamic> toJson() => {
        'textractorDir': textractorDir,
        'engine': engine.name,
        'lmStudioUrl': lmStudioUrl,
        'lmStudioToken': lmStudioToken,
        'model': model,
        'targetLanguage': targetLanguage,
        'sourceLanguage': sourceLanguage,
        'historyLines': historyLines,
        'noThink': noThink,
        'fontSize': fontSize,
        'overlayOpacity': overlayOpacity,
        'showSource': showSource,
        'glossary': glossary,
        'ocrLanguages': ocrLanguages,
        'captureIntervalMs': captureIntervalMs,
        if (region != null)
          'region': {'x': region!.left, 'y': region!.top, 'w': region!.width, 'h': region!.height},
        if (displayId != null) 'displayId': displayId,
      };

  void applyJson(Map<String, dynamic> j) {
    textractorDir = j['textractorDir'] as String? ?? textractorDir;
    engine = Engine.values.firstWhere(
      (e) => e.name == j['engine'],
      orElse: () => engine,
    );
    lmStudioUrl = j['lmStudioUrl'] as String? ?? lmStudioUrl;
    lmStudioToken = j['lmStudioToken'] as String? ?? lmStudioToken;
    model = j['model'] as String? ?? model;
    targetLanguage = j['targetLanguage'] as String? ?? targetLanguage;
    sourceLanguage = j['sourceLanguage'] as String? ?? sourceLanguage;
    historyLines = (j['historyLines'] as num?)?.toInt() ?? historyLines;
    noThink = j['noThink'] as bool? ?? noThink;
    fontSize = (j['fontSize'] as num?)?.toDouble() ?? fontSize;
    overlayOpacity = (j['overlayOpacity'] as num?)?.toDouble() ?? overlayOpacity;
    showSource = j['showSource'] as bool? ?? showSource;
    final g = j['glossary'];
    if (g is Map) glossary = g.map((k, v) => MapEntry('$k', '$v'));
    final langs = j['ocrLanguages'];
    if (langs is List && langs.isNotEmpty) ocrLanguages = langs.map((e) => '$e').toList();
    captureIntervalMs = (j['captureIntervalMs'] as num?)?.toInt() ?? captureIntervalMs;
    displayId = (j['displayId'] as num?)?.toInt();
    final r = j['region'];
    if (r is Map) {
      region = Rect.fromLTWH(
        (r['x'] as num).toDouble(),
        (r['y'] as num).toDouble(),
        (r['w'] as num).toDouble(),
        (r['h'] as num).toDouble(),
      );
    }
  }

  Future<void> load() async {
    try {
      final f = _file();
      if (await f.exists()) {
        applyJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('settings load failed: $e');
    }
    // Environment overrides for automation / first launch, persisted so later
    // launches do not need them (e.g. `open hooktrans.app --env HOOKTRANS_LM_TOKEN=...`).
    final env = Platform.environment;
    var overridden = false;
    final t = env['HOOKTRANS_LM_TOKEN'];
    if (t != null && t.isNotEmpty && t != lmStudioToken) {
      lmStudioToken = t;
      overridden = true;
    }
    final u = env['HOOKTRANS_LM_URL'];
    if (u != null && u.isNotEmpty && u != lmStudioUrl) {
      lmStudioUrl = u;
      overridden = true;
    }
    if (overridden) await save();
    notifyListeners();
  }

  Future<void> save() async {
    notifyListeners();
    try {
      final f = _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
    } catch (e) {
      debugPrint('settings save failed: $e');
    }
  }
}
