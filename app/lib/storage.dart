import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局标准存储实例,main() 启动时初始化并 override。
final storageProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('storageProvider 须在 main() 中 override'),
);
