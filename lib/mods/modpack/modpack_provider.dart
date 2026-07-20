import 'package:archive/archive.dart';

/// 整合包格式。plainZip 为无清单的普通压缩包（回退直接解压）。
enum ModpackFormat { modrinth, curseforge, multimc, mcbbs, hmcl, plainZip }

/// 整合包中的一个待下载文件（中立）。
///
/// [downloads] 为有序候选 URL（镜像在前、官方兜底）；CurseForge 等只存
/// projectID/fileID 的格式需先解析出下载链接再填充此列表。
class ModpackFileEntry {
  const ModpackFileEntry({
    required this.path,
    required this.downloads,
    this.fileSize,
    this.sha1,
    this.serverRequired = true,
  });

  /// 相对实例根目录的路径（如 "mods/foo.jar"）。
  final String path;
  final List<String> downloads;
  final int? fileSize;
  final String? sha1;

  /// 服务端是否需要该文件。客户端专属文件为 false，下载时跳过。
  final bool serverRequired;
}

/// 已解析的整合包信息（中立）。
class ParsedModpack {
  const ParsedModpack({
    required this.format,
    this.name,
    this.versionId,
    required this.dependencies,
    required this.files,
    this.overridePrefixes = const [],
  });

  final ModpackFormat format;
  final String? name;
  final String? versionId;

  /// 依赖：minecraft / fabric-loader / forge / neo-forge / neoforge / quilt-loader。
  /// 统一为 Modrinth 风格键名，供 create_modpack_page 的服务端 jar 下载逻辑复用。
  final Map<String, String> dependencies;

  final List<ModpackFileEntry> files;

  /// 需要展开到实例根目录的归档内前缀（如 "overrides/"、"server-overrides/"）。
  /// 各格式在解析时给出，[extractOverrides] 据此平铺文件。
  final List<String> overridePrefixes;

  /// 服务端需要下载的文件。
  List<ModpackFileEntry> get serverFiles =>
      files.where((f) => f.serverRequired).toList();
}

/// 整合包格式解析器。每种格式实现此接口，探测签名文件并解析为中立模型。
///
/// 借鉴 HMCL 的 ModpackProvider 有序探测：注册表按固定顺序调用 [matches]，
/// 命中即用其 [parse]。因 MCBBS 与 CurseForge 都用 manifest.json，顺序敏感。
abstract class ModpackProvider {
  const ModpackProvider();

  /// 格式标识。
  ModpackFormat get format;

  /// 归档是否匹配本格式。[baseFolder] 为归档内包裹前缀（支持单层子目录包裹），
  /// 空串表示根目录。
  bool matches(Archive archive, {required String baseFolder});

  /// 解析归档为中立整合包模型。[archivePath] 供需要二次读取的场景，
  /// [archive] 为已解码归档，[baseFolder] 同 [matches]。
  Future<ParsedModpack> parse(
    String archivePath,
    Archive archive, {
    required String baseFolder,
  });
}
