import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'modrinth_service.dart';

/// 整合包格式。
enum ModpackFormat { modrinth, plainZip }

/// Modrinth 整合包中的一个待下载文件。
///
/// 参考 PCL-CE 的 ModModpack.InstallPackModrinth：整合包内 `files` 数组已
/// 包含完整下载信息（URL、相对路径、大小、哈希、env），可直接下载。
class ModrinthModpackFile {
  const ModrinthModpackFile({
    required this.path,
    required this.downloads,
    this.fileSize,
    this.sha1,
    required this.envClient,
    required this.envServer,
  });

  /// 相对实例根目录的路径（如 "mods/foo.jar"）。
  final String path;
  final List<String> downloads;
  final int? fileSize;
  final String? sha1;
  final String envClient;
  final String envServer;

  /// 服务端是否需要该文件：env.server 非 "unsupported" 即下载。
  /// "optional" 也一并下载（用户可稍后自行删除）。
  bool get serverRequired => envServer != 'unsupported';
}

/// 已解析的 Modrinth 整合包信息。
class ModrinthModpack {
  const ModrinthModpack({
    this.name,
    this.versionId,
    required this.dependencies,
    required this.files,
  });

  final String? name;
  final String? versionId;

  /// 依赖：minecraft / fabric-loader / forge / neo-forge / neoforge / quilt-loader。
  final Map<String, String> dependencies;
  final List<ModrinthModpackFile> files;

  /// 服务端需要下载的文件列表。
  List<ModrinthModpackFile> get serverFiles =>
      files.where((f) => f.serverRequired).toList();
}

/// 整合包解析与安装服务。
///
/// 仅支持 Modrinth 格式（modrinth.index.json）。CurseForge 格式需 CurseForge
/// API Key 获取下载链接，项目未配置故不支持。普通 zip 由调用方走原生解压。
class ModpackService {
  ModpackService._();

  /// 检测整合包格式。先尝试识别 Modrinth，否则视为普通压缩包。
  static Future<ModpackFormat> detectFormat(String archivePath) async {
    try {
      final bytes = await File(archivePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      if (_findManifestEntry(archive) != null) return ModpackFormat.modrinth;
    } catch (_) {}
    return ModpackFormat.plainZip;
  }

  /// 解析 Modrinth 整合包清单。
  static Future<ModrinthModpack> parseModrinth(String archivePath) async {
    final bytes = await File(archivePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestEntry = _findManifestEntry(archive);
    if (manifestEntry == null) {
      throw const FormatException('未找到 modrinth.index.json');
    }

    final String manifestStr;
    try {
      manifestStr = utf8.decode(
        manifestEntry.content as List<int>,
        allowMalformed: true,
      );
    } catch (e) {
      throw FormatException('解析 modrinth.index.json 失败：$e');
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(manifestStr) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('modrinth.index.json 不是合法 JSON：$e');
    }

    // 依赖。
    final depsRaw = data['dependencies'] as Map<String, dynamic>? ?? {};
    final deps = <String, String>{};
    depsRaw.forEach((k, v) => deps[k] = '$v');

    // 文件列表。
    final filesRaw = data['files'] as List<dynamic>? ?? [];
    final files = <ModrinthModpackFile>[];
    for (final item in filesRaw) {
      if (item is! Map<String, dynamic>) continue;
      final path = item['path'] as String?;
      final downloadsRaw = item['downloads'] as List<dynamic>?;
      if (path == null || downloadsRaw == null) continue;
      final downloads = downloadsRaw.map((u) => '$u').toList();
      final env = item['env'] as Map<String, dynamic>? ?? {};
      final hashes = item['hashes'] as Map<String, dynamic>? ?? {};
      files.add(
        ModrinthModpackFile(
          path: path,
          downloads: downloads,
          fileSize: item['fileSize'] as int?,
          sha1: hashes['sha1'] as String?,
          envClient: (env['client'] ?? 'required') as String,
          envServer: (env['server'] ?? 'required') as String,
        ),
      );
    }

    return ModrinthModpack(
      name: data['name'] as String?,
      versionId: data['versionId'] as String?,
      dependencies: deps,
      files: files,
    );
  }

  /// 下载整合包中服务端需要的文件到 [destDir]，保持 manifest 中的相对路径结构。
  ///
  /// [onProgress] 回调 (current, total, currentFileName)。
  /// [isCancelled] 返回 true 时中断并删除当前不完整文件。
  /// 已存在且大小匹配的文件会被跳过，便于失败重试。
  static Future<void> downloadServerFiles(
    ModrinthModpack modpack,
    Directory destDir, {
    void Function(int current, int total, String currentFile)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final serverFiles = modpack.serverFiles;
    final total = serverFiles.length;
    for (var i = 0; i < serverFiles.length; i++) {
      if (isCancelled?.call() == true) return;
      final file = serverFiles[i];
      final relPath = _safeRelativePath(file.path, destDir);
      final targetPath = p.join(destDir.path, relPath);
      final targetFile = File(targetPath);

      // 跳过已存在且大小匹配的文件。
      if (await targetFile.exists() &&
          file.fileSize != null &&
          (await targetFile.length()) == file.fileSize) {
        onProgress?.call(i + 1, total, p.basename(targetPath));
        continue;
      }

      await Directory(p.dirname(targetPath)).create(recursive: true);

      final url = file.downloads.isEmpty ? null : file.downloads.first;
      if (url == null) {
        onProgress?.call(i + 1, total, p.basename(targetPath));
        continue;
      }

      await ModrinthService.downloadFile(
        url,
        targetPath,
        isCancelled: isCancelled,
      );

      // 哈希校验（可选）。
      if (file.sha1 != null && file.sha1!.isNotEmpty) {
        final actual = await ModrinthService.computeSha1(targetPath);
        if (actual != file.sha1) {
          try {
            await targetFile.delete();
          } catch (_) {}
          throw Exception(
            '哈希校验失败：${p.basename(targetPath)}（期望 ${file.sha1}，实际 $actual）',
          );
        }
      }

      onProgress?.call(i + 1, total, p.basename(targetPath));
    }
  }

  /// 解压 Modrinth 整合包的 overrides 与 server-overrides 目录到 [destDir]。
  /// 这两个目录中的文件会平铺到实例根目录（保留其相对结构）。
  static Future<int> extractOverrides(
    String archivePath,
    Directory destDir,
  ) async {
    final bytes = await File(archivePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestEntry = _findManifestEntry(archive);
    final baseFolder = manifestEntry == null
        ? ''
        : (manifestEntry.name == 'modrinth.index.json'
              ? ''
              : manifestEntry.name.substring(
                  0,
                  manifestEntry.name.length - 'modrinth.index.json'.length,
                ));

    final overridePrefixes = [
      '${baseFolder}overrides/',
      '${baseFolder}client-overrides/',
      '${baseFolder}server-overrides/',
    ];

    var count = 0;
    for (final file in archive) {
      if (!file.isFile) continue;
      String? rel;
      for (final prefix in overridePrefixes) {
        if (file.name.startsWith(prefix) && file.name.length > prefix.length) {
          rel = file.name.substring(prefix.length);
          break;
        }
      }
      if (rel == null) continue;
      rel = _safeRelativePath(rel, destDir);
      final targetPath = p.join(destDir.path, rel);
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await File(targetPath).writeAsBytes(file.content as List<int>);
      count++;
    }
    return count;
  }

  /// 在归档中查找 modrinth.index.json 条目（优先根目录，其次任意层级）。
  static ArchiveFile? _findManifestEntry(Archive archive) {
    ArchiveFile? fallback;
    for (final f in archive) {
      if (!f.isFile) continue;
      if (f.name == 'modrinth.index.json') return f;
      if (f.name.endsWith('/modrinth.index.json')) {
        fallback ??= f;
      }
    }
    return fallback;
  }

  /// 规范化相对路径，并防止路径穿越（不允许逃逸出 [destDir]）。
  static String _safeRelativePath(String rel, Directory destDir) {
    final normalized = p.normalize(rel).replaceAll('\\', '/');
    // 禁止绝对路径与盘符前缀，禁用 .. 逃逸。
    if (p.isAbsolute(normalized) ||
        normalized.startsWith('..') ||
        normalized.contains(':')) {
      throw InvalidPathException('整合包包含非法路径：$normalized');
    }
    final resolved = p.normalize(p.join(destDir.path, normalized));
    if (!p.isWithin(destDir.path, resolved)) {
      throw const InvalidPathException('整合包路径逃逸出实例目录');
    }
    return normalized;
  }
}

/// 整合包路径非法异常。
class InvalidPathException implements Exception {
  final String message;
  const InvalidPathException(this.message);
  @override
  String toString() => message;
}
