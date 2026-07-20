import 'dart:convert';

import 'package:archive/archive.dart';

import '../../i18n/i18n_service.dart';
import 'modpack_provider.dart';
import 'modpack_utils.dart';

/// Modrinth 整合包（modrinth.index.json）解析器。
///
/// 整合包内 `files` 数组已含完整下载信息（URL、相对路径、大小、哈希、env），
/// 可直接下载，无需二次解析。
class ModrinthModpackProvider extends ModpackProvider {
  const ModrinthModpackProvider();

  static const _manifest = 'modrinth.index.json';

  @override
  ModpackFormat get format => ModpackFormat.modrinth;

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
    // 以签名条目实际位置推导 baseFolder（支持子目录包裹的 .mrpack）。
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

    // 依赖。
    final depsRaw = data['dependencies'] as Map<String, dynamic>? ?? {};
    final deps = <String, String>{};
    depsRaw.forEach((k, v) => deps[k] = '$v');

    // 文件列表。
    final filesRaw = data['files'] as List<dynamic>? ?? [];
    final files = <ModpackFileEntry>[];
    for (final item in filesRaw) {
      if (item is! Map<String, dynamic>) continue;
      final path = item['path'] as String?;
      final downloadsRaw = item['downloads'] as List<dynamic>?;
      if (path == null || downloadsRaw == null) continue;
      final env = item['env'] as Map<String, dynamic>? ?? {};
      final hashes = item['hashes'] as Map<String, dynamic>? ?? {};
      final envServer = (env['server'] ?? 'required') as String;
      files.add(
        ModpackFileEntry(
          path: path,
          downloads: downloadsRaw.map((u) => '$u').toList(),
          fileSize: item['fileSize'] as int?,
          sha1: hashes['sha1'] as String?,
          // env.server 非 "unsupported" 即下载（"optional" 也下，用户可删）。
          serverRequired: envServer != 'unsupported',
        ),
      );
    }

    return ParsedModpack(
      format: ModpackFormat.modrinth,
      name: data['name'] as String?,
      versionId: data['versionId'] as String?,
      dependencies: deps,
      files: files,
      overridePrefixes: [
        '${base}overrides/',
        '${base}client-overrides/',
        '${base}server-overrides/',
      ],
    );
  }
}
