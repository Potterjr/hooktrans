/// Dart side of the "hooktrans/screen" method channel (macOS only).
library;


import 'package:flutter/services.dart';

class Screenshot {
  const Screenshot({required this.png, required this.displayId, required this.frame, required this.scale});
  final Uint8List png;
  final int displayId;

  /// Display frame in global points (top-left origin, main display at 0,0).
  final Rect frame;
  final double scale;
}

class ScreenChannel {
  ScreenChannel([MethodChannel? channel]) : _ch = channel ?? const MethodChannel('hooktrans/screen');

  final MethodChannel _ch;

  Future<bool> requestPermission() async =>
      await _ch.invokeMethod<bool>('requestPermission') ?? false;

  /// Screenshot of the display containing [anchor] (global points), or the
  /// main display when null.
  Future<Screenshot> screenshot({Offset? anchor}) async {
    final m = await _ch.invokeMapMethod<String, dynamic>('screenshot', {
      if (anchor != null) 'x': anchor.dx,
      if (anchor != null) 'y': anchor.dy,
    });
    if (m == null) throw PlatformException(code: 'screenshot', message: 'no result');
    return Screenshot(
      png: m['png'] as Uint8List,
      displayId: (m['displayId'] as num).toInt(),
      frame: Rect.fromLTWH(
        (m['left'] as num?)?.toDouble() ?? 0,
        (m['top'] as num?)?.toDouble() ?? 0,
        (m['width'] as num).toDouble(),
        (m['height'] as num).toDouble(),
      ),
      scale: (m['scale'] as num).toDouble(),
    );
  }

  /// OCRs [rect] (points relative to the display's top-left). Returns null
  /// when the region has not changed since the previous call.
  Future<String?> captureText(Rect rect, List<String> languages, {bool force = false, int? displayId}) async {
    final m = await _ch.invokeMapMethod<String, dynamic>('captureText', {
      'x': rect.left,
      'y': rect.top,
      'w': rect.width,
      'h': rect.height,
      'languages': languages,
      'force': force,
      'displayId': ?displayId,
    });
    if (m == null || m['changed'] != true) return null;
    return m['text'] as String? ?? '';
  }
}
