import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'config/config_migration.dart';
import 'config/network_store.dart';
import 'home_shell.dart';
import 'instance/instance_controller.dart';
import 'instance/instance_scope.dart';
import 'online/online_service.dart';
import 'server/server_controller.dart';
import 'server/server_scope.dart';
import 'server/system_monitor_controller.dart';
import 'server/system_monitor_scope.dart';
import 'theme/theme_scope.dart';
import 'theme/theme_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 把旧版 SharedPreferences 中的历史配置迁移到新的文件式布局（只执行一次），
  // 必须先于下面任何新配置读取。
  await ConfigMigration.run();
  final initialThemeMode = await ThemeStore.load();
  final initialSeedColor = await ThemeStore.loadSeedColor();
  final initialUseDynamicColor = await ThemeStore.loadUseDynamicColor();
  final instanceController = InstanceController();
  await instanceController.init();
  final onlineService = OnlineService();
  await onlineService.init();
  final serverController = ServerController();
  // 让服务端状态机能查询某实例是否开启兼容模式（兼容模式跳过「启动中」标签）。
  serverController.compatModeResolver = instanceController.compatModeFor;
  // UPnP 端口映射开关：读取 config/network.json 中的持久化配置。
  serverController.upnpEnabledResolver = NetworkStore.loadUpnpEnabled;
  // FRP 隧道开关：读取 config/network.json 中的持久化配置。
  serverController.tunnelEnabledResolver = NetworkStore.loadTunnelEnabled;
  final systemMonitorController = SystemMonitorController();
  runApp(
    EdgeCubeApp(
      initialThemeMode: initialThemeMode,
      initialSeedColor: initialSeedColor,
      initialUseDynamicColor: initialUseDynamicColor,
      instanceController: instanceController,
      serverController: serverController,
      systemMonitorController: systemMonitorController,
      onlineService: onlineService,
    ),
  );
}

class EdgeCubeApp extends StatefulWidget {
  const EdgeCubeApp({
    super.key,
    this.initialThemeMode = ThemeMode.system,
    this.initialSeedColor = ThemeStore.defaultSeedColor,
    this.initialUseDynamicColor = false,
    required this.instanceController,
    required this.serverController,
    required this.systemMonitorController,
    required this.onlineService,
  });

  final ThemeMode initialThemeMode;
  final Color initialSeedColor;
  final bool initialUseDynamicColor;
  final InstanceController instanceController;
  final ServerController serverController;
  final SystemMonitorController systemMonitorController;
  final OnlineService onlineService;

  @override
  State<EdgeCubeApp> createState() => _EdgeCubeAppState();
}

class _EdgeCubeAppState extends State<EdgeCubeApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;
  late Color _seedColor = widget.initialSeedColor;
  late bool _useDynamicColor = widget.initialUseDynamicColor;

  void _setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    setState(() => _themeMode = mode);
    ThemeStore.save(mode);
  }

  void _setSeedColor(Color color) {
    if (color == _seedColor) return;
    setState(() => _seedColor = color);
    ThemeStore.saveSeedColor(color);
  }

  void _setUseDynamicColor(bool value) {
    if (value == _useDynamicColor) return;
    setState(() => _useDynamicColor = value);
    ThemeStore.saveUseDynamicColor(value);
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      themeMode: _themeMode,
      setThemeMode: _setThemeMode,
      seedColor: _seedColor,
      setSeedColor: _setSeedColor,
      useDynamicColor: _useDynamicColor,
      setUseDynamicColor: _setUseDynamicColor,
      child: InstanceScope(
        controller: widget.instanceController,
        child: ServerScope(
          controller: widget.serverController,
          child: SystemMonitorScope(
            controller: widget.systemMonitorController,
            child: DynamicColorBuilder(
              builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
                // 当用户开启「跟随系统主题色」且设备支持动态色时使用系统取色。
                final useDynamic = _useDynamicColor && lightDynamic != null;
                final lightScheme = useDynamic
                    ? lightDynamic
                    : ColorScheme.fromSeed(seedColor: _seedColor);
                final darkScheme = useDynamic
                    ? (darkDynamic ??
                          ColorScheme.fromSeed(
                            seedColor: _seedColor,
                            brightness: Brightness.dark,
                          ))
                    : ColorScheme.fromSeed(
                        seedColor: _seedColor,
                        brightness: Brightness.dark,
                      );

                return MaterialApp(
                  title: 'EdgeCube',
                  theme: ThemeData(colorScheme: lightScheme),
                  darkTheme: ThemeData(colorScheme: darkScheme),
                  themeMode: _themeMode,
                  home: HomeShell(onlineService: widget.onlineService),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
