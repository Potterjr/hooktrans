import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooktrans/core/process_list.dart';

Uint8List fakePe(int machine) {
  final b = Uint8List(0x100);
  b[0] = 0x4D;
  b[1] = 0x5A;
  b[0x3C] = 0x80; // e_lfanew = 0x80
  b[0x80] = 0x50;
  b[0x81] = 0x45;
  b[0x84] = machine & 0xFF;
  b[0x85] = machine >> 8;
  return b;
}

void main() {
  test('detects bitness from PE header', () async {
    final dir = await Directory.systemTemp.createTemp('pe');
    final f32 = File('${dir.path}/a.exe')..writeAsBytesSync(fakePe(0x014C));
    final f64 = File('${dir.path}/b.exe')..writeAsBytesSync(fakePe(0x8664));
    final junk = File('${dir.path}/c.exe')..writeAsBytesSync([1, 2, 3]);
    expect(detectBitness(f32.path), Bitness.x86);
    expect(detectBitness(f64.path), Bitness.x64);
    expect(detectBitness(junk.path), Bitness.unknown);
    expect(detectBitness('${dir.path}/missing.exe'), Bitness.unknown);
    await dir.delete(recursive: true);
  });

  test('parses PowerShell JSON for one or many processes', () {
    final many = parseProcessJson('[{"Id":1,"ProcessName":"game","Path":"C:\\\\g\\\\game.exe","MainWindowTitle":"Game"},'
        '{"Id":2,"ProcessName":"x","Path":null,"MainWindowTitle":"X"}]');
    expect(many.length, 2);
    expect(many[0].path, r'C:\g\game.exe');
    expect(many[1].path, isNull);
    final one = parseProcessJson('{"Id":5,"ProcessName":"solo","Path":"p","MainWindowTitle":"S"}');
    expect(one.single.pid, 5);
    expect(parseProcessJson(''), isEmpty);
  });
}
