import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// Mod 加载器类型。
enum ModLoader { fabric, forge, quilt, neoforge, unknown }

/// 从 .jar 文件中解析出的模组元数据。
///
/// 参考自 PCL-CE 的 ModLocalComp.LookupMetadata，依次尝试
/// fabric.mod.json → quilt.mod.json → META-INF/mods.toml → mcmod.info。
class ModMetadata {
  const ModMetadata({
    required this.name,
    this.version,
    this.description,
    this.modId,
    this.authors,
    this.url,
    this.loader = ModLoader.unknown,
  });

  final String name;
  final String? version;
  final String? description;
  final String? modId;
  final String? authors;
  final String? url;
  final ModLoader loader;

  String get loaderLabel => switch (loader) {
        ModLoader.fabric => 'Fabric',
        ModLoader.forge => 'Forge',
        ModLoader.quilt => 'Quilt',
        ModLoader.neoforge => 'NeoForge',
        ModLoader.unknown => '',
      };
}

/// 从 .jar（zip）中解析模组元数据。
class ModMetadataParser {
  ModMetadataParser._();

  /// 解析 [jarPath] 指向的 .jar 文件，返回元数据；无法识别返回 null。
  static Future<ModMetadata?> parse(String jarPath) async {
    final file = File(jarPath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    Archive? archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }

    // 1. fabric.mod.json
    final fabric = _readEntry(archive, 'fabric.mod.json');
    if (fabric != null) {
      final meta = _parseFabricModJson(fabric);
      if (meta != null) return meta;
    }

    // 2. quilt.mod.json
    final quilt = _readEntry(archive, 'quilt.mod.json');
    if (quilt != null) {
      final meta = _parseQuiltModJson(quilt);
      if (meta != null) return meta;
    }

    // 3. META-INF/mods.toml (Forge 1.13+ / NeoForge)
    final modsToml = _readEntry(archive, 'META-INF/mods.toml');
    if (modsToml != null) {
      final meta = _parseModsToml(modsToml);
      if (meta != null) return meta;
    }

    // 4. mcmod.info (Forge 1.7.10 及更早)
    final mcmodInfo = _readEntry(archive, 'mcmod.info');
    if (mcmodInfo != null) {
      final meta = _parseMcmodInfo(mcmodInfo);
      if (meta != null) return meta;
    }

    return null;
  }

  /// 读取 zip 中某个条目的内容（UTF-8 字符串），不存在返回 null。
  static String? _readEntry(Archive archive, String name) {
    final entry = archive.findFile(name);
    if (entry == null || !entry.isFile) return null;
    try {
      final data = entry.content;
      return utf8.decode(data, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  // ── fabric.mod.json ──────────────────────────────────────────
  static ModMetadata? _parseFabricModJson(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final name = data['name'] as String?;
      final id = data['id'] as String?;
      if (name == null && id == null) return null;
      final version = data['version'] as String?;
      final description = data['description'] as String?;
      String? url;
      final contact = data['contact'];
      if (contact is Map<String, dynamic>) {
        url = contact['homepage'] as String?;
      }
      String? authors;
      final authorsRaw = data['authors'];
      if (authorsRaw is List && authorsRaw.isNotEmpty) {
        authors = authorsRaw.map((a) {
          if (a is String) return a;
          if (a is Map<String, dynamic>) return a['name'] as String? ?? '';
          return '';
        }).where((s) => s.isNotEmpty).join(', ');
      }
      return ModMetadata(
        name: name ?? id!,
        version: version,
        description: description,
        modId: id,
        authors: authors,
        url: url,
        loader: ModLoader.fabric,
      );
    } catch (_) {
      return null;
    }
  }

  // ── quilt.mod.json ───────────────────────────────────────────
  static ModMetadata? _parseQuiltModJson(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final quiltLoader = data['quilt_loader'];
      if (quiltLoader is! Map<String, dynamic>) return null;
      final id = quiltLoader['id'] as String?;
      final version = quiltLoader['version'] as String?;
      if (id == null) return null;
      String name = id;
      String? description;
      final metadata = data['metadata'];
      if (metadata is Map<String, dynamic>) {
        name = metadata['name'] as String? ?? id;
        description = metadata['description'] as String?;
      }
      return ModMetadata(
        name: name,
        version: version,
        description: description,
        modId: id,
        loader: ModLoader.quilt,
      );
    } catch (_) {
      return null;
    }
  }

  // ── META-INF/mods.toml ───────────────────────────────────────
  /// 简易 TOML 解析，仅提取 [[mods]] 段的 modId / displayName /
  /// description / version 和全局段的 displayURL / authors。
  static ModMetadata? _parseModsToml(String toml) {
    try {
      final lines = toml.split('\n');
      String? currentSection;
      final mods = <String, String>{};
      final global = <String, String>{};
      var inModsArray = false;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

        // Section header
        final sectionMatch = RegExp(r'^\[+(.+?)\]+$').firstMatch(trimmed);
        if (sectionMatch != null) {
          final section = sectionMatch.group(1)!;
          currentSection = section;
          inModsArray = section == 'mods';
          continue;
        }

        // Key-value
        final kvMatch = RegExp(r'^([a-zA-Z_]+)\s*=\s*(.+)$').firstMatch(trimmed);
        if (kvMatch == null) continue;
        final key = kvMatch.group(1)!;
        var value = kvMatch.group(2)!;

        // Remove surrounding quotes
        if (value.startsWith('"') && value.endsWith('"')) {
          value = value.substring(1, value.length - 1);
        } else if (value.startsWith("'") && value.endsWith("'")) {
          value = value.substring(1, value.length - 1);
        }
        value = value.replaceAll('\\"', '"');

        if (inModsArray) {
          mods[key] = value;
        } else if (currentSection == null || !currentSection.startsWith('dependencies')) {
          global[key] = value;
        }
      }

      final modId = mods['modId'];
      final displayName = mods['displayName'] ?? mods['modId'];
      if (modId == null && displayName == null) return null;

      final isNeoForge = toml.contains('neoforge') || toml.contains('NeoForge');

      return ModMetadata(
        name: displayName!,
        version: mods['version'],
        description: mods['description'],
        modId: modId,
        authors: global['authors'],
        url: global['displayURL'],
        loader: isNeoForge ? ModLoader.neoforge : ModLoader.forge,
      );
    } catch (_) {
      return null;
    }
  }

  // ── mcmod.info ───────────────────────────────────────────────
  static ModMetadata? _parseMcmodInfo(String jsonStr) {
    try {
      var data = jsonDecode(jsonStr);
      List list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic> && data['modList'] is List) {
        list = data['modList'] as List;
      } else {
        return null;
      }
      if (list.isEmpty) return null;
      final first = list[0] as Map<String, dynamic>;
      final name = first['name'] as String? ?? first['modid'] as String?;
      if (name == null) return null;
      String? authors;
      final authorsRaw = first['authorList'];
      if (authorsRaw is List && authorsRaw.isNotEmpty) {
        authors = authorsRaw.cast<String>().join(', ');
      }
      return ModMetadata(
        name: name,
        version: first['version'] as String?,
        description: first['description'] as String?,
        modId: first['modid'] as String?,
        authors: authors,
        url: first['url'] as String?,
        loader: ModLoader.forge,
      );
    } catch (_) {
      return null;
    }
  }
}
