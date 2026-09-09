import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'router.dart';
import 'settings/appearance.dart';

class EdgeCubeApp extends ConsumerWidget {
  const EdgeCubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appearanceSettingsProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Android 12+ 壁纸取色,跟随系统关闭或平台不支持时回退种子色
        final lightScheme = (s.followSystemColor && lightDynamic != null)
            ? lightDynamic.harmonized()
            : ColorScheme.fromSeed(seedColor: s.seedColor);
        final darkScheme = (s.followSystemColor && darkDynamic != null)
            ? darkDynamic.harmonized()
            : ColorScheme.fromSeed(
                seedColor: s.seedColor,
                brightness: Brightness.dark,
              );
        return MaterialApp.router(
          title: 'EdgeCube',
          themeMode: s.themeMode,
          theme: ThemeData(colorScheme: lightScheme),
          darkTheme: ThemeData(colorScheme: darkScheme),
          // material_ui 自带的是其自身的 MaterialLocalizations 实现;
          // 编辑器等 flutter/material 组件需要这三份 Global 代理才能取到
          // flutter 侧的 MaterialLocalizations/WidgetsLocalizations。
          localizationsDelegates: const [
            loc.GlobalMaterialLocalizations.delegate,
            loc.GlobalWidgetsLocalizations.delegate,
            loc.GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: ref.watch(routerProvider),
        );
      },
    );
  }
}
