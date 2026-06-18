import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用配置文件的基础读写工具。
///
/// 全局配置（主题、在线服务、网络映射）各自存为文档目录 `config/` 下的独立
/// JSON 文件；本模块只负责定位目录、读取与原子写入，不关心具体配置内容。
class ConfigStore {
  ConfigStore._();

  /// 全局配置目录 `<documents>/config/`，不存在时自动创建。
  static Future<Directory> configDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'config'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 读取 `config/<fileName>` 并解析为 Map；缺失或损坏时返回空 Map。
  static Future<Map<String, dynamic>> readConfig(String fileName) async {
    final dir = await configDir();
    return readJsonFile(File(p.join(dir.path, fileName)));
  }

  /// 将 [data] 写入 `config/<fileName>`。
  static Future<void> writeConfig(
    String fileName,
    Map<String, dynamic> data,
  ) async {
    final dir = await configDir();
    await writeJsonFile(File(p.join(dir.path, fileName)), data);
  }

  /// 读取任意 JSON 文件为 Map；文件缺失或内容损坏均返回空 Map，
  /// 调用方据此回退到默认值。
  static Future<Map<String, dynamic>> readJsonFile(File file) async {
    if (!await file.exists()) return {};
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  /// 原子写入 JSON 文件：先写临时文件再 rename，避免写入中途崩溃导致损坏。
  static Future<void> writeJsonFile(
    File file,
    Map<String, dynamic> data,
  ) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(file.path);
  }
}
