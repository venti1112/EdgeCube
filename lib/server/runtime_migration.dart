import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 旧版（beta9+9 及更早）内置于 assets 的运行时目录迁移。
///
/// 新版改为用户手动导入 `.ecpkg`，运行时存于 `filesDir/runtimes/<id>/`，
/// 与旧版的 `filesDir/runtimes/<version>/` 路径冲突。检测到旧版升级时，
/// 删除整个 `runtimes` 目录，让用户重新导入所需运行时。
class RuntimeMigration {
  RuntimeMigration._();

  /// 判断 [lastVersion] 是否需要清除旧运行时目录。
  ///
  /// 版本格式为 `<semver>+<buildNumber>`，仅判断构建号是否小于等于 9。
  static bool shouldClearRuntimes(String? lastVersion) {
    if (lastVersion == null || lastVersion.isEmpty) return false;
    final plus = lastVersion.lastIndexOf('+');
    if (plus < 0 || plus == lastVersion.length - 1) return false;
    final build = int.tryParse(lastVersion.substring(plus + 1));
    if (build == null) return false;
    return build <= 9;
  }

  /// 删除旧运行时目录。目录不存在或非目录时静默跳过。
  static Future<void> clearOldRuntimes() async {
    final supportDir = await getApplicationSupportDirectory();
    final runtimesDir = Directory(p.join(supportDir.path, 'runtimes'));
    if (!await runtimesDir.exists()) return;
    await runtimesDir.delete(recursive: true);
  }
}
