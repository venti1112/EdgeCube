import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'settings/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预加载 + override:Notifier 的 build() 能同步读到已保存的外观设置,
  // 首帧即为正确主题,不会先闪一下默认外观。
  final storage = await SharedPreferences.getInstance();
  final appearance = await loadAppearanceSettings(storage);

  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        initialAppearanceProvider.overrideWithValue(appearance),
      ],
      child: const EdgeCubeApp(),
    ),
  );
}
