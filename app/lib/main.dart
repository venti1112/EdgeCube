import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_state/ui_style.dart';
import 'app_state/ui_style_scope.dart';
import 'shell/shell_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();
  runApp(const EdgeCubeApp());
}

/// 应用根:持有全局 [UiStyleController],通过 [UiStyleScope] 注入 widget 树。
///
/// 根据 [UiStyle] 决定是否用 `LiquidGlassWidgets.wrap` 包裹 [MaterialApp]:
/// - [UiStyle.material3]:不 wrap,纯 M3
/// - [UiStyle.liquidGlass]:wrap 注入 GlassTheme + GlassAdaptiveScope
///
/// 切换 [UiStyleController.value] 即时触发根重建。
class EdgeCubeApp extends StatefulWidget {
  const EdgeCubeApp({super.key});

  @override
  State<EdgeCubeApp> createState() => _EdgeCubeAppState();
}

class _EdgeCubeAppState extends State<EdgeCubeApp> {
  final _uiStyleController = UiStyleController();

  @override
  void dispose() {
    _uiStyleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UiStyleScope(
      controller: _uiStyleController,
      child: ListenableBuilder(
        listenable: _uiStyleController,
        builder: (context, _) {
          return _buildApp(_uiStyleController.value);
        },
      ),
    );
  }

  Widget _buildApp(UiStyle uiStyle) {
    final materialApp = MaterialApp(
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
      home: const ShellScaffold(),
    );

    switch (uiStyle) {
      case UiStyle.material3:
        return materialApp;
      case UiStyle.liquidGlass:
        return LiquidGlassWidgets.wrap(
          child: materialApp,
          adaptiveQuality: true,
          brightnessResolver: Theme.maybeBrightnessOf,
          theme: GlassThemeData.simple(
            blur: 10,
            thickness: 30,
            quality: GlassQuality.standard,
          ),
        );
    }
  }
}
