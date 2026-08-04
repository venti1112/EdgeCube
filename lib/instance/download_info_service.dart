import 'dart:convert';
import 'dart:io';

import '../online/cloud_headers.dart';
import 'download_info.dart';

class DownloadInfoService {
  DownloadInfoService._();

  static Future<DownloadInfo> fetchVelocityDownloadInfo(String version) async {
    final client = HttpClient();
    try {
      final buildReq = await client.getUrl(
        Uri.parse(
          'https://fill.papermc.io/v3/projects/velocity/versions/$version/builds/latest',
        ),
      );
      buildReq.headers.set('User-Agent', 'EdgeCube/1.0');
      final buildRes = await buildReq.close();
      final buildBody = await buildRes.transform(utf8.decoder).join();
      final buildJson = jsonDecode(buildBody) as Map<String, dynamic>;
      final serverDefault =
          (buildJson['downloads'] as Map<String, dynamic>)['server:default']
              as Map<String, dynamic>;
      final sha256 =
          (serverDefault['checksums'] as Map<String, dynamic>)['sha256']
              as String;
      final downloadUrl = serverDefault['url'] as String;
      return DownloadInfo(url: downloadUrl, sha256: sha256);
    } finally {
      client.close();
    }
  }

  static Future<DownloadInfo> fetchPaperDownloadInfo(String version) async {
    final client = HttpClient();
    try {
      final buildReq = await client.getUrl(
        Uri.parse(
          'https://fill.papermc.io/v3/projects/paper/versions/$version/builds/latest',
        ),
      );
      buildReq.headers.set('User-Agent', 'EdgeCube/1.0');
      final buildRes = await buildReq.close();
      final buildBody = await buildRes.transform(utf8.decoder).join();
      final buildJson = jsonDecode(buildBody) as Map<String, dynamic>;
      final serverDefault =
          (buildJson['downloads'] as Map<String, dynamic>)['server:default']
              as Map<String, dynamic>;
      final sha256 =
          (serverDefault['checksums'] as Map<String, dynamic>)['sha256']
              as String;
      final downloadUrl = serverDefault['url'] as String;
      return DownloadInfo(url: downloadUrl, sha256: sha256);
    } finally {
      client.close();
    }
  }

  static Future<DownloadInfo> fetchSpigotDownloadInfo(String version) async {
    return DownloadInfo(
      url: 'https://cdn.getbukkit.org/spigot/spigot-$version.jar',
    );
  }

  static Future<DownloadInfo> fetchCraftBukkitDownloadInfo(
    String version,
  ) async {
    return DownloadInfo(
      url: 'https://cdn.getbukkit.org/craftbukkit/craftbukkit-$version.jar',
    );
  }

  static Future<DownloadInfo> fetchPurpurDownloadInfo(String version) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.purpurmc.org/v2/purpur/$version'),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final builds = json['builds'] as Map<String, dynamic>;
      final latest = builds['latest'] as String;
      final downloadUrl =
          'https://api.purpurmc.org/v2/purpur/$version/$latest/download';
      return DownloadInfo(url: downloadUrl);
    } finally {
      client.close();
    }
  }

  static Future<DownloadInfo> fetchLeafDownloadInfo(String version) async {
    final client = HttpClient();
    try {
      final verReq = await client.getUrl(
        Uri.parse('https://api.leafmc.one/v2/projects/leaf/versions/$version'),
      );
      verReq.headers.set('User-Agent', 'EdgeCube/1.0');
      final verRes = await verReq.close();
      final verBody = await verRes.transform(utf8.decoder).join();
      final verJson = jsonDecode(verBody) as Map<String, dynamic>;
      final builds = (verJson['builds'] as List<dynamic>)
          .map((b) => b as int)
          .toList();
      builds.sort();
      final latestBuild = builds.last;

      final buildReq = await client.getUrl(
        Uri.parse(
          'https://api.leafmc.one/v2/projects/leaf/versions/$version/builds/$latestBuild',
        ),
      );
      buildReq.headers.set('User-Agent', 'EdgeCube/1.0');
      final buildRes = await buildReq.close();
      final buildBody = await buildRes.transform(utf8.decoder).join();
      final buildJson = jsonDecode(buildBody) as Map<String, dynamic>;
      final primary =
          (buildJson['downloads'] as Map<String, dynamic>)['primary']
              as Map<String, dynamic>;
      final name = primary['name'] as String;
      final sha256 = primary['sha256'] as String?;
      final downloadUrl =
          'https://api.leafmc.one/v2/projects/leaf/versions/$version/builds/$latestBuild/downloads/$name';
      return DownloadInfo(url: downloadUrl, sha256: sha256);
    } finally {
      client.close();
    }
  }

  static Future<DownloadInfo> fetchLeavesDownloadInfo(String version) async {
    final client = HttpClient();
    try {
      final buildReq = await client.getUrl(
        Uri.parse(
          'https://api.leavesmc.org/v2/projects/leaves/versions/$version/builds/latest',
        ),
      );
      buildReq.headers.set('User-Agent', 'EdgeCube/1.0');
      final buildRes = await buildReq.close();
      final buildBody = await buildRes.transform(utf8.decoder).join();
      final buildJson = jsonDecode(buildBody) as Map<String, dynamic>;
      final build = buildJson['build'] as int;
      final application =
          (buildJson['downloads'] as Map<String, dynamic>)['application']
              as Map<String, dynamic>;
      final name = application['name'] as String;
      final sha256 = application['sha256'] as String?;
      final downloadUrl =
          'https://api.leavesmc.org/v2/projects/leaves/versions/$version/builds/$build/downloads/$name';
      return DownloadInfo(url: downloadUrl, sha256: sha256);
    } finally {
      client.close();
    }
  }

  static Future<DownloadInfo> fetchBungeeCordDownloadInfo() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/api/json',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final buildNumber = json['number'] as int;
      final downloadUrl =
          'https://ci.md-5.net/job/BungeeCord/$buildNumber/artifact/bootstrap/target/BungeeCord.jar';
      return DownloadInfo(url: downloadUrl);
    } finally {
      client.close();
    }
  }

  static Future<DownloadInfo> fetchPowernukkitxDownloadInfo(
    String version,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/PowerNukkitX/PowerNukkitX/releases/tags/$version',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final assets = json['assets'] as List<dynamic>;
      String? downloadUrl;
      for (final asset in assets) {
        final name = (asset as Map<String, dynamic>)['name'] as String;
        if (name.endsWith('.jar')) {
          downloadUrl = asset['browser_download_url'] as String;
          if (name.toLowerCase().contains('shaded')) break;
        }
      }
      if (downloadUrl == null) {
        throw Exception('No JAR found in release $version');
      }
      return DownloadInfo(url: downloadUrl);
    } finally {
      client.close();
    }
  }

  static Future<DownloadInfo> fetchPocketmineDownloadInfo(
    String version,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://raw.githubusercontent.com/pmmp/update.pmmp.io/master/channels/$version.json',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final downloadUrl = json['download_url'] as String?;
      if (downloadUrl == null) {
        throw Exception('No download_url in channel $version');
      }
      return DownloadInfo(url: downloadUrl);
    } finally {
      client.close();
    }
  }

  static Future<DownloadInfo> fetchAllayDownloadInfo(String version) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/AllayMC/Allay/releases/tags/$version',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final assets = json['assets'] as List<dynamic>;
      if (assets.isEmpty) {
        throw Exception('No asset found in release $version');
      }
      Map<String, dynamic>? asset;
      for (final a in assets) {
        final name = (a as Map<String, dynamic>)['name'] as String? ?? '';
        if (name.startsWith('allay')) {
          asset = a;
          break;
        }
      }
      asset ??= assets.first as Map<String, dynamic>;
      final downloadUrl = asset['browser_download_url'] as String;
      final digest = asset['digest'] as String?;
      final sha256 = digest != null && digest.startsWith('sha256:')
          ? digest.substring(7)
          : null;
      return DownloadInfo(url: downloadUrl, sha256: sha256);
    } finally {
      client.close();
    }
  }

  /// 获取 SurvivalcraftNet 联机版指定 tag 的服务端下载信息。
  ///
  /// 数据源：`https://gitee.com/api/v5/repos/SC-SPM/SurvivalcraftNet/releases/tags/{tag}`
  /// 从 release assets 中筛选服务端文件（文件名含「服务端」），优先选 Linux
  /// 版本（可通过 proot 运行），其次选未标明平台的通用包，最后回退到首个服务端文件。
  /// 无服务端文件时抛出异常。
  static Future<DownloadInfo> fetchSurvivalcraftDownloadInfo(String tag) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://gitee.com/api/v5/repos/SC-SPM/SurvivalcraftNet/releases/tags/$tag',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final assets = (json['assets'] as List<dynamic>?) ?? [];
      if (assets.isEmpty) {
        throw Exception('No asset found in release $tag');
      }

      // 筛选服务端文件：文件名含「服务端」（中文名），回退匹配「server」（英文名）。
      final serverAssets = assets.where((a) {
        final name = (a as Map<String, dynamic>)['name'] as String? ?? '';
        final lower = name.toLowerCase();
        return name.contains('服务端') || lower.contains('server');
      }).toList();

      if (serverAssets.isEmpty) {
        throw Exception('No server asset found in release $tag');
      }

      // 优先级：Linux 版 > 未标明 Windows 的通用包 > 首个服务端文件。
      Map<String, dynamic>? linuxAsset;
      Map<String, dynamic>? nonWindowsAsset;
      for (final a in serverAssets) {
        final name = (a as Map<String, dynamic>)['name'] as String? ?? '';
        final lower = name.toLowerCase();
        if (lower.contains('linux')) {
          linuxAsset = a;
          break;
        }
        if (!lower.contains('windows') && nonWindowsAsset == null) {
          nonWindowsAsset = a;
        }
      }
      final asset = linuxAsset ?? nonWindowsAsset ?? serverAssets.first;
      final downloadUrl = asset['browser_download_url'] as String;
      return DownloadInfo(url: downloadUrl);
    } finally {
      client.close();
    }
  }
}
