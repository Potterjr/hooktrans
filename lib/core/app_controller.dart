/// Owns the CLI process, the pipeline and the settings; the UI only talks
/// to this object.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'google_translator.dart';
import 'pipeline.dart';
import 'process_list.dart';
import 'screen_channel.dart';
import 'screen_ocr_source.dart';
import 'settings.dart';
import 'textractor_cli.dart';
import 'translator.dart';

enum AppMode { setup, overlay, regionPick }

/// Where the text comes from: Textractor memory hook (Windows) or screen OCR (macOS).
enum SourceKind { hook, ocr }

class AppController extends ChangeNotifier {
  AppController(this.settings, {ScreenChannel? screen}) {
    pipeline = HookPipeline(translatorFactory: _makeTranslator);
    pipeline.addListener(notifyListeners);
    sourceKind = Platform.isMacOS ? SourceKind.ocr : SourceKind.hook;
    ocr = ScreenOcrSource(screen ?? ScreenChannel());
    ocr.text.listen((t) {
      _addLog('ocr: $t');
      pipeline.onText(id: 1, name: 'Screen', code: 'ocr', text: t);
    });
    ocr.errors.listen((e) {
      ocrError = e;
      _addLog('ocr: $e');
    });
  }

  final AppSettings settings;
  late final HookPipeline pipeline;
  late final SourceKind sourceKind;
  late final ScreenOcrSource ocr;
  String? ocrError;
  Screenshot? regionScreenshot;

  TextractorCli? _cli;
  StreamSubscription? _lineSub;
  StreamSubscription? _logSub;

  AppMode mode = AppMode.setup;
  List<ProcessInfo> processes = const [];
  bool loadingProcesses = false;
  ProcessInfo? attached;
  String? attachError;
  List<String> models = const [];
  String? modelError;
  final List<String> log = <String>[];
  static const _logLimit = 300;

  bool get isAttached => attached != null && (_cli?.isRunning ?? false);

  /// True when text is flowing from the active source.
  bool get isActive => sourceKind == SourceKind.ocr ? ocr.running : isAttached;

  // ---------------------------------------------------------------- OCR

  Future<bool> requestScreenPermission() => ocr.channel.requestPermission();

  /// Grabs a screenshot of the display containing [anchor] (global points)
  /// and switches to the region picker.
  Future<void> beginRegionPick({Offset? anchor}) async {
    ocrError = null;
    try {
      await ocr.channel.requestPermission();
      regionScreenshot = await ocr.channel.screenshot(anchor: anchor);
      mode = AppMode.regionPick;
    } catch (e) {
      final msg = e.toString();
      permissionMissing = msg.contains('TCC') || msg.contains('declined');
      ocrError = permissionMissing
          ? 'macOS ยังไม่อนุญาตให้ HookTrans อ่านหน้าจอ เปิด System Settings → Privacy & Security → Screen Recording แล้วเปิดสวิตช์ของ hooktrans จากนั้นปิดแอปแล้วเปิดใหม่'
          : 'จับภาพหน้าจอไม่ได้: $msg';
    }
    notifyListeners();
  }

  bool permissionMissing = false;

  /// Opens the Screen Recording pane of System Settings.
  Future<void> openScreenRecordingSettings() async {
    if (!Platform.isMacOS) return;
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
    ]);
  }

  /// [globalRegion] is in global points; it is stored relative to the
  /// display it was picked on.
  Future<void> finishRegionPick(Rect? globalRegion) async {
    final shot = regionScreenshot;
    regionScreenshot = null;
    mode = AppMode.setup;
    if (shot != null && globalRegion != null && globalRegion.width > 4 && globalRegion.height > 4) {
      settings.region = globalRegion.shift(-shot.frame.topLeft);
      settings.displayId = shot.displayId;
      await settings.save();
      await startOcr();
    }
    notifyListeners();
  }

  Future<void> startOcr() async {
    final r = settings.region;
    if (r == null) return;
    ocrError = null;
    pipeline.reset();
    ocr
      ..rect = r
      ..displayId = settings.displayId
      ..languages = settings.ocrLanguages
      ..interval = Duration(milliseconds: settings.captureIntervalMs);
    await ocr.start();
    notifyListeners();
  }

  void stopOcr() {
    ocr.stop();
    notifyListeners();
  }

  Translator _makeTranslator() {
    switch (settings.engine) {
      case Engine.google:
        return GoogleTranslator(
          targetLanguage: googleLanguageCodes[settings.targetLanguage] ?? 'th',
          sourceLanguage: settings.sourceLanguage == 'auto'
              ? 'auto'
              : googleLanguageCodes[settings.sourceLanguage] ?? 'auto',
        );
      case Engine.lmStudio:
        return LmStudioTranslator(
          baseUrl: settings.lmStudioUrl,
          model: settings.model,
          token: settings.lmStudioToken,
          options: TranslateOptions(
            targetLanguage: settings.targetLanguage,
            sourceLanguage: settings.sourceLanguage,
            historyLines: settings.historyLines,
            glossary: settings.glossary,
            noThink: settings.noThink,
          ),
        );
    }
  }

  void _addLog(String s) {
    log.add(s);
    while (log.length > _logLimit) {
      log.removeAt(0);
    }
    notifyListeners();
  }

  Future<void> refreshProcesses() async {
    loadingProcesses = true;
    notifyListeners();
    try {
      processes = await listWindowedProcesses();
    } catch (e) {
      _addLog('process list failed: $e');
    } finally {
      loadingProcesses = false;
      notifyListeners();
    }
  }

  Future<void> refreshModels() async {
    modelError = null;
    notifyListeners();
    try {
      models = await LmStudioTranslator(
        baseUrl: settings.lmStudioUrl,
        model: '',
        token: settings.lmStudioToken,
      ).listModels();
      if (settings.model.isEmpty || !models.contains(settings.model)) {
        if (models.isNotEmpty) {
          settings.model = models.first;
          await settings.save();
        }
      }
    } catch (e) {
      models = const [];
      modelError = e.toString();
    }
    notifyListeners();
  }

  /// Starts the matching TextractorCLI and injects it into [p].
  Future<void> attach(ProcessInfo p) async {
    attachError = null;
    await detach();
    pipeline.reset();

    final is64 = p.bitness != Bitness.x86;
    final exe = textractorCliPath(settings.textractorDir, is64Bit: is64);
    final cli = TextractorCli(exe);
    try {
      await cli.start();
    } catch (e) {
      attachError = 'เปิด TextractorCLI ไม่ได้: $e';
      notifyListeners();
      return;
    }
    _cli = cli;
    _logSub = cli.log.listen(_addLog);
    _lineSub = cli.lines.listen(pipeline.onLine);
    cli.exitCode.then((_) {
      if (_cli == cli) {
        attached = null;
        attachError = 'TextractorCLI ปิดตัวไป';
        notifyListeners();
      }
    });
    await cli.attach(p.pid);
    attached = p;
    notifyListeners();
  }

  Future<void> sendHookCode(String code) async {
    final cli = _cli;
    final p = attached;
    if (cli == null || p == null) throw StateError('ยังไม่ได้ attach เกม');
    await cli.insertHook(code, p.pid);
  }

  Future<void> detach() async {
    final cli = _cli;
    _cli = null;
    attached = null;
    await _lineSub?.cancel();
    await _logSub?.cancel();
    _lineSub = null;
    _logSub = null;
    await cli?.stop();
    notifyListeners();
  }

  /// Call after the engine, model or language changed.
  Future<void> translatorChanged() async {
    await settings.save();
    if (settings.engine == Engine.lmStudio) await refreshModels();
    pipeline.retranslate();
  }

  void setMode(AppMode m) {
    mode = m;
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    ocr.dispose();
    pipeline.dispose();
    super.dispose();
  }
}
