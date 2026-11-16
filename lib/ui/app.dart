import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'overlay_page.dart';
import 'region_picker_page.dart';
import 'setup_page.dart';

class HookTransApp extends StatelessWidget {
  const HookTransApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HookTrans',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C9CFF),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => switch (controller.mode) {
          AppMode.overlay => OverlayPage(controller: controller),
          AppMode.regionPick => RegionPickerPage(controller: controller),
          AppMode.setup => SetupPage(controller: controller),
        },
      ),
    );
  }
}
