import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'connection/state.dart';
import 'router.dart';
import 'settings/appearance.dart';

class EdgeCubeApp extends ConsumerStatefulWidget {
  const EdgeCubeApp({super.key});

  @override
  ConsumerState<EdgeCubeApp> createState() => _EdgeCubeAppState();
}

class _EdgeCubeAppState extends ConsumerState<EdgeCubeApp> {
  @override
  void initState() {
    super.initState();
    // 有历史配置就自动连(首次启动无配置时什么也不做,停在连接页)。
    // 放到首帧之后:build / 导航期间不该改 Provider 状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(connectionProvider.notifier).connectIfConfigured();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 主题相关三项各自的全局 Provider:改主题色不会牵连其它设置
    final themeMode = ref.watch(themeModeProvider);
    final followSystemColor = ref.watch(followSystemColorProvider);
    final seedColor = ref.watch(seedColorProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Android 12+ 壁纸取色,跟随系统关闭或平台不支持时回退种子色
        final lightScheme = (followSystemColor && lightDynamic != null)
            ? lightDynamic.harmonized()
            : ColorScheme.fromSeed(seedColor: seedColor);
        final darkScheme = (followSystemColor && darkDynamic != null)
            ? darkDynamic.harmonized()
            : ColorScheme.fromSeed(
                seedColor: seedColor,
                brightness: Brightness.dark,
              );
        return MaterialApp.router(
          title: 'EdgeCube',
          themeMode: themeMode,
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
