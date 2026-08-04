import 'dart:convert';

import 'package:archive/archive.dart';

import '../../i18n/i18n_service.dart';
import '../../net/mod_mirror.dart';
import '../sources/curseforge_mod_source.dart';
import 'modpack_provider.dart';
import 'modpack_utils.dart';

/// CurseForge 整合包（manifest.json，无 addons 键）解析器。
///
/// CF 整合包只存 projectID/fileID，需经 [CurseForgeModSource.resolveFiles]
/// 批量解析出下载链接（含 CDN 回退）。因此**依赖 CF 可用**（编译期 Key 或
/// 已开镜像）；不可用时 [parse] 抛可读错误。
///
/// 注意：与 MCBBS 同用 manifest.json，靠**无 addons 键**区分——注册表中
/// MCBBS 必须排在本 provider 之前。
class CurseForgeModpackProvider extends ModpackProvider {
  const CurseForgeModpackProvider();

  static const _manifest = 'manifest.json';
  static const _cf = CurseForgeModSource();

  @override
  ModpackFormat get format => ModpackFormat.curseforge;

  @override
  bool matches(Archive archive, {required String baseFolder}) {
    final entry = ModpackUtils.findEntry(archive, _manifest);
    if (entry == null) return false;
    try {
      final str = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final data = jsonDecode(str) as Map<String, dynamic>;
      // CF：manifestType == 'minecraftModpack' 且无 addons 键（MCBBS 才有）。
      if (data.containsKey('addons')) return false;
      return data['manifestType'] == 'minecraftModpack' ||
          data.containsKey('minecraft');
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
    if (!await ModMirror.isCurseForgeAvailable()) {
      throw ModpackParseException(tr('modpack.curseForgeUnavailable'));
    }

    final entry = ModpackUtils.findEntry(archive, _manifest);
    if (entry == null) {
      throw ModpackParseException(tr('modpack.manifestNotFound'));
    }
    final Map<String, dynamic> data;
    try {
      final str = utf8.decode(entry.content as List<int>, allowMalformed: true);
      data = jsonDecode(str) as Map<String, dynamic>;
    } catch (e) {
      throw ModpackParseException(
        tr('modpack.parseManifestFailed', {'error': '$e'}),
      );
    }

    // 依赖：minecraft.version + modLoaders[].id（按前缀分流），归一到 Modrinth 键名。
    final deps = <String, String>{};
    final minecraft = data['minecraft'] as Map<String, dynamic>?;
    final mcVersion = minecraft?['version'] as String?;
    if (mcVersion != null) deps['minecraft'] = mcVersion;
    final loaders = (minecraft?['modLoaders'] as List? ?? [])
        .whereType<Map<String, dynamic>>();
    for (final l in loaders) {
      final id =
          l['id']
              as String?; // 如 "forge-47.2.0" / "neoforge-21.1.5" / "fabric-0.15.0"
      if (id == null) continue;
      final dash = id.indexOf('-');
      if (dash < 0) continue;
      final loaderName = id.substring(0, dash);
      final loaderVer = id.substring(dash + 1);
      switch (loaderName) {
        case 'forge':
          deps['forge'] = loaderVer;
        case 'neoforge':
          deps['neoforge'] = loaderVer;
        case 'fabric':
          deps['fabric-loader'] = loaderVer;
        case 'quilt':
          deps['quilt-loader'] = loaderVer;
      }
    }

    // 文件：收集 fileID → 批量解析下载链接。
    final filesRaw = (data['files'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final fileIds = filesRaw.map((f) => f['fileID']).whereType<int>().toList();
    final resolved = await _cf.resolveFiles(fileIds);

    final files = <ModpackFileEntry>[];
    for (final f in filesRaw) {
      final fileId = f['fileID'] as int?;
      if (fileId == null) continue;
      final info = resolved[fileId];
      if (info == null || info.filename.isEmpty || info.downloads.isEmpty) {
        continue; // 无法解析下载链接的文件跳过（作者禁用分发且无 CDN 回退）。
      }
      final required = f['required'] as bool? ?? true;
      // CF 整合包的 mod 文件默认落到 mods/。
      final urls = await ModMirror.expandDownloads(info.downloads);
      files.add(
        ModpackFileEntry(
          path: 'mods/${info.filename}',
          downloads: urls,
          fileSize: info.size,
          sha1: info.sha1,
          serverRequired: required,
        ),
      );
    }

    // overrides 目录名可能自定义（manifest.overrides），默认 "overrides"。
    final overrideName = data['overrides'] as String? ?? 'overrides';
    return ParsedModpack(
      format: ModpackFormat.curseforge,
      name: data['name'] as String?,
      versionId: data['version'] as String?,
      dependencies: deps,
      files: files,
      overridePrefixes: ['$baseFolder$overrideName/'],
    );
  }
}
