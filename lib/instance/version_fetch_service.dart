import 'dart:convert';
import 'dart:io';

import '../online/cloud_headers.dart';

class VersionFetchService {
  VersionFetchService._();

  static Future<List<String>> fetchPaperVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://fill.papermc.io/v3/projects/paper'),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as Map<String, dynamic>;
      final result = <String>[];
      for (final group in versions.keys) {
        final groupVersions = versions[group] as List<dynamic>;
        for (final v in groupVersions) {
          final lower = (v as String).toLowerCase();
          if (!lower.contains('rc') && !lower.contains('pre')) {
            result.add(v);
          }
        }
      }
      return result;
    } finally {
      client.close();
    }
  }

  static Future<List<String>> fetchSpigotVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://getbukkit.org/download/spigot'),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final versionRegex = RegExp(
        r'<h4>Version</h4>\s*<h2>([\d.]+)</h2>',
      );
      return versionRegex.allMatches(body).map((m) => m.group(1)!).toList();
    } finally {
      client.close();
    }
  }

  static Future<List<String>> fetchCraftBukkitVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://getbukkit.org/download/craftbukkit'),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final versionRegex = RegExp(
        r'<h4>Version</h4>\s*<h2>([\d.]+)</h2>',
      );
      return versionRegex.allMatches(body).map((m) => m.group(1)!).toList();
    } finally {
      client.close();
    }
  }

  static Future<List<String>> fetchPurpurVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.purpurmc.org/v2/purpur'),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as List<dynamic>;
      return versions
          .where((v) {
            final lower = (v as String).toLowerCase();
            return !lower.contains('rc') && !lower.contains('pre');
          })
          .map<String>((v) => v as String)
          .toList()
          .reversed
          .toList();
    } finally {
      client.close();
    }
  }

  static Future<List<String>> fetchLeafVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.leafmc.one/v2/projects/leaf'),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as List<dynamic>;
      return versions.map<String>((v) => v as String).toList().reversed.toList();
    } finally {
      client.close();
    }
  }

  static Future<List<String>> fetchLeavesVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.leavesmc.org/v2/projects/leaves'),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as List<dynamic>;
      return versions
          .where((v) {
            final lower = (v as String).toLowerCase();
            return !lower.contains('rc') && !lower.contains('pre');
          })
          .map<String>((v) => v as String)
          .toList()
          .reversed
          .toList();
    } finally {
      client.close();
    }
  }

  static Future<List<String>> fetchVelocityVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://fill.papermc.io/v3/projects/velocity'),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as Map<String, dynamic>;
      final result = <String>[];
      for (final group in versions.keys) {
        final groupVersions = versions[group] as List<dynamic>;
        for (final v in groupVersions) {
          final lower = (v as String).toLowerCase();
          if (!lower.contains('rc') && !lower.contains('pre')) {
            result.add(v);
          }
        }
      }
      return result;
    } finally {
      client.close();
    }
  }

  static Future<List<String>> fetchAllayVersions() async {
    final client = HttpClient();
    try {
      final releasesFuture = _fetchAllayReleases(client);
      final nightlyFuture = _fetchAllayReleaseByTag(client, 'nightly');

      final releases = await releasesFuture;
      final nightly = await nightlyFuture;

      final versions = <String>[];
      if (nightly != null) {
        versions.add('nightly');
      }
      for (final r in releases) {
        final tag = r['tag_name'] as String?;
        if (tag != null && tag != 'nightly') {
          versions.add(tag);
        }
      }
      return versions;
    } finally {
      client.close();
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchAllayReleases(
    HttpClient client,
  ) async {
    final req = await client.getUrl(
      Uri.parse('https://api.github.com/repos/AllayMC/Allay/releases'),
    );
    req.headers.set('User-Agent', await CloudHeaders.userAgent);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as List<dynamic>;
    return json.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>?> _fetchAllayReleaseByTag(
    HttpClient client,
    String tag,
  ) async {
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/AllayMC/Allay/releases/tags/$tag',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> fetchFabricMcVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://meta.fabricmc.net/v2/versions/game'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;
      return json
          .where((v) => v['stable'] == true)
          .map<String>((v) => v['version'] as String)
          .toList();
    } finally {
      client.close();
    }
  }

  static Future<List<String>> fetchFabricLoaderVersions(
    String mcVersion,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://meta.fabricmc.net/v2/versions/loader/$mcVersion',
        ),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;
      return json
          .map<String>(
            (v) =>
                (v['loader'] as Map<String, dynamic>)['version'] as String,
          )
          .toList();
    } finally {
      client.close();
    }
  }

  /// 解析 Forge Maven 元数据 XML，返回 {mcVersion: [forgeVersion...]}。
  /// 版本格式为 "{mcVersion}-{forgeVersion}"。MC 版本段本身不含 "-"，
  /// 而部分老版本的 Forge 段带分支后缀（如 "10.13.2.1300-1.7.10"、
  /// "12.18.0.1981-1.10.0"），因此必须按第一个 "-" 分割，
  /// 否则后缀会被误当成独立的 MC 版本。
  static Future<Map<String, List<String>>> fetchAllForgeVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml',
        ),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      final versionPattern = RegExp(r'<version>([^<]+)</version>');
      final matches = versionPattern.allMatches(body);

      final map = <String, List<String>>{};
      for (final m in matches) {
        final full = m.group(1)!;
        final firstDash = full.indexOf('-');
        if (firstDash < 0) continue;
        final mcVersion = full.substring(0, firstDash);
        final forgeVersion = full.substring(firstDash + 1);
        map.putIfAbsent(mcVersion, () => []).add(forgeVersion);
      }

      final sortedKeys = map.keys.toList()
        ..sort((a, b) {
          final pa = a.split('.').map(int.tryParse).toList();
          final pb = b.split('.').map(int.tryParse).toList();
          for (int i = 0; i < 3; i++) {
            final va = i < pa.length ? (pa[i] ?? 0) : 0;
            final vb = i < pb.length ? (pb[i] ?? 0) : 0;
            if (va != vb) return vb.compareTo(va);
          }
          return 0;
        });

      return {for (final k in sortedKeys) k: map[k]!};
    } finally {
      client.close();
    }
  }

  /// 获取 SurvivalcraftNet 联机版的发行版列表（Gitee Releases）。
  ///
  /// 数据源：`https://gitee.com/api/v5/repos/SC-SPM/SurvivalcraftNet/releases`
  /// 返回每个发行版的 `tag_name`，按发布时间倒序（最新在前）。
  /// 同时缓存每个 tag 对应的服务端资产名，供下载时使用。
  static Future<List<String>> fetchSurvivalcraftVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://gitee.com/api/v5/repos/SC-SPM/SurvivalcraftNet/releases?per_page=40',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;
      return json
          .map<String>((r) => (r as Map<String, dynamic>)['tag_name'] as String)
          .where((tag) => tag.isNotEmpty)
          .toList();
    } finally {
      client.close();
    }
  }

  /// 从 GitHub Releases 获取 PowerNukkitX 版本列表（tag_name），
  /// 同时从 release body 中提取对应的 MCBE 版本号返回。
  static Future<({List<String> versions, Map<String, String> mcVersions})>
      fetchPowernukkitxVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/PowerNukkitX/PowerNukkitX/releases',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;
      final mcVersionRegex = RegExp(
        r'\|\s*\*\*Supported Minecraft Version\*\*\s*\|\s*([\d.]+)\s*\|',
      );
      final versions = <String>[];
      final mcVersions = <String, String>{};
      for (final r in json) {
        final release = r as Map<String, dynamic>;
        final tagName = release['tag_name'] as String;
        versions.add(tagName);
        final bodyText = release['body'] as String?;
        if (bodyText != null) {
          final match = mcVersionRegex.firstMatch(bodyText);
          if (match != null) {
            mcVersions[tagName] = match.group(1)!;
          }
        }
      }
      return (versions: versions, mcVersions: mcVersions);
    } finally {
      client.close();
    }
  }

  /// 获取 PocketMine-MP 版本列表（5.x 稳定版，降序）及每个版本对应的 MCBE 版本。
  ///
  /// 数据源：https://github.com/pmmp/update.pmmp.io/tree/master/channels
  static Future<({List<String> versions, Map<String, String> mcpeVersions})>
      fetchPocketmineVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/pmmp/update.pmmp.io/contents/channels',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;

      // 仅匹配 5.x 稳定版本文件名（如 5、5.44、5.25.0），排除 alpha/beta 等。
      final versionPattern = RegExp(r'^5(\.\d+)*$');
      final versions = <String>[];
      for (final item in json) {
        final name = (item as Map<String, dynamic>)['name'] as String;
        if (!name.endsWith('.json')) continue;
        final base = name.substring(0, name.length - 5); // 去掉 .json
        if (!versionPattern.hasMatch(base)) continue;
        versions.add(base);
      }

      // 按版本号降序排列（最新版本在前）。
      versions.sort((a, b) {
        final pa = a.split('.').map(int.tryParse).toList();
        final pb = b.split('.').map(int.tryParse).toList();
        final len = pa.length > pb.length ? pa.length : pb.length;
        for (int i = 0; i < len; i++) {
          final va = i < pa.length ? (pa[i] ?? 0) : 0;
          final vb = i < pb.length ? (pb[i] ?? 0) : 0;
          if (va != vb) return vb.compareTo(va);
        }
        return 0;
      });

      // 并发获取每个版本的 mcpe_version。
      final mcpeVersions = <String, String>{};
      await Future.wait(
        versions
            .map((v) => _fetchPocketmineMcpeVersion(client, v, mcpeVersions)),
      );

      return (versions: versions, mcpeVersions: mcpeVersions);
    } finally {
      client.close();
    }
  }

  /// 获取单个 PocketMine-MP 版本对应的 MCBE 客户端版本，写入 [into]。
  /// 失败时静默跳过（不影响版本列表）。
  static Future<void> _fetchPocketmineMcpeVersion(
    HttpClient client,
    String version,
    Map<String, String> into,
  ) async {
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://raw.githubusercontent.com/pmmp/update.pmmp.io/master/channels/$version.json',
        ),
      );
      req.headers.set('User-Agent', await CloudHeaders.userAgent);
      final res = await req.close();
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final mcpe = json['mcpe_version'] as String?;
      if (mcpe != null && mcpe.isNotEmpty) {
        into[version] = mcpe;
      }
    } catch (_) {
      // 单个版本获取失败不影响整体列表。
    }
  }

  /// 解析 NeoForge Maven 元数据 XML，返回 {mcVersion: [neoforgeVersion...]}。
  static Future<Map<String, List<String>>> fetchAllNeoforgeVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml',
        ),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      final versionPattern = RegExp(r'<version>([^<]+)</version>');
      final matches = versionPattern.allMatches(body);

      final map = <String, List<String>>{};
      for (final m in matches) {
        final full = m.group(1)!;
        if (full.contains('-beta')) continue;
        final cleanFull = full.split('-').first;
        final parts = cleanFull.split('.');
        if (parts.length < 3) continue;
        final String mcVersion;
        if (parts.length >= 4) {
          mcVersion = '${parts[0]}.${parts[1]}.${parts[2]}';
        } else {
          mcVersion = '${parts[0]}.${parts[1]}';
        }
        map.putIfAbsent(mcVersion, () => []).add(full);
      }

      final sortedKeys = map.keys.toList()
        ..sort((a, b) {
          final pa = a.split('.').map(int.tryParse).toList();
          final pb = b.split('.').map(int.tryParse).toList();
          for (int i = 0; i < 3; i++) {
            final va = i < pa.length ? (pa[i] ?? 0) : 0;
            final vb = i < pb.length ? (pb[i] ?? 0) : 0;
            if (va != vb) return vb.compareTo(va);
          }
          return 0;
        });

      return {for (final k in sortedKeys) k: map[k]!};
    } finally {
      client.close();
    }
  }
}
