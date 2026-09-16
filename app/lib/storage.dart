import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局标准存储实例,main() 启动时初始化并 override。
///
/// 单独放在这里而不是某个具体设置模块内:外观、连接配置等都要用它,
/// 谁先定义谁被依赖会造成无谓的耦合。原定义在 `settings/appearance.dart`,
/// 那里保留了 `export`,老 import 路径依旧可用。
final storageProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('storageProvider 须在 main() 中 override'),
);
