import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_controller.dart';
import 'core/settings.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final settings = AppSettings();
  await settings.load();
  final controller = AppController(settings);

  const options = WindowOptions(
    size: Size(960, 680),
    minimumSize: Size(640, 400),
    center: true,
    title: 'HookTrans',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(HookTransApp(controller: controller));
}
