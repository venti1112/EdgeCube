import 'dart:convert';
import 'dart:io';

/// MSL 镜像源（MSL 开服器）服务端下载 API 封装。
///
/// 文档：https://apidoc-v4.mslmc.cn/
/// 基础流程：`GET /download/server/{server}/{version}` → `{url, sha256?}`。
/// 返回的 url 为可直接下载的 jar：vanilla/paper/velocity/fabric 为可运行的
/// server.jar，forge/neoforge 为 installer.jar（需经原生安装器安装）。
///
/// 使用规范要求集成方注明「本服务由MSL开服器提供」并附官网地址，详见
/// [officialSite]，UI 侧在「网络设置」页中展示来源声明。
class MslMirror {
  MslMirror._();

  static const String baseUrl = 'https://api.mslmc.cn/v4';
  static const String officialSite = 'https://www.mslmc.cn';
  static const String _userAgent = 'EdgeCube/1.0';

  /// 应用内服务端类型 → MSL 核心名（当前一一对应）。
  static const Map<String, String> _serverNameMap = {
    'vanilla': 'vanilla',
    'paper': 'paper',
    'velocity': 'velocity',
    'fabric': 'fabric',
    'forge': 'forge',
    'neoforge': 'neoforge',
  };

  /// 获取指定核心 + 版本的镜像下载信息。
  ///
  /// [serverType] 为应用内服务端类型；[version] 对 vanilla/paper/fabric/forge
  /// 为 Minecraft 版本，对 velocity 为其自身版本，对 neoforge 为 `1.21.1` 这类
  /// MC 版本格式。不支持的类型 / 网络失败 / 镜像无此版本时返回 null，
  /// 由调用方回退官方源。
  static Future<MslDownloadInfo?> fetchDownloadInfo(
    String serverType,
    String version, {
    String build = 'latest',
  }) async {
    final mslName = _serverNameMap[serverType];
    if (mslName == null) return null;
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('$baseUrl/download/server/$mslName/$version?build=$build'),
      );
      req.headers.set('User-Agent', _userAgent);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['code'] != 200) return null;
      final data = json['data'];
      if (data is! Map<String, dynamic>) return null;
      final url = data['url'];
      if (url is! String || url.isEmpty) return null;
      return MslDownloadInfo(url: url, sha256: data['sha256'] as String?);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}

/// MSL 镜像源返回的下载信息。
class MslDownloadInfo {
  const MslDownloadInfo({required this.url, this.sha256});

  final String url;
  final String? sha256;
}
