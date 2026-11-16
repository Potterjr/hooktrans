import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_controller.dart';
import '../core/pipeline.dart';
import '../core/process_list.dart';
import '../core/settings.dart';
import '../core/thread_picker.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _search = TextEditingController();
  final _hookCode = TextEditingController();
  late final TextEditingController _lmUrl;
  late final TextEditingController _lmToken;
  late final TextEditingController _textractorDir;
  String? _hookError;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _lmUrl = TextEditingController(text: c.settings.lmStudioUrl);
    _lmToken = TextEditingController(text: c.settings.lmStudioToken);
    _textractorDir = TextEditingController(text: c.settings.textractorDir);
    // Refreshes notify the controller; run them after the first frame so the
    // parent ListenableBuilder is not rebuilt while it is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (c.sourceKind == SourceKind.hook) c.refreshProcesses();
      if (c.settings.engine == Engine.lmStudio) c.refreshModels();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _hookCode.dispose();
    _lmUrl.dispose();
    _lmToken.dispose();
    _textractorDir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    final p = c.pipeline;
    return Scaffold(
      appBar: AppBar(
        title: const Text('HookTrans'),
        actions: [
          FilledButton.icon(
            onPressed: c.isActive ? () => c.setMode(AppMode.overlay) : null,
            icon: const Icon(Icons.open_in_new),
            label: const Text('เปิด Overlay'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 340, child: c.sourceKind == SourceKind.ocr ? _ocrColumn() : _gameColumn()),
          const VerticalDivider(width: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('2. เครื่องมือแปล', _engineCard(s)),
                const SizedBox(height: 16),
                if (c.sourceKind == SourceKind.hook) ...[
                  _section('3. Thread บทพูด', _threadCard(p)),
                  const SizedBox(height: 16),
                ],
                _section('ตัวอย่างผลแปล', _previewCard(p, s)),
                const SizedBox(height: 16),
                _advanced(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  // ------------------------------------------------------------ screen OCR

  static const _ocrLangs = {
    'ja': 'ญี่ปุ่น',
    'en': 'อังกฤษ',
    'zh-Hans': 'จีน',
    'ko': 'เกาหลี',
    'th': 'ไทย',
  };

  Widget _ocrColumn() {
    final s = c.settings;
    final r = s.region;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('1. พื้นที่ subtitle บนหน้าจอ', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'เปิดเกมให้เห็นกล่องข้อความ แล้วกดปุ่มด้านล่าง ลากกรอบรอบกล่องข้อความ',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            final b = await windowManager.getBounds();
            await c.beginRegionPick(anchor: b.center);
          },
          icon: const Icon(Icons.crop),
          label: Text(r == null ? 'เลือกพื้นที่บนหน้าจอ' : 'เลือกพื้นที่ใหม่'),
        ),
        if (r != null) ...[
          const SizedBox(height: 8),
          Text(
            'พื้นที่: ${r.left.round()},${r.top.round()}  ${r.width.round()}×${r.height.round()}',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: c.ocr.running ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 6),
              Text(c.ocr.running ? 'กำลังอ่านหน้าจอ' : 'หยุดอยู่'),
              const Spacer(),
              c.ocr.running
                  ? OutlinedButton(onPressed: c.stopOcr, child: const Text('หยุด'))
                  : FilledButton.tonal(onPressed: c.startOcr, child: const Text('เริ่มอ่าน')),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
            child: Text(
              c.ocr.lastText.isEmpty ? 'ยังอ่านไม่เจอข้อความในกรอบ' : c.ocr.lastText,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (c.ocrError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(c.ocrError!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ),
        if (c.permissionMissing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: c.openScreenRecordingSettings,
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('เปิด System Settings'),
            ),
          ),
        const Divider(height: 32),
        Text('ภาษาในเกม (OCR)', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final e in _ocrLangs.entries)
              FilterChip(
                label: Text(e.value),
                selected: s.ocrLanguages.contains(e.key),
                onSelected: (v) async {
                  final l = [...s.ocrLanguages];
                  v ? l.add(e.key) : l.remove(e.key);
                  if (l.isEmpty) return;
                  s.ocrLanguages = l;
                  await s.save();
                  c.ocr.languages = l;
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('ความถี่ในการอ่าน: ${s.captureIntervalMs} ms', style: Theme.of(context).textTheme.labelLarge),
        Slider(
          value: s.captureIntervalMs.toDouble(),
          min: 100,
          max: 1000,
          divisions: 9,
          label: '${s.captureIntervalMs} ms',
          onChanged: (v) async {
            s.captureIntervalMs = v.round();
            await s.save();
            c.ocr.interval = Duration(milliseconds: s.captureIntervalMs);
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'ครั้งแรก macOS จะถามสิทธิ์ Screen Recording ให้อนุญาตแล้วเปิดแอปใหม่',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- games

  Widget _gameColumn() {
    final q = _search.text.toLowerCase();
    final list = c.processes
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.windowTitle.toLowerCase().contains(q))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(child: Text('1. เลือกเกม', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: 'โหลดรายชื่อใหม่',
                onPressed: c.loadingProcesses ? null : c.refreshProcesses,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'ค้นหาชื่อเกม',
            ),
          ),
        ),
        if (c.attachError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(c.attachError!, style: const TextStyle(color: Colors.redAccent)),
          ),
        Expanded(
          child: c.loadingProcesses
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => _processTile(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _processTile(ProcessInfo p) {
    final selected = c.attached?.pid == p.pid;
    final bits = switch (p.bitness) {
      Bitness.x86 => '32-bit',
      Bitness.x64 => '64-bit',
      Bitness.unknown => '?',
    };
    return ListTile(
      dense: true,
      selected: selected,
      leading: Icon(selected ? Icons.link : Icons.videogame_asset_outlined),
      title: Text(p.windowTitle.isEmpty ? p.name : p.windowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${p.name}.exe · $bits · pid ${p.pid}'),
      trailing: selected
          ? TextButton(onPressed: c.detach, child: const Text('ถอด'))
          : null,
      onTap: selected ? null : () => c.attach(p),
    );
  }

  // --------------------------------------------------------------- engine

  Widget _engineCard(AppSettings s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<Engine>(
              segments: const [
                ButtonSegment(value: Engine.lmStudio, icon: Icon(Icons.memory), label: Text('LM Studio (local)')),
                ButtonSegment(value: Engine.google, icon: Icon(Icons.cloud_outlined), label: Text('Google Translate')),
              ],
              selected: {s.engine},
              onSelectionChanged: (v) async {
                s.engine = v.first;
                await c.translatorChanged();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: supportedLanguages.contains(s.targetLanguage) ? s.targetLanguage : 'Thai',
                    decoration: const InputDecoration(labelText: 'แปลเป็น', isDense: true),
                    items: supportedLanguages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      s.targetLanguage = v;
                      await c.translatorChanged();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: s.sourceLanguage,
                    decoration: const InputDecoration(labelText: 'ภาษาเกม', isDense: true),
                    items: [
                      const DropdownMenuItem(value: 'auto', child: Text('ตรวจอัตโนมัติ')),
                      ...supportedLanguages.map((l) => DropdownMenuItem(value: l, child: Text(l))),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      s.sourceLanguage = v;
                      await c.translatorChanged();
                    },
                  ),
                ),
              ],
            ),
            if (s.engine == Engine.lmStudio) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lmUrl,
                      decoration: const InputDecoration(labelText: 'LM Studio server URL', isDense: true),
                      onSubmitted: (v) async {
                        s.lmStudioUrl = v.trim();
                        await s.save();
                        c.refreshModels();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'โหลดรายชื่อโมเดล',
                    onPressed: () async {
                      s.lmStudioUrl = _lmUrl.text.trim();
                      s.lmStudioToken = _lmToken.text.trim();
                      await s.save();
                      c.refreshModels();
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lmToken,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API token (ถ้า LM Studio เปิด Require authentication)',
                  isDense: true,
                ),
                onSubmitted: (v) async {
                  s.lmStudioToken = v.trim();
                  await s.save();
                  c.refreshModels();
                },
              ),
              const SizedBox(height: 12),
              if (c.modelError != null)
                Text(
                  'ติดต่อ LM Studio ไม่ได้: ${c.modelError}\nเปิด LM Studio แล้วกด Start Server ที่แท็บ Developer หรือสลับไปใช้ Google Translate',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: c.models.contains(s.model) ? s.model : null,
                  decoration: const InputDecoration(labelText: 'โมเดล', isDense: true),
                  items: c.models.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    s.model = v;
                    await s.save();
                    c.pipeline.retranslate();
                  },
                ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('ปิด thinking (/no_think) เพื่อให้แปลเร็ว'),
                value: s.noThink,
                onChanged: (v) async {
                  s.noThink = v;
                  await s.save();
                },
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'ใช้ endpoint สาธารณะของ Google Translate ต้องต่ออินเทอร์เน็ต ไม่ต้องใช้ API key',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- threads

  Widget _threadCard(HookPipeline p) {
    final now = DateTime.now();
    final threads = p.threads.values.toList()
      ..sort((a, b) => scoreThread(b, now).compareTo(scoreThread(a, now)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'กดเดินบทพูดในเกม 2-3 ครั้ง แอปจะเลือก thread ที่เป็นบทพูดให้เอง '
                    'ถ้าเลือกผิด คลิกแถวที่ถูกต้องเพื่อปักหมุด',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ),
                FilterChip(
                  label: const Text('อัตโนมัติ'),
                  selected: p.autoPick,
                  onSelected: (v) => v ? p.selectThread(null) : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (threads.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('ยังไม่มีข้อความจากเกม', style: TextStyle(color: Colors.white38)),
              ),
            for (final t in threads.take(12))
              ListTile(
                dense: true,
                selected: t.id == p.selectedThread,
                leading: Icon(t.id == p.selectedThread ? Icons.push_pin : Icons.subject, size: 18),
                title: Text(t.lastText, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${t.name} · ${t.hookCode} · ${t.messages} msgs', style: const TextStyle(fontSize: 11)),
                onTap: () => p.selectThread(t.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(HookPipeline p, AppSettings s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.sourceText.isEmpty ? '—' : p.sourceText, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 8),
            if (p.error != null)
              Text(p.error!, style: const TextStyle(color: Colors.redAccent))
            else
              Text(
                p.translation.isEmpty ? (p.translating ? 'กำลังแปล…' : '—') : p.translation,
                style: TextStyle(fontSize: s.fontSize * 0.8),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: p.clearContext,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: const Text('ล้างบริบท'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- advanced

  Widget _advanced() {
    final s = c.settings;
    return ExpansionTile(
      title: const Text('ขั้นสูง'),
      childrenPadding: const EdgeInsets.all(12),
      children: [
        if (c.sourceKind == SourceKind.hook) TextField(
          controller: _textractorDir,
          decoration: const InputDecoration(
            labelText: 'โฟลเดอร์ Textractor (ต้องมี x86\\TextractorCLI.exe และ x64\\TextractorCLI.exe)',
            isDense: true,
          ),
          onSubmitted: (v) async {
            s.textractorDir = v.trim();
            await s.save();
          },
        ),
        if (c.sourceKind == SourceKind.hook) const SizedBox(height: 12),
        if (c.sourceKind == SourceKind.hook) Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hookCode,
                decoration: InputDecoration(
                  labelText: 'H-code / R-code (ถ้าเกมไม่ขึ้นบทพูด)',
                  isDense: true,
                  errorText: _hookError,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: c.isAttached
                  ? () async {
                      try {
                        await c.sendHookCode(_hookCode.text);
                        setState(() => _hookError = null);
                      } catch (e) {
                        setState(() => _hookError = e.toString());
                      }
                    }
                  : null,
              child: const Text('ส่ง'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Log', style: Theme.of(context).textTheme.labelLarge),
        ),
        Container(
          height: 140,
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(
              c.log.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}
