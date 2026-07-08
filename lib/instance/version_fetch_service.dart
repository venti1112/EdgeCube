import 'dart:convert';
import 'dart:io';

class VersionFetchService {
  VersionFetchService._();

  static Future<List<String>> fetchPaperVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://fill.papermc.io/v3/projects/paper'),
      );
      req.headers.set('User-Agent', 'EdgeCube/1.0');
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
      req.headers.set('User-Agent', 'EdgeCube/1.0');
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
      req.headers.set('User-Agent', 'EdgeCube/1.0');
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
      req.headers.set('User-Agent', 'EdgeCube/1.0');
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
      req.headers.set('User-Agent', 'EdgeCube/1.0');
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
      req.headers.set('User-Agent', 'EdgeCube/1.0');
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
      req.headers.set('User-Agent', 'EdgeCube/1.0');
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
    req.headers.set('User-Agent', 'EdgeCube/1.0');
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
      req.headers.set('User-Agent', 'EdgeCube/1.0');
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
  /// 版本格式为 "{mcVersion}-{forgeVersion}"，按最后一个 "-" 分割。
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
        final lastDash = full.lastIndexOf('-');
        if (lastDash < 0) continue;
        final mcVersion = full.substring(0, lastDash);
        final forgeVersion = full.substring(lastDash + 1);
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
