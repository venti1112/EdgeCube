import 'dart:io';

import 'package:edgecube/server/world_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 在 [parent] 下建一个世界目录，[kind] 决定用哪种服务端的标识文件：
/// java（level.dat）/ region（仅区域目录）/ bedrock（db 目录）。
Future<Directory> _makeWorld(
  Directory parent,
  String name, {
  String kind = 'java',
}) async {
  final dir = Directory(p.join(parent.path, name));
  await dir.create(recursive: true);
  switch (kind) {
    case 'region':
      await Directory(p.join(dir.path, 'region')).create(recursive: true);
    case 'bedrock':
      await Directory(p.join(dir.path, 'db')).create(recursive: true);
    default:
      await File(p.join(dir.path, 'level.dat')).writeAsBytes([1, 2, 3]);
  }
  return dir;
}

Future<Directory> _makeDir(Directory parent, String name) async {
  final dir = Directory(p.join(parent.path, name));
  await dir.create(recursive: true);
  return dir;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('edgecube_world_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('level-name 读写', () {
    test('缺少 server.properties 时回退到默认世界名', () async {
      expect(await WorldService.readLevelName(tempDir), 'world');
    });

    test('读取 server.properties 中的 level-name', () async {
      await File(p.join(tempDir.path, 'server.properties')).writeAsString(
        '#Minecraft server properties\nmax-players=20\nlevel-name=我的世界\n',
      );
      expect(await WorldService.readLevelName(tempDir), '我的世界');
    });

    test('level-name 为空时回退到默认世界名', () async {
      await File(
        p.join(tempDir.path, 'server.properties'),
      ).writeAsString('level-name=\n');
      expect(await WorldService.readLevelName(tempDir), 'world');
    });

    test('writeLevelName 更新已有键且保留其它配置', () async {
      final file = File(p.join(tempDir.path, 'server.properties'));
      await file.writeAsString('level-name=world\nmax-players=20\n');
      expect(await WorldService.writeLevelName(tempDir, 'new_world'), isTrue);
      expect(await WorldService.readLevelName(tempDir), 'new_world');
      expect(await file.readAsString(), contains('max-players=20'));
    });

    test('writeLevelName 在文件不存在时不创建文件', () async {
      expect(await WorldService.writeLevelName(tempDir, 'new_world'), isFalse);
      expect(
        await File(p.join(tempDir.path, 'server.properties')).exists(),
        isFalse,
      );
    });

    test('clearLevelSeed 清空种子，未配置时不改文件', () async {
      final file = File(p.join(tempDir.path, 'server.properties'));
      await file.writeAsString('level-seed=12345\nlevel-name=world\n');
      expect(await WorldService.clearLevelSeed(tempDir), isTrue);
      expect(await file.readAsString(), contains('level-seed=\n'));
      // 已经为空，重复调用不再写文件。
      expect(await WorldService.clearLevelSeed(tempDir), isFalse);
    });
  });

  group('世界识别', () {
    test('分别识别 java / region / bedrock 目录', () async {
      expect(WorldService.isWorldDirSync(await _makeWorld(tempDir, 'a')), true);
      expect(
        WorldService.isWorldDirSync(
          await _makeWorld(tempDir, 'b', kind: 'region'),
        ),
        true,
      );
      expect(
        WorldService.isWorldDirSync(
          await _makeWorld(tempDir, 'c', kind: 'bedrock'),
        ),
        true,
      );
      expect(WorldService.isWorldDirSync(await _makeDir(tempDir, 'mods')), false);
    });

    test('listWorlds 只列出世界目录并跳过隐藏目录', () async {
      await _makeWorld(tempDir, 'world_nether');
      await _makeWorld(tempDir, 'world');
      await _makeWorld(tempDir, '.world_import_1');
      await _makeDir(tempDir, 'mods');
      final worlds = await WorldService.listWorlds(tempDir);
      expect(worlds.map((w) => w.name).toList(), ['world', 'world_nether']);
      expect(worlds.every((w) => w.sizeBytes != null), isTrue);
    });

    test('worldsForLevel 带上 nether / the_end 伴生目录', () async {
      await _makeWorld(tempDir, 'world');
      await _makeWorld(tempDir, 'world_nether');
      await _makeWorld(tempDir, 'world_the_end');
      await _makeWorld(tempDir, 'another');
      final related = await WorldService.worldsForLevel(tempDir, 'world');
      expect(
        related.map((w) => w.name).toList(),
        ['world', 'world_nether', 'world_the_end'],
      );
    });

    test('deleteWorld 递归删除世界目录', () async {
      final dir = await _makeWorld(tempDir, 'world');
      final worlds = await WorldService.listWorlds(tempDir);
      await WorldService.deleteWorld(worlds.single);
      expect(await dir.exists(), isFalse);
      // 目录已不存在时静默通过。
      await WorldService.deleteWorld(worlds.single);
    });
  });

  group('导入扫描', () {
    test('压缩包根目录就是世界时用兜底名', () async {
      final root = await _makeWorld(tempDir, 'unpacked');
      final found = await WorldService.scanForWorlds(
        root,
        fallbackName: 'my_world.zip',
      );
      expect(found, hasLength(1));
      expect(found.single.name, 'my_world.zip');
    });

    test('压缩包内含若干世界目录时按目录名导入', () async {
      final root = await _makeDir(tempDir, 'unpacked');
      await _makeWorld(root, 'world');
      await _makeWorld(root, 'world_nether');
      await _makeDir(root, 'mods');
      final found = await WorldService.scanForWorlds(root);
      expect(found.map((w) => w.name).toList(), ['world', 'world_nether']);
    });

    test('归档多包一层时向内再找一层', () async {
      final root = await _makeDir(tempDir, 'unpacked');
      final backup = await _makeDir(root, 'backup');
      await _makeWorld(backup, 'world');
      final found = await WorldService.scanForWorlds(root);
      expect(found, hasLength(1));
      expect(found.single.name, 'world');
    });

    test('没有世界目录时返回空列表', () async {
      final root = await _makeDir(tempDir, 'unpacked');
      await _makeDir(root, 'mods');
      expect(await WorldService.scanForWorlds(root), isEmpty);
    });

    test('世界名中的非法字符被替换', () async {
      final root = await _makeDir(tempDir, 'unpacked');
      await _makeWorld(root, 'server:world');
      final found = await WorldService.scanForWorlds(root);
      expect(found.single.name, 'server_world');
    });
  });

  group('导入落盘', () {
    test('移动到实例目录并返回导入的世界名', () async {
      final source = await _makeDir(tempDir, 'unpacked');
      await _makeWorld(source, 'world');
      final instance = await _makeDir(tempDir, 'instance');
      final found = await WorldService.scanForWorlds(source);
      final imported = await WorldService.moveIntoInstance(instance, found);
      expect(imported, ['world']);
      expect(
        WorldService.isWorldDirSync(Directory(p.join(instance.path, 'world'))),
        isTrue,
      );
    });

    test('同名目录存在时未允许覆盖会抛冲突，允许后删除原目录', () async {
      final source = await _makeDir(tempDir, 'unpacked');
      final newWorld = await _makeWorld(source, 'world');
      await File(p.join(newWorld.path, 'marker_new')).writeAsString('new');
      final instance = await _makeDir(tempDir, 'instance');
      final oldWorld = await _makeWorld(instance, 'world');
      await File(p.join(oldWorld.path, 'marker_old')).writeAsString('old');

      final found = await WorldService.scanForWorlds(source);
      expect(
        () => WorldService.moveIntoInstance(instance, found),
        throwsA(isA<WorldImportConflictException>()),
      );
      await WorldService.moveIntoInstance(instance, found, overwrite: true);
      expect(
        await File(p.join(instance.path, 'world', 'marker_new')).exists(),
        isTrue,
      );
      expect(
        await File(p.join(instance.path, 'world', 'marker_old')).exists(),
        isFalse,
      );
    });
  });
}
