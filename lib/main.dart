import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'instance/instance_controller.dart';
import 'instance/instance_scope.dart';
import 'server/server_controller.dart';
import 'server/server_scope.dart';
import 'server/system_monitor_controller.dart';
import 'server/system_monitor_scope.dart';
import 'theme/theme_scope.dart';
import 'theme/theme_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialThemeMode = await ThemeStore.load();
  final instanceController = InstanceController();
  await instanceController.init();
  final serverController = ServerController();
  // 让服务端状态机能查询某实例是否开启兼容模式（兼容模式跳过「启动中」标签）。
  serverController.compatModeResolver =
      (id) => instanceController.byId(id)?.compatMode ?? false;
  final systemMonitorController = SystemMonitorController();
  runApp(EdgeCubeApp(
    initialThemeMode: initialThemeMode,
    instanceController: instanceController,
    serverController: serverController,
    systemMonitorController: systemMonitorController,
  ));
}

class EdgeCubeApp extends StatefulWidget {
  const EdgeCubeApp({
    super.key,
    this.initialThemeMode = ThemeMode.system,
    required this.instanceController,
    required this.serverController,
    required this.systemMonitorController,
  });

  final ThemeMode initialThemeMode;
  final InstanceController instanceController;
  final ServerController serverController;
  final SystemMonitorController systemMonitorController;

  @override
  State<EdgeCubeApp> createState() => _EdgeCubeAppState();
}

class _EdgeCubeAppState extends State<EdgeCubeApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;

  void _setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    setState(() => _themeMode = mode);
    ThemeStore.save(mode);
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      themeMode: _themeMode,
      setThemeMode: _setThemeMode,
      child: InstanceScope(
        controller: widget.instanceController,
        child: ServerScope(
          controller: widget.serverController,
          child: SystemMonitorScope(
            controller: widget.systemMonitorController,
            child: MaterialApp(
              title: 'EdgeCube',
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.green,
                  brightness: Brightness.dark,
                ),
              ),
              themeMode: _themeMode,
              home: const HomeShell(),
            ),
          ),
        ),
      ),
    );
  }
}
