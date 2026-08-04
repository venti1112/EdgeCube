import 'dart:convert';

import 'package:archive/archive.dart';

import '../../i18n/i18n_service.dart';
import 'modpack_provider.dart';
import 'modpack_utils.dart';

/// MCBBS 整合包解析器（`mcbbs.packmeta`，或带 addons 键的 `manifest.json`）。
///
/// addons[] 形如 `{id, version}`，id 为 game/forge/neoforge/fabric/quilt。
/// mods 内容通过 overrides 展开（MCBBS 不在清单里列 URL 下载文件）。
///
/// 必须排在 [CurseForgeModpackProvider] 之前——两者都可能用 manifest.json，
/// MCBBS 以 addons 键区分。
class McbbsModpackProvider extends ModpackProvider {
  const McbbsModpackProvider();

  static const _packmeta = 'mcbbs.packmeta';
  static const _manifest = 'manifest.json';

  @override
  ModpackFormat get format => ModpackFormat.mcbbs;

  @override
  bool matches(Archive archive, {required String baseFolder}) {
    if (ModpackUtils.hasEntry(archive, _packmeta)) return true;
    // 带 addons 键的 manifest.json 视为 MCBBS。
    final entry = ModpackUtils.findEntry(archive, _manifest);
    if (entry == null) return false;
    try {
      final str = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final data = jsonDecode(str) as Map<String, dynamic>;
      return data.containsKey('addons');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ParsedModpack> parse(
    String archivePath,
    Archive archive, {
    required String baseFolder,
  }) async {
    final entry =
        ModpackUtils.findEntry(archive, _packmeta) ??
        ModpackUtils.findEntry(archive, _manifest);
    if (entry == null) {
      throw ModpackParseException(tr('modpack.manifestNotFound'));
    }
    final fileName = entry.name.endsWith(_packmeta) ? _packmeta : _manifest;
    final base = ModpackUtils.baseFolderOf(entry, fileName);

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
    for (final a
        in (data['addons'] as List? ?? []).whereType<Map<String, dynamic>>()) {
      final id = a['id'] as String?;
      final version = a['version'] as String?;
      if (id == null || version == null) continue;
      switch (id) {
        case 'game':
          deps['minecraft'] = version;
        case 'forge':
          deps['forge'] = version;
        case 'neoforge':
          deps['neoforge'] = version;
        case 'fabric':
          deps['fabric-loader'] = version;
        case 'quilt':
          deps['quilt-loader'] = version;
      }
    }

    return ParsedModpack(
      format: ModpackFormat.mcbbs,
      name: data['name'] as String?,
      versionId: data['version'] as String?,
      dependencies: deps,
      files: const [],
      overridePrefixes: ['${base}overrides/'],
    );
  }
}

/// HMCL 整合包解析器（`modpack.json`）。
///
/// gameVersion 为 MC 版本；内容在 `minecraft/` 子目录作 overrides 平铺。
/// 加载器信息在 HMCL 格式中随 minecraft/ 内的 version json 走，此处仅取 MC 版本，
/// 服务端 jar 下载回退 Vanilla（多数 HMCL 包 mod 已在 overrides 内）。
class HmclModpackProvider extends ModpackProvider {
  const HmclModpackProvider();

  static const _manifest = 'modpack.json';

  @override
  ModpackFormat get format => ModpackFormat.hmcl;

  @override
  bool matches(Archive archive, {required String baseFolder}) {
    final entry = ModpackUtils.findEntry(archive, _manifest);
    if (entry == null) return false;
    try {
      final str = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final data = jsonDecode(str) as Map<String, dynamic>;
      // HMCL 的 modpack.json 有 gameVersion；避免误吞其它同名文件。
      return data.containsKey('gameVersion') || data.containsKey('name');
    } catch (_) {
      return false;
    }
  }

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
    final gameVersion = data['gameVersion'] as String?;
    if (gameVersion != null) deps['minecraft'] = gameVersion;

    return ParsedModpack(
      format: ModpackFormat.hmcl,
      name: data['name'] as String?,
      versionId: data['version'] as String?,
      dependencies: deps,
      files: const [],
      overridePrefixes: ['${base}minecraft/', '${base}overrides/'],
    );
  }
}
