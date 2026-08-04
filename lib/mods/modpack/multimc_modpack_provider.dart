import 'dart:convert';

import 'package:archive/archive.dart';

import '../../i18n/i18n_service.dart';
import 'modpack_provider.dart';
import 'modpack_utils.dart';

/// MultiMC / PrismLauncher 整合包解析器。
///
/// 签名：`mmc-pack.json`（组件列表）+ `instance.cfg`。支持根目录或单层子目录
/// 包裹。mods 等内容直接内嵌在归档的 `.minecraft/`（或 `minecraft/`）目录，
/// 通过 overrides 机制平铺展开，无需 URL 下载。
///
/// 从 `mmc-pack.json` 的 `components[].uid` 归一加载器版本到 Modrinth 键名。
class MultiMcModpackProvider extends ModpackProvider {
  const MultiMcModpackProvider();

  static const _manifest = 'mmc-pack.json';

  /// MultiMC 组件 uid → Modrinth 依赖键名。
  static const _componentMap = {
    'net.minecraft': 'minecraft',
    'net.minecraftforge': 'forge',
    'net.neoforged': 'neoforge',
    'net.fabricmc.fabric-loader': 'fabric-loader',
    'org.quiltmc.quilt-loader': 'quilt-loader',
  };

  @override
  ModpackFormat get format => ModpackFormat.multimc;

  @override
  bool matches(Archive archive, {required String baseFolder}) =>
      ModpackUtils.hasEntry(archive, _manifest);

  @override
  Future<ParsedModpack> parse(
    String archivePath,
    Archive archive, {
    required String baseFolder,
  }) async {
    final entry = ModpackUtils.findEntry(archive, _manifest);
    if (entry == null) {
      throw ModpackParseException(tr('modpack.manifestNotFound'));
    }
    // 以签名条目实际位置推导 baseFolder（支持子目录包裹）。
    final base = ModpackUtils.baseFolderOf(entry, _manifest);

    final Map<String, dynamic> data;
    try {
      final str = utf8.decode(entry.content as List<int>, allowMalformed: true);
      data = jsonDecode(str) as Map<String, dynamic>;
    } catch (e) {
      throw ModpackParseException(
        tr('modpack.parseManifestFailed', {'error': '$e'}),
      );
    }

    final deps = <String, String>{};
    for (final c
        in (data['components'] as List? ?? [])
            .whereType<Map<String, dynamic>>()) {
      final uid = c['uid'] as String?;
      final version = c['version'] as String?;
      if (uid == null || version == null) continue;
      final key = _componentMap[uid];
      if (key != null) deps[key] = version;
    }

    // MultiMC 的实例内容在 .minecraft/ 或 minecraft/，平铺到实例根目录。
    // 无 URL 下载文件，全部走 overrides。
    return ParsedModpack(
      format: ModpackFormat.multimc,
      name: _readInstanceName(archive, base),
      dependencies: deps,
      files: const [],
      overridePrefixes: ['$base.minecraft/', '${base}minecraft/'],
    );
  }

  /// 从 instance.cfg 读取实例名（INI 风格 `name=xxx`）。缺失返回 null。
  String? _readInstanceName(Archive archive, String base) {
    final cfg = ModpackUtils.findEntry(archive, 'instance.cfg');
    if (cfg == null) return null;
    try {
      final str = utf8.decode(cfg.content as List<int>, allowMalformed: true);
      for (final line in const LineSplitter().convert(str)) {
        final t = line.trim();
        if (t.startsWith('name=')) return t.substring('name='.length);
      }
    } catch (_) {}
    return null;
  }
}
