import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'instance/instance_controller.dart';
import 'instance/instance_scope.dart';
import 'theme/theme_scope.dart';
import 'theme/theme_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialThemeMode = await ThemeStore.load();
  final instanceController = InstanceController();
  await instanceController.init();
  runApp(EdgeCubeApp(
    initialThemeMode: initialThemeMode,
    instanceController: instanceController,
  ));
}

class EdgeCubeApp extends StatefulWidget {
  const EdgeCubeApp({
    super.key,
    this.initialThemeMode = ThemeMode.system,
    required this.instanceController,
  });

  final ThemeMode initialThemeMode;
  final InstanceController instanceController;

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
    );
  }
}
