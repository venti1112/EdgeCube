import '../config/network_store.dart';
import 'app_secrets.dart';

/// 模组 / 整合包下载的镜像源与 API Key 注入层。
///
/// 仿 [MslMirror]（服务端 jar 镜像）的写法，但服务于模组内容平台
/// （CurseForge / Modrinth）。设计要点：
///
/// - **一个开关统管**：复用 [NetworkStore.loadUseMirror]，与「服务端下载镜像」
///   共用同一个用户开关（符合「像 MC 服务端下载镜像那样可手动开关」的诉求）。
/// - **镜像开启时**：API 与 CDN 请求改写到镜像 host（镜像侧持有 CF Key，
///   客户端无需 Key），同时加速国内下载。
/// - **镜像关闭时**：直连官方 API，CF 请求附带编译期注入的 [AppSecrets.curseForgeApiKey]。
///
/// CurseForge 是否可用：`AppSecrets.hasCurseForgeKey || 已开启镜像`。
class ModMirror {
  ModMirror._();

  /// 镜像服务根地址（PCL-CE 同款 mcimirror）。
  static const String _mirrorBase = 'https://mod.mcimirror.top';

  static const String _curseForgeApiHost = 'api.curseforge.com';
  static const String _modrinthApiHost = 'api.modrinth.com';
  static const String _forgeCdnHost = 'edge.forgecdn.net';
  static const String _modrinthCdnHost = 'cdn.modrinth.com';

  /// 当前是否启用镜像源（与服务端下载共用开关）。
  static Future<bool> isEnabled() => NetworkStore.loadUseMirror();

  /// CurseForge 是否可用：有编译期 Key，或已开启镜像。
  static Future<bool> isCurseForgeAvailable() async {
    if (AppSecrets.hasCurseForgeKey) return true;
    return isEnabled();
  }

  /// 改写 API 请求 URI。镜像开启时把官方 API host 换成镜像路径；
  /// 关闭时原样返回。
  static Future<Uri> rewriteApi(Uri uri) async {
    if (!await isEnabled()) return uri;
    return _rewriteApiSync(uri);
  }

  /// 同步版 API 改写（调用方已确定镜像开启时使用）。
  static Uri _rewriteApiSync(Uri uri) {
    switch (uri.host) {
      case _curseForgeApiHost:
        return uri.replace(
          scheme: 'https',
          host: 'mod.mcimirror.top',
          path: '/curseforge${uri.path}',
        );
      case _modrinthApiHost:
        return uri.replace(
          scheme: 'https',
          host: 'mod.mcimirror.top',
          path: '/modrinth${uri.path}',
        );
      default:
        return uri;
    }
  }

  /// 为单个下载 URL 生成候选列表：镜像开启时返回 `[镜像URL, 官方URL]`，
  /// 供 [DownloadEngine.downloadToFileMultiSource] 顺序回退；关闭时仅
  /// 返回官方 URL。空/非法输入原样透传。
  static Future<List<String>> downloadCandidates(String url) async {
    if (url.isEmpty) return [url];
    if (!await isEnabled()) return [url];
    final mirrored = _rewriteDownloadUrl(url);
    if (mirrored == null || mirrored == url) return [url];
    // 镜像优先，官方兜底。
    return [mirrored, url];
  }

  /// 批量：对每个官方下载 URL 生成候选并去重合并（保持顺序：所有镜像在前、
  /// 官方在后由各自 candidates 决定）。用于整合包多文件场景。
  static Future<List<String>> expandDownloads(List<String> urls) async {
    final enabled = await isEnabled();
    if (!enabled) return urls;
    final result = <String>[];
    for (final u in urls) {
      final mirrored = _rewriteDownloadUrl(u);
      if (mirrored != null && mirrored != u) result.add(mirrored);
      result.add(u);
    }
    return result;
  }

  /// 把官方 CDN host 改写为镜像 CDN。无法识别的 host 返回 null。
  static String? _rewriteDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    switch (uri.host) {
      case _forgeCdnHost:
        return uri
            .replace(host: 'mod.mcimirror.top', path: '/files${uri.path}')
            .toString();
      case _modrinthCdnHost:
        return uri
            .replace(host: 'mod.mcimirror.top', path: '/data${uri.path}')
            .toString();
      default:
        return null;
    }
  }

  /// CurseForge 请求头：镜像关闭且有编译期 Key 时附带 `X-API-KEY`；
  /// 镜像开启时不附（请求走镜像 host，Key 由镜像侧持有）。
  static Future<Map<String, String>> curseForgeHeaders() async {
    if (await isEnabled()) return const {};
    if (AppSecrets.hasCurseForgeKey) {
      return {'X-API-KEY': AppSecrets.curseForgeApiKey};
    }
    return const {};
  }

  /// 镜像服务根地址（供 UI 展示或调试）。
  static String get mirrorBase => _mirrorBase;
}
