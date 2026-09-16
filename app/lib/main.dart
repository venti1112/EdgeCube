import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'connection/settings.dart';
import 'connection/state.dart';
import 'settings/appearance.dart';
import 'storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预加载 + override:Notifier 的 build() 能同步读到已保存的设置,
  // 首帧即为正确主题,也不会先闪一下连接页再跳走。
  final storage = await SharedPreferences.getInstance();
  final appearance = await loadAppearanceSettings(storage);
  // null = 从未成功连接过 → 路由守卫会先显示连接页
  final connection = loadPersistedConnection(storage);

  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        initialAppearanceProvider.overrideWithValue(appearance),
        initialPersistedConnectionProvider.overrideWithValue(connection),
        // 编辑中的工作副本:有历史就回填,方便「连接设置」里改一个字段就重连
        initialConnectionSettingsProvider.overrideWithValue(
          connection ?? ConnectionSettings.empty,
        ),
      ],
      child: const EdgeCubeApp(),
    ),
  );
}
