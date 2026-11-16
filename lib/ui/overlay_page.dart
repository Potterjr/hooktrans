import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_controller.dart';

/// Compact always-on-top window shown over the game.
class OverlayPage extends StatefulWidget {
  const OverlayPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> {
  @override
  void initState() {
    super.initState();
    _enterOverlay();
  }

  Future<void> _enterOverlay() async {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setMinimumSize(const Size(320, 100));
    await windowManager.setSize(const Size(900, 200));
    await windowManager.setOpacity(widget.controller.settings.overlayOpacity);
  }

  Future<void> _leaveOverlay() async {
    await windowManager.setOpacity(1);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(const Size(640, 400));
    await windowManager.setSize(const Size(960, 680));
    widget.controller.setMode(AppMode.setup);
  }

  Future<void> _bumpFont(double delta) async {
    final s = widget.controller.settings;
    s.fontSize = (s.fontSize + delta).clamp(12, 64);
    await s.save();
  }

  Future<void> _bumpOpacity(double delta) async {
    final s = widget.controller.settings;
    s.overlayOpacity = (s.overlayOpacity + delta).clamp(0.3, 1.0);
    await s.save();
    await windowManager.setOpacity(s.overlayOpacity);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = c.pipeline;
    final s = c.settings;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      body: Column(
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Container(
                      color: Colors.white10,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: p.translating
                                ? Colors.amber
                                : (c.isActive ? Colors.greenAccent : Colors.redAccent),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            c.sourceKind == SourceKind.ocr
                                ? (c.ocr.running ? 'กำลังอ่านหน้าจอ' : 'หยุดอ่านหน้าจอ')
                                : (c.attached?.name ?? 'ไม่ได้เชื่อมเกม'),
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                          const Spacer(),
                          const Text('ลากเพื่อย้าย', style: TextStyle(fontSize: 10, color: Colors.white38)),
                        ],
                      ),
                    ),
                  ),
                ),
                _tiny(Icons.text_decrease, () => _bumpFont(-2), 'ตัวเล็กลง'),
                _tiny(Icons.text_increase, () => _bumpFont(2), 'ตัวใหญ่ขึ้น'),
                _tiny(Icons.opacity, () => _bumpOpacity(-0.1), 'โปร่งขึ้น'),
                _tiny(Icons.brightness_7, () => _bumpOpacity(0.1), 'ทึบขึ้น'),
                _tiny(
                  s.showSource ? Icons.subtitles : Icons.subtitles_off,
                  () async {
                    s.showSource = !s.showSource;
                    await s.save();
                  },
                  'ซ่อน/แสดงต้นฉบับ',
                ),
                _tiny(Icons.settings, _leaveOverlay, 'กลับไปหน้าตั้งค่า'),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.showSource && p.sourceText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          p.sourceText,
                          style: TextStyle(fontSize: s.fontSize * 0.6, color: Colors.white54),
                        ),
                      ),
                    if (p.error != null)
                      Text(p.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))
                    else
                      Text(
                        p.translation.isEmpty
                            ? (p.translating ? '…' : 'รอบทพูดจากเกม')
                            : p.translation,
                        style: TextStyle(
                          fontSize: s.fontSize,
                          height: 1.3,
                          color: Colors.white,
                          shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tiny(IconData icon, VoidCallback onTap, String tip) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 28,
          color: Colors.white10,
          child: Icon(icon, size: 14, color: Colors.white70),
        ),
      ),
    );
  }
}
