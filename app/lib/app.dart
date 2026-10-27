import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'connection/state.dart';
import 'local_service/settings.dart';
import 'local_service/state.dart';
import 'router.dart';
import 'settings/appearance.dart';
import 'shell/glass.dart';

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
    // 开了本地服务则先把它拉起来,等服务就绪后由 LocalServiceNotifier 自动连接。
    // 放到首帧之后:build / 导航期间不该改 Provider 状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(localServiceEnabledProvider)) {
        ref.read(localServiceProvider.notifier).startIfEnabled();
      } else {
        ref.read(connectionProvider.notifier).connectIfConfigured();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 主题相关几项各自的全局 Provider:改主题色不会牵连其它设置
    final themeMode = ref.watch(themeModeProvider);
    final followSystemColor = ref.watch(followSystemColorProvider);
    final seedColor = ref.watch(seedColorProvider);
    final globalFontFamily = ref.watch(globalFontFamilyProvider);
    // 毛玻璃模式下条目也要跟着透明:卡片走「玻璃配方」(半透明 + 细描边),
    // 否则实心卡片盖在外壳的 BackdropFilter 上就是一条条黑条。
    final glass = ref.watch(glassModeEnabledProvider);
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
        ThemeData themeFor(ColorScheme scheme) => ThemeData(
          colorScheme: scheme,
          // 全局字体族名(null = 跟随系统默认)。字体得装在系统里,
          // Flutter 没有跨平台的「列出已装字体」接口,所以设置页是手填。
          fontFamily: globalFontFamily,
          cardTheme: glass ? glassCardTheme(scheme) : null,
        );
        return MaterialApp.router(
          title: 'EdgeCube',
          themeMode: themeMode,
          theme: themeFor(lightScheme),
          darkTheme: themeFor(darkScheme),
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
