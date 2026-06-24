import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 旧版（beta7+7 及更早）内置于 assets 的运行时目录迁移。
///
/// 新版改为用户手动导入 `.ecpkg`，运行时存于 `filesDir/runtimes/<id>/`，
/// 与旧版的 `filesDir/runtimes/<version>/` 路径冲突。检测到旧版升级时，
/// 删除整个 `runtimes` 目录，让用户重新导入所需运行时。
class RuntimeMigration {
  RuntimeMigration._();

  static const _maxVersion = _Version(1, 0, 0, 'beta7', 7);

  /// 判断 [lastVersion] 是否需要清除旧运行时目录。
  ///
  /// 版本格式为 `<semver>+<buildNumber>`，例如 `1.0.0-beta7+7`。
  static bool shouldClearRuntimes(String? lastVersion) {
    if (lastVersion == null || lastVersion.isEmpty) return false;
    final v = _parseVersion(lastVersion);
    if (v == null) return false;
    return v.compareTo(_maxVersion) <= 0;
  }

  /// 删除旧运行时目录。目录不存在或非目录时静默跳过。
  static Future<void> clearOldRuntimes() async {
    final docs = await getApplicationDocumentsDirectory();
    final runtimesDir = Directory(p.join(docs.path, 'runtimes'));
    if (!await runtimesDir.exists()) return;
    await runtimesDir.delete(recursive: true);
  }
}

class _Version implements Comparable<_Version> {
  const _Version(this.major, this.minor, this.patch, this.pre, this.build);

  final int major;
  final int minor;
  final int patch;
  final String pre;
  final int build;

  @override
  int compareTo(_Version other) {
    var c = major.compareTo(other.major);
    if (c != 0) return c;
    c = minor.compareTo(other.minor);
    if (c != 0) return c;
    c = patch.compareTo(other.patch);
    if (c != 0) return c;
    c = _comparePreRelease(pre, other.pre);
    if (c != 0) return c;
    return build.compareTo(other.build);
  }

  static int _comparePreRelease(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;
    final aNum = int.tryParse(a.replaceAll(RegExp(r'^beta'), ''));
    final bNum = int.tryParse(b.replaceAll(RegExp(r'^beta'), ''));
    if (aNum != null && bNum != null) return aNum.compareTo(bNum);
    return a.compareTo(b);
  }
}

/// 从 `1.0.0-beta7+7` 格式解析版本号；解析失败返回 null。
_Version? _parseVersion(String version) {
  final plus = version.lastIndexOf('+');
  if (plus < 0 || plus == version.length - 1) return null;
  final build = int.tryParse(version.substring(plus + 1));
  if (build == null) return null;

  final semver = version.substring(0, plus);
  final parts = semver.split('-');
  final nums = parts[0].split('.');
  if (nums.length < 3) return null;
  final major = int.tryParse(nums[0]);
  final minor = int.tryParse(nums[1]);
  final patch = int.tryParse(nums[2]);
  if (major == null || minor == null || patch == null) return null;

  final pre = parts.length > 1 ? parts.sublist(1).join('-') : '';
  return _Version(major, minor, patch, pre, build);
}
