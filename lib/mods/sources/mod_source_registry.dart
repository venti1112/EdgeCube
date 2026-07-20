import 'curseforge_mod_source.dart';
import 'hangar_mod_source.dart';
import 'mod_source.dart';
import 'modrinth_mod_source.dart';
import 'spiget_mod_source.dart';

/// 下载源注册表：按项目类型返回可用平台列表。
///
/// 新增平台只需在此登记，UI（下载页平台切换）与整合包解析都从这里取源，
/// 无需硬编码具体平台。CurseForge 等需异步判断可用性的平台，通过
/// [availableSources] 过滤（无 Key 且未开镜像时剔除）。
///
/// 注意：PMMP（PocketMine）插件仍走既有 PoggitDownloadPage，不并入本注册表。
class ModSourceRegistry {
  ModSourceRegistry._();

  static const _modrinth = ModrinthModSource();
  static const _curseforge = CurseForgeModSource();
  static const _hangar = HangarModSource();
  static const _spiget = SpigetModSource();

  /// 某项目类型下登记的全部平台（未按可用性过滤）。
  ///
  /// 顺序即 UI 中的展示顺序，Modrinth 作为默认源置首位。
  /// - 模组：Modrinth + CurseForge
  /// - 插件：Modrinth + Hangar + SpigotMC
  static List<ModSource> sourcesFor(String projectType) {
    return switch (projectType) {
      'plugin' => const [_modrinth, _hangar, _spiget],
      _ => const [_modrinth, _curseforge],
    };
  }

  /// 某项目类型下当前可用的平台（已按 [ModSource.isAvailable] 过滤）。
  static Future<List<ModSource>> availableSources(String projectType) async {
    final all = sourcesFor(projectType);
    final result = <ModSource>[];
    for (final s in all) {
      if (await s.isAvailable) result.add(s);
    }
    return result;
  }

  /// 默认源（列表首个，恒为 Modrinth）。
  static ModSource defaultSource(String projectType) =>
      sourcesFor(projectType).first;
}
