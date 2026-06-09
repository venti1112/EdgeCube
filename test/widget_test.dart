import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:edgecube/files/file_service.dart';
import 'package:edgecube/instance/instance_controller.dart';
import 'package:edgecube/main.dart';
import 'package:edgecube/theme/theme_store.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    // 内存版 SharedPreferences，供主题与实例元数据读写。
    SharedPreferences.setMockInitialValues({});
    // 临时目录承载实例文件夹，避免依赖原生 path_provider。
    tempRoot = await Directory.systemTemp.createTemp('edgecube_test');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  /// 构造一个文件夹根目录指向临时目录、已初始化的控制器。
  Future<InstanceController> makeController() async {
    final controller = InstanceController(rootResolver: () async => tempRoot);
    await controller.init();
    return controller;
  }

  Future<void> pumpApp(WidgetTester tester, InstanceController controller) {
    return tester.pumpWidget(EdgeCubeApp(instanceController: controller));
  }

  testWidgets('底部导航显示全部标签并可切换页面', (WidgetTester tester) async {
    await pumpApp(tester, await makeController());

    expect(find.text('服务器'), findsWidgets);
    expect(find.text('控制台'), findsWidgets);
    expect(find.text('玩家'), findsWidgets);
    expect(find.text('文件'), findsWidgets);
    expect(find.text('设置'), findsWidgets);

    // 点击“文件”切换页面（无实例时提示先建实例）。
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(
      find.text('请先在「服务器」页新建并选择一个实例，再管理其文件。'),
      findsOneWidget,
    );
  });

  testWidgets('设置页可切换主题模式，默认跟随系统', (WidgetTester tester) async {
    await pumpApp(tester, await makeController());

    MaterialApp app() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app().themeMode, ThemeMode.system);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.dark);

    await tester.tap(find.text('浅色模式'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);
  });

  testWidgets('主题选择会被持久化并在重启后恢复', (WidgetTester tester) async {
    await pumpApp(tester, await makeController());

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(() => ThemeStore.load());
    expect(saved, ThemeMode.dark);

    await tester.pumpWidget(EdgeCubeApp(
      initialThemeMode: saved!,
      instanceController: await makeController(),
    ));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('无实例时服务器页提示新建', (WidgetTester tester) async {
    await pumpApp(tester, await makeController());
    expect(find.text('还没有实例'), findsOneWidget);
    expect(find.text('选择实例'), findsWidgets);
  });

  testWidgets('可新建实例并自动选中，文件夹真实创建', (WidgetTester tester) async {
    final controller = await makeController();
    await pumpApp(tester, controller);

    // 打开实例选择弹窗。
    await tester.tap(find.text('选择实例'));
    await tester.pumpAndSettle();

    // 点击“新建实例”，对话框默认名“新实例”。
    await tester.tap(find.text('新建实例'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 控制器中已有一个被选中的实例。
    expect(controller.instances.length, 1);
    expect(controller.selected, isNotNull);
    expect(controller.selected!.name, '新实例');

    // 磁盘上以随机 id 命名的文件夹已创建。
    final dir = Directory('${tempRoot.path}/${controller.selected!.id}');
    expect(dir.existsSync(), isTrue);

    // 服务器页标题显示该实例名。
    expect(find.text('新实例'), findsWidgets);
  });

  testWidgets('可编辑实例显示名称', (WidgetTester tester) async {
    final controller = await makeController();
    await controller.createInstance('旧名称');
    await pumpApp(tester, controller);

    // 点击右上角编辑按钮。
    await tester.tap(find.byTooltip('编辑实例'));
    await tester.pumpAndSettle();

    // 清空并输入新名称。
    await tester.enterText(find.byType(TextField), '新名称');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(controller.selected!.name, '新名称');
    expect(find.text('新名称'), findsWidgets);
  });

  group('实例名唯一性', () {
    test('新建同名实例抛异常', () async {
      final controller =
          InstanceController(rootResolver: () async => tempRoot);
      await controller.init();
      await controller.createInstance('世界');
      expect(
        () => controller.createInstance('  世界  '),
        throwsA(isA<DuplicateInstanceNameException>()),
      );
      expect(controller.instances.length, 1);
    });

    test('改名撞上其它实例抛异常，但可改回自身原名', () async {
      final controller =
          InstanceController(rootResolver: () async => tempRoot);
      await controller.init();
      final a = await controller.createInstance('A');
      await controller.createInstance('B');
      expect(
        () => controller.rename(a.id, 'B'),
        throwsA(isA<DuplicateInstanceNameException>()),
      );
      // 改成与自身相同的名字不应报错。
      await controller.rename(a.id, 'A');
      expect(controller.instances.firstWhere((i) => i.id == a.id).name, 'A');
    });
  });

  group('FileService', () {
    late Directory root;
    const service = FileService();

    setUp(() async {
      root = await Directory.systemTemp.createTemp('edgecube_files');
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('列目录：文件夹在前并按名排序', () async {
      await File(p.join(root.path, 'b.txt')).create();
      await File(p.join(root.path, 'a.txt')).create();
      await Directory(p.join(root.path, 'sub')).create();
      final entries = await service.list(root);
      expect(entries.map((e) => e.name).toList(), ['sub', 'a.txt', 'b.txt']);
    });

    test('复制重名自动追加后缀', () async {
      final src = File(p.join(root.path, 'note.txt'));
      await src.writeAsString('hello');
      await service.copy(src.path, root);
      final names = (await service.list(root)).map((e) => e.name).toSet();
      expect(names.contains('note.txt'), isTrue);
      expect(names.contains('note (1).txt'), isTrue);
    });

    test('移动文件到子目录', () async {
      final src = File(p.join(root.path, 'm.txt'));
      await src.writeAsString('x');
      final sub = await Directory(p.join(root.path, 'dst')).create();
      await service.move(src.path, sub);
      expect(File(p.join(sub.path, 'm.txt')).existsSync(), isTrue);
      expect(src.existsSync(), isFalse);
    });

    test('重命名冲突抛异常', () async {
      await File(p.join(root.path, 'x.txt')).create();
      final y = File(p.join(root.path, 'y.txt'));
      await y.create();
      expect(
        () => service.rename(y.path, 'x.txt'),
        throwsA(isA<FileConflictException>()),
      );
    });

    test('禁止把目录移入自身子目录', () async {
      final dir = await Directory(p.join(root.path, 'parent')).create();
      final child = await Directory(p.join(dir.path, 'child')).create();
      expect(
        () => service.move(dir.path, child),
        throwsA(isA<InvalidDestinationException>()),
      );
    });

    test('递归删除目录', () async {
      final dir = await Directory(p.join(root.path, 'del')).create();
      await File(p.join(dir.path, 'inner.txt')).create();
      await service.delete(dir.path);
      expect(dir.existsSync(), isFalse);
    });
  });
}
