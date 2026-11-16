import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_controller.dart';

/// Full-screen page showing a frozen screenshot; the user drags a rectangle
/// around the game's subtitle box.
class RegionPickerPage extends StatefulWidget {
  const RegionPickerPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<RegionPickerPage> createState() => _RegionPickerPageState();
}

class _RegionPickerPageState extends State<RegionPickerPage> {
  Rect? _savedBounds;
  Rect _windowBounds = Rect.zero;
  Offset? _start;
  Rect? _sel; // in window-local logical pixels
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _enter();
  }

  Future<void> _enter() async {
    final shot = widget.controller.regionScreenshot!;
    _savedBounds = await windowManager.getBounds();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setMinimumSize(const Size(100, 100));
    await windowManager.setBounds(shot.frame);
    // The OS may keep the window below the menu bar; read back where it ended
    // up so the screenshot can be aligned with the real screen.
    _windowBounds = await windowManager.getBounds();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _leave(Rect? regionInScreenPoints) async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(const Size(640, 400));
    final b = _savedBounds;
    if (b != null) await windowManager.setBounds(b);
    await widget.controller.finishRegionPick(regionInScreenPoints);
  }

  void _confirm() {
    final s = _sel;
    if (s == null) return;
    _leave(s.shift(_windowBounds.topLeft));
  }

  @override
  Widget build(BuildContext context) {
    final shot = widget.controller.regionScreenshot!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_ready
          ? const SizedBox.shrink()
          : Stack(
              children: [
                Positioned(
                  left: shot.frame.left - _windowBounds.left,
                  top: shot.frame.top - _windowBounds.top,
                  width: shot.frame.width,
                  height: shot.frame.height,
                  child: Image.memory(shot.png, fit: BoxFit.fill, gaplessPlayback: true),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => setState(() {
                      _start = d.localPosition;
                      _sel = Rect.fromPoints(d.localPosition, d.localPosition);
                    }),
                    onPanUpdate: (d) => setState(() {
                      _sel = Rect.fromPoints(_start!, d.localPosition);
                    }),
                    child: CustomPaint(painter: _DimPainter(_sel)),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Material(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('ลากกรอบรอบกล่องข้อความของเกม', style: TextStyle(color: Colors.white)),
                            const SizedBox(width: 16),
                            TextButton(onPressed: () => _leave(null), child: const Text('ยกเลิก')),
                            FilledButton(
                              onPressed: _sel != null && _sel!.width > 4 ? _confirm : null,
                              child: const Text('ใช้พื้นที่นี้'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter(this.sel);
  final Rect? sel;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final full = Offset.zero & size;
    if (sel == null) {
      canvas.drawRect(full, dim);
      return;
    }
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(full), Path()..addRect(sel!)),
      dim,
    );
    canvas.drawRect(
      sel!,
      Paint()
        ..color = Colors.lightBlueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.sel != sel;
}
