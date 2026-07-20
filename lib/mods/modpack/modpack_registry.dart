import 'dart:io';

import 'package:archive/archive.dart';

import 'curseforge_modpack_provider.dart';
import 'mcbbs_hmcl_modpack_provider.dart';
import 'modpack_provider.dart';
import 'modrinth_modpack_provider.dart';
import 'multimc_modpack_provider.dart';

/// 整合包格式注册表：按固定顺序探测格式并解析。
///
/// 顺序敏感（借鉴 HMCL）：MCBBS 与 CurseForge 都用 manifest.json，MCBBS
/// （含 addons 键）必须先试。命中任一 provider 即返回其解析结果；全不命中
/// 回退 [ModpackFormat.plainZip]（普通压缩包，由调用方直接解压）。
///
/// CurseForge / MultiMC / MCBBS-HMCL provider 将在后续步骤登记。
class ModpackRegistry {
  ModpackRegistry._();

  /// 探测顺序。越靠前优先级越高。
  ///
  /// 顺序敏感：MCBBS 与 CurseForge 都用 manifest.json，MCBBS（含 addons 键）
  /// 必须先试；Modrinth/MultiMC 有独立签名文件，顺序不敏感。
  static const List<ModpackProvider> _providers = [
    McbbsModpackProvider(),
    CurseForgeModpackProvider(),
    ModrinthModpackProvider(),
    HmclModpackProvider(),
    MultiMcModpackProvider(),
  ];

  /// 解码归档并探测格式，解析为中立整合包。无匹配格式时返回 null
  /// （调用方据此走普通 zip 解压）。
  static Future<ParsedModpack?> detectAndParse(String archivePath) async {
    final bytes = await File(archivePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final provider in _providers) {
      final baseFolder = _detectBaseFolder(archive, provider);
      if (baseFolder == null) continue;
      return provider.parse(archivePath, archive, baseFolder: baseFolder);
    }
    return null;
  }

  /// 探测某 provider 的包裹前缀。matches 命中返回 baseFolder（可能为空串），
  /// 不命中返回 null。当前 provider 自行在 matches 内判断签名，故这里
  /// 统一传空串探测，由 provider 内部推导真实 baseFolder 后写入结果。
  static String? _detectBaseFolder(Archive archive, ModpackProvider provider) {
    if (provider.matches(archive, baseFolder: '')) return '';
    return null;
  }
}
