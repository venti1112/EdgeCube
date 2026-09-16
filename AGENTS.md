# AGENTS.md

## 项目概述

本项目是一套 Minecraft 服务器管理软件，采用前后端分离架构：

- 前端 App：Flutter，跨平台（Android、Web、Linux、Windows），负责界面展示与用户交互。
- 后端 Daemon：Rust，常驻服务器，负责管理服务实例、PTY 终端、系统状态采集与推送。
- 通信方式：单个 WebSocket 长连接，在连接上实现类 HTTP 的一问一答，同时支持服务端主动推送。

## 关于 material_ui

https://pub.dev/packages/material_ui

### 描述
`material_ui` 是Flutter的官方Material UI库，实现了Google的Material Design设计系统。它提供了完整的现代化视觉组件、动画、排版、颜色系统和主题工具，用于在各种屏幕尺寸上构建美观且可访问的用户界面。在之前版本的 Flutter 中 Material 集成在 Flutter 中，从 Flutter 3.47.0 开始，Material 正在逐步与 Flutter 分离以便独立更新，该包即为分离出的包。

### 迁移指南

#### 步骤1: 迁移导入
运行以下命令进行数据驱动的Dart修复：
```bash
dart fix --apply --code=migrate_design_widgets
```
这将等效于添加`material_ui`到项目中，并将`package:flutter/material.dart`的导入更改为`package:material_ui/material_ui.dart`。

#### 步骤2: 迁移本地化（如需要）
如果不使用`GlobalMaterialLocalizations`或`GlobalCupertinoLocalizations`类，则无需更改。否则，使用`material_ui`和`cupertino_ui`中的新版本类。

典型的本地化委托配置：
```dart
localizationsDelegates: GlobalMaterialLocalizations.delegates,
```

#### 步骤3: 桥接遗留依赖（如需要）
如果应用使用仍然导入和依赖`package:flutter/material.dart`的第三方包或子树，使用`MaterialUiCompatibilityBridge`来桥接`ThemeData`和`MaterialLocalizations`。

在MaterialApp.builder中包装应用：
```dart
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) {
        return MaterialUiCompatibilityBridge(child: child!);
      },
      home: const HomeScreen(),
    );
  }
}
```

也可以包装包含遗留包小部件的单个子树：
```dart
Scaffold(
  appBar: AppBar(title: const Text('Modern Screen')),
  body: MaterialUiCompatibilityBridge(
    child: LegacyPackageWidget(),
  ),
)
```

### 相关资源
- [Material Design 3规范](https://m3.material.io/)
- [Flutter Material小部件目录](https://docs.flutter.dev/ui/widgets/material)
- [API参考](https://pub.dev/documentation/material_ui/latest/material_ui/)
- [问题跟踪器](https://github.com/flutter/flutter/issues?q=is%3Aissue+is%3Aopen+label%3A%22p%3A+material_ui%22)
- [GitHub仓库](https://github.com/flutter/packages/tree/main/packages/material_ui)

### 使用说明
在本项目中，**不使用**Flutter内建的Material样式（`package:flutter/material.dart`），而是使用独立的`material_ui`包（`package:material_ui/material_ui.dart`）。
