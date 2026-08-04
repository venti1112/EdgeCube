import 'dart:io';

import 'package:path/path.dart' as p;

/// 现代 Forge/NeoForge（MC 1.17+）的启动支持。
///
/// 自 MC 1.17 起，Forge/NeoForge 安装器不再在实例根目录生成可直接 `-jar` 运行
/// 的服务端 jar，而是生成 `run.sh` / `run.bat` + `user_jvm_args.txt`，真正的
/// 服务端类位于 `libraries/…` 下，通过 JVM `@argfile`
/// （`libraries/net/minecraftforge/forge/<mc>-<forge>/unix_args.txt`）启动。
///
/// 为不改动实例配置结构与原生启动层，这里用一个「以 `@` 开头的 serverFile 哨兵」
/// 承载该 argfile 的相对路径：
/// - 安装页检测到现代布局时，将 serverFile 记为 `@<相对路径>`；
/// - 启动时若 serverFile 以 `@` 开头，则作为 JVM argfile 传入而非 `-jar`。
///
/// 旧版 Forge（≤1.16）仍生成可运行的根 jar，走原有 `-jar` 流程，不受影响。
class ForgeLaunch {
  ForgeLaunch._();

  /// serverFile 哨兵前缀：以此开头表示「用 JVM @argfile 启动」。
  static const String argfilePrefix = '@';

  /// 判断某个 serverFile 是否为现代 Forge 的 @argfile 启动方式。
  static bool isArgfile(String? serverFile) =>
      serverFile != null && serverFile.startsWith(argfilePrefix);

  /// 从 @argfile 哨兵中取出实际的相对路径（去掉前缀 `@`）。
  static String argfilePath(String serverFile) =>
      serverFile.substring(argfilePrefix.length);

  /// 在实例目录中检测现代 Forge/NeoForge 布局，返回 @argfile 哨兵字符串
  /// （如 `@libraries/net/minecraftforge/forge/1.20.1-47.4.20/unix_args.txt`），
  /// 未检测到则返回 null。
  ///
  /// 优先解析 `run.sh` 中 `@libraries/.../unix_args.txt` 的确切路径（最可靠），
  /// 失败再回退到在 `libraries/` 下搜索 `unix_args.txt`。
  static String? detectArgfile(Directory dir) {
    final fromScript = _argfileFromRunScript(dir);
    if (fromScript != null) return '$argfilePrefix$fromScript';
    final globbed = _argfileByGlob(dir);
    if (globbed != null) return '$argfilePrefix$globbed';
    return null;
  }

  /// 解析 run.sh，提取 `@libraries/.../unix_args.txt` 的相对路径。
  static String? _argfileFromRunScript(Directory dir) {
    final runSh = File(p.join(dir.path, 'run.sh'));
    if (!runSh.existsSync()) return null;
    final String content;
    try {
      content = runSh.readAsStringSync();
    } catch (_) {
      return null;
    }
    // 匹配 `@libraries/....../unix_args.txt`（run.sh 中以 @ 引用的 argfile）。
    final match = RegExp(
      r'@(libraries/\S*?unix_args\.txt)',
    ).firstMatch(content);
    if (match == null) return null;
    final rel = match.group(1)!;
    // 确认文件确实存在，避免记录一个无效路径。
    if (File(p.join(dir.path, rel)).existsSync()) return rel;
    return null;
  }

  /// 在 `libraries/` 下递归搜索 `unix_args.txt`，返回首个命中的相对路径。
  static String? _argfileByGlob(Directory dir) {
    final libraries = Directory(p.join(dir.path, 'libraries'));
    if (!libraries.existsSync()) return null;
    try {
      for (final entry in libraries.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File && p.basename(entry.path) == 'unix_args.txt') {
          return p.relative(entry.path, from: dir.path).replaceAll('\\', '/');
        }
      }
    } catch (_) {}
    return null;
  }
}
