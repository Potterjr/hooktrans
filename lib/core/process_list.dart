/// Enumerates windowed processes on Windows and detects their bitness.
library;

import 'dart:convert';
import 'dart:io';

enum Bitness { x86, x64, unknown }

class ProcessInfo {
  const ProcessInfo({
    required this.pid,
    required this.name,
    required this.path,
    required this.windowTitle,
    this.bitness = Bitness.unknown,
  });

  final int pid;
  final String name;
  final String? path;
  final String windowTitle;
  final Bitness bitness;

  ProcessInfo withBitness(Bitness b) => ProcessInfo(
        pid: pid,
        name: name,
        path: path,
        windowTitle: windowTitle,
        bitness: b,
      );
}

/// Reads the PE header to find out whether an executable is 32 or 64 bit.
Bitness detectBitness(String exePath) {
  try {
    final raf = File(exePath).openSync();
    try {
      if (raf.lengthSync() < 0x40) return Bitness.unknown;
      raf.setPositionSync(0);
      final mz = raf.readSync(2);
      if (mz[0] != 0x4D || mz[1] != 0x5A) return Bitness.unknown;
      raf.setPositionSync(0x3C);
      final b = raf.readSync(4);
      final peOffset = b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);
      raf.setPositionSync(peOffset);
      final pe = raf.readSync(6);
      if (pe[0] != 0x50 || pe[1] != 0x45) return Bitness.unknown;
      final machine = pe[4] | (pe[5] << 8);
      switch (machine) {
        case 0x014C:
          return Bitness.x86;
        case 0x8664:
        case 0xAA64:
          return Bitness.x64;
        default:
          return Bitness.unknown;
      }
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return Bitness.unknown;
  }
}

/// Parses the JSON that the PowerShell query below prints.
List<ProcessInfo> parseProcessJson(String json) {
  if (json.trim().isEmpty) return const [];
  final decoded = jsonDecode(json);
  final list = decoded is List ? decoded : [decoded];
  return list.map((e) {
    final m = e as Map<String, dynamic>;
    return ProcessInfo(
      pid: (m['Id'] as num).toInt(),
      name: (m['ProcessName'] ?? '') as String,
      path: m['Path'] as String?,
      windowTitle: (m['MainWindowTitle'] ?? '') as String,
    );
  }).toList();
}

const _psScript = r'''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8;
Get-Process | Where-Object { $_.MainWindowTitle -ne '' } |
  Select-Object Id, ProcessName, Path, MainWindowTitle |
  ConvertTo-Json -Compress
''';

/// Lists processes that own a visible window (games do; services do not).
Future<List<ProcessInfo>> listWindowedProcesses() async {
  if (!Platform.isWindows) return const [];
  final res = await Process.run(
    'powershell',
    ['-NoProfile', '-NonInteractive', '-Command', _psScript],
    stdoutEncoding: utf8,
  );
  if (res.exitCode != 0) {
    throw ProcessException('powershell', const [], res.stderr.toString(), res.exitCode);
  }
  final procs = parseProcessJson(res.stdout as String);
  return procs
      .map((p) => p.path == null ? p : p.withBitness(detectBitness(p.path!)))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
