import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/instance/config/config_page.dart';
import 'package:edgecube_app/instance/config/draft.dart';
import 'package:edgecube_app/instance/config/icon_crop_page.dart';
import 'package:edgecube_app/instance/config/icon_image.dart';
import 'package:edgecube_app/instance/config/parsers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

/// 「服务器配置」页。
///
/// 钉三件事：
///
/// * **认哪种配置由 daemon 说了算** —— 页面本身不认识优先级，给它什么 kind 就画
///   哪张表（这是这次改造的核心）。
/// * 一个配置文件都没有时给「先启动一次服务端」，不是错误弹窗。
/// * 编辑 → 保存发的是整份文本 + `kind`（**不带路径** —— 写哪个文件由 daemon 算）。

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

// ══════════════════════════════════════════════════════════════════════════
// 解析器（纯 Dart，不起 widget）
// ══════════════════════════════════════════════════════════════════════════

void _parserTests() {
  group('server.properties 的行级编辑', () {
    test('读得到值，注释与排版一字不动', () {
      const source = '# 这是说明\nmotd=我的服务器\n\nmax-players=20\n';
      final doc = KeyValueDocument.parse(source);

      expect(doc['motd'], '我的服务器');
      expect(doc['max-players'], '20');
      expect(doc['不存在'], isNull);
      expect(doc.containsKey('motd'), isTrue);
      // 没改过：序列化回去逐字相同
      expect(doc.serialize(), source);
    });

    test('改一个键只动那一行，且存一次不会长出新行', () {
      const source = '# 说明\nmotd=旧\nmax-players=20\n';
      final doc = KeyValueDocument.parse(source);
      doc.setValue('motd', '新');

      expect(doc.serialize(), '# 说明\nmotd=新\nmax-players=20\n');
      // 再存一次不该继续变（不会存一次多一个空行）
      expect(doc.serialize(), doc.serialize());
    });

    test('值里可以有 =，按第一个 = 切', () {
      final doc = KeyValueDocument.parse('generator-settings={"a":1,"b":2}\n');
      expect(doc['generator-settings'], '{"a":1,"b":2}');
    });

    test('不认识的键只改不增', () {
      final doc = KeyValueDocument.parse('motd=hi\n');
      doc.setValue('谁知道呢', 'x');
      expect(doc.serialize(), 'motd=hi\n');
    });
  });

  group('YAML 的行级编辑', () {
    test('点分路径认多层嵌套', () {
      const source = 'settings:\n  motd: hi\n  port: 19132\nother:\n  x: 1\n';
      final doc = YamlDocument.parse(source);

      expect(doc['settings.motd'], 'hi');
      expect(doc['settings.port'], '19132');
      expect(doc['other.x'], '1');
      expect(doc.serialize(), source);
    });

    test('改值保留缩进与行尾注释', () {
      final doc = YamlDocument.parse('settings:\n  port: 19132 # 默认端口\n');
      doc.setValue('settings.port', '25565');
      expect(doc.serialize(), 'settings:\n  port: 25565 # 默认端口\n');
    });

    test('引号包着的值原样读出（里面可以有 #）', () {
      final doc = YamlDocument.parse('settings:\n  motd: "你好 # 世界"\n');
      expect(doc['settings.motd'], '你好 # 世界');
    });

    test('按 kind 选解析器', () {
      expect(ConfigDocument.parse('pnx', 'a:\n  b: 1\n'), isA<YamlDocument>());
      expect(ConfigDocument.parse('allay', 'a:\n  b: 1\n'), isA<YamlDocument>());
      expect(ConfigDocument.parse('java', 'a=1\n'), isA<KeyValueDocument>());
      expect(ConfigDocument.parse('pmmp', 'a=on\n'), isA<KeyValueDocument>());
    });
  });

  group('草稿的脏判定', () {
    ConfigDraft draft(String kind, String content) => ConfigDraft(
      kind: kind,
      file: kind == 'java' || kind == 'pmmp'
          ? 'server.properties'
          : (kind == 'pnx' ? 'pnx.yml' : 'server-settings.yml'),
      document: ConfigDocument.parse(kind, content),
    );

    test('改回原值就不算脏', () {
      final d = draft('java', 'motd=旧\n');
      expect(d.hasChanges, isFalse);

      d.setValue('motd', '新');
      expect(d.hasChanges, isTrue);
      expect(d.dirty('motd'), isTrue);

      d.setValue('motd', '旧');
      expect(d.hasChanges, isFalse);
    });

    test('文件里没有的键不画（开关除外）', () {
      final d = draft('java', 'motd=hi\n');
      expect(d.present('motd'), isTrue);
      expect(d.present('max-players'), isFalse);
    });

    test('开关「打开又关上」不算脏，也不会把不存在的键写进文件', () {
      final d = draft('java', 'motd=hi\n');
      d.setBool('pvp', true);
      expect(d.dirty('pvp'), isTrue);

      d.setBool('pvp', false);
      // 生效的布尔值没变（缺省就是关），所以不脏 —— 否则会凭空多出一行 pvp=false
      expect(d.dirty('pvp'), isFalse);
      expect(d.serialize(), 'motd=hi\n');
    });

    test('PocketMine 的开关写成 on / off', () {
      final d = draft('pmmp', 'pvp=on\n');
      d.setBool('pvp', false);
      expect(d.serialize(), 'pvp=off\n');
    });

    test('保存只写脏字段，别的行原样保留', () {
      final d = draft('java', '# 顶部注释\nmotd=旧\nmax-players=20\n');
      d.setValue('max-players', '30');
      expect(d.serialize(), '# 顶部注释\nmotd=旧\nmax-players=30\n');
    });
  });
}

// ══════════════════════════════════════════════════════════════════════════
// 页面
// ══════════════════════════════════════════════════════════════════════════

typedef ConfigFixture = ({
  ProviderContainer container,
  FakeInstanceStore store,
  FakeDaemonTransport transport,
  String id,
});

/// 连上假 daemon，摆好实例与它的配置文件。
///
/// [files] 是「文件名 → 内容」。假后端按 daemon 那套优先级认类型，所以
/// **测试不用自己算 kind** —— 摆个 `pnx.yml` 进去，回来的就是 `pnx`。
Future<ConfigFixture> bootConfig({
  Map<String, String> files = const {},
  Uint8List? icon,
  bool withInstance = true,
  String phase = 'stopped',
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = FakeInstanceStore();
  final id = withInstance ? store.seed(name: '生存服') : '';
  store.phase = phase;
  if (withInstance && files.isNotEmpty) {
    store.configFiles[id] = {...files};
  }
  if (withInstance && icon != null) {
    store.icons[id] = icon;
  }
  final factory = FakeTransportFactory(instances: store);
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: factory.call,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  return (
    container: container,
    store: store,
    transport: factory.latest,
    id: id,
  );
}

Future<void> pumpConfig(WidgetTester tester, ConfigFixture fixture) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: const MaterialApp(home: InstanceConfigPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void _pageTests() {
  testWidgets('daemon 说是 server.properties：画 Java 那套字段', (tester) async {
    final fixture = await bootConfig(
      files: {'server.properties': 'motd=我的服\nmax-players=20\npvp=true\n'},
    );
    await pumpConfig(tester, fixture);

    // 入口文案是通用的，具体在改哪个文件写在页面里
    expect(find.text('服务器配置'), findsOneWidget);
    expect(find.text('编辑 server.properties'), findsOneWidget);

    // Java 表里的字段都在
    expect(find.text('服务器描述 (MOTD)'), findsOneWidget);
    expect(find.text('最大玩家数'), findsOneWidget);
    expect(find.text('启用 PvP'), findsOneWidget);
    // pnx / allay 专有的字段不该出现 —— 说明表是按 kind 选的，不是画全部
    expect(find.text('副描述 (Sub-MOTD)'), findsNothing);
    expect(find.text('RakNet 最大 MTU'), findsNothing);
  });

  testWidgets('daemon 说是 pnx.yml：换成 PowerNukkitX 那套字段', (tester) async {
    final fixture = await bootConfig(
      files: {
        'pnx.yml': 'settings:\n  motd: hi\n  sub-motd: 副\n  port: 19132\n',
      },
    );
    await pumpConfig(tester, fixture);

    expect(find.text('编辑 pnx.yml'), findsOneWidget);
    // pnx 专有的字段（字段表里没有这个键就不画，所以夹具里得真有它）
    expect(find.text('副描述 (Sub-MOTD)'), findsOneWidget);
    // Java 专有的（pnx 表里没有）不该出现
    expect(find.text('最大 Tick 时间'), findsNothing);
  });

  testWidgets('三种配置文件都没有：提示先启动一次服务端，不是错误', (tester) async {
    final fixture = await bootConfig();
    await pumpConfig(tester, fixture);

    expect(find.textContaining('server.properties 文件不存在'), findsOneWidget);
    expect(find.textContaining('请先启动一次服务器'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('没选中实例时给一句话', (tester) async {
    final fixture = await bootConfig(withInstance: false);
    await pumpConfig(tester, fixture);

    expect(find.text('未选中任何实例'), findsOneWidget);
  });

  testWidgets('改一个字段再保存：发出的 kind 与整份内容都对，且不带路径', (tester) async {
    final fixture = await bootConfig(
      files: {'server.properties': '# 说明\nmotd=旧\nmax-players=20\n'},
    );
    await pumpConfig(tester, fixture);

    // 没改之前保存按钮是灰的
    final saveButton = find.widgetWithIcon(IconButton, Icons.save_outlined);
    expect(saveButton, findsOneWidget);
    expect(tester.widget<IconButton>(saveButton).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('config_motd')),
      '新描述',
    );
    await tester.pumpAndSettle();

    // 改完变成可保存（图标也换成实心那个）
    final dirtyButton = find.widgetWithIcon(IconButton, Icons.save);
    expect(tester.widget<IconButton>(dirtyButton).onPressed, isNotNull);

    await tester.tap(dirtyButton);
    await tester.pumpAndSettle();

    final saved = fixture.store.savedConfig[fixture.id];
    expect(saved, isNotNull, reason: '应当发过 instance.config.save');
    expect(saved!.kind, 'java');
    // **只有改过的那一行变了**，注释与另一行原样
    expect(saved.content, '# 说明\nmotd=新描述\nmax-players=20\n');
    // 写哪个文件是 daemon 按 kind 算的，前端连路径都不该发
    final envelope = fixture.transport.sent
        .where((e) => e['method'] == 'instance.config.save')
        .single;
    final params = envelope['params'] as Map;
    expect(params.keys, containsAll(['id', 'kind', 'content']));
    expect(params.containsKey('path'), isFalse);
  });

  testWidgets('PocketMine 的开关写回 on / off，不是 true / false', (tester) async {
    // `pvp=on` 就是 daemon 认 PMMP 的依据（布尔值写法）
    final fixture = await bootConfig(files: {'server.properties': 'pvp=on\n'});
    await pumpConfig(tester, fixture);

    // 认成 PMMP 之后 gamemode 的取值是大写的（Java 那套是小写）
    expect(find.text('启用 PvP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('config_pvp')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.save));
    await tester.pumpAndSettle();

    final saved = fixture.store.savedConfig[fixture.id];
    expect(saved!.kind, 'pmmp');
    expect(saved.content, 'pvp=off\n');
  });

  testWidgets('下拉的当前值不在选项表里时会补进去，不把用户的取值改掉', (tester) async {
    // `level-type` 在 Java 表里是文本框，换成 pnx 的 gamemode
    // 更贴题：`settings.language` 是下拉，摆一个不在选项里的语言码
    final fixture = await bootConfig(
      files: {'pnx.yml': 'settings:\n  language: klingon\n'},
    );
    await pumpConfig(tester, fixture);

    expect(find.text('语言'), findsOneWidget);
    // 原样显示那个不认识的取值（而不是回落到第一项）
    expect(find.text('klingon'), findsOneWidget);
  });

  testWidgets('图标卡在 Java 系出现：没有图标时给占位与「导入」', (tester) async {
    final fixture = await bootConfig(files: {'server.properties': 'motd=hi\n'});
    await pumpConfig(tester, fixture);

    expect(find.text('服务器图标'), findsOneWidget);
    expect(find.text('server-icon.png'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });

  testWidgets('pnx（基岩系）没有图标卡', (tester) async {
    final fixture = await bootConfig(
      files: {'pnx.yml': 'settings:\n  motd: hi\n'},
    );
    await pumpConfig(tester, fixture);

    expect(find.text('服务器图标'), findsNothing);
    expect(find.text('导入'), findsNothing);
  });

  testWidgets('已经有图标：画出来，按钮变成「更换」', (tester) async {
    // 用一张**真的** 64×64 PNG（假后端只会从真的图标文件里读出来这种东西）
    final icon = await tester.runAsync(
      () => paintPng(64, 64, (canvas) {
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 64, 64),
          ui.Paint()..color = const Color(0xFF00AA00),
        );
      }),
    );
    final fixture = await bootConfig(
      files: {'server.properties': 'motd=hi\n'},
      icon: icon,
    );
    await pumpConfig(tester, fixture);

    expect(find.text('更换'), findsOneWidget);
    expect(find.text('导入'), findsNothing);
    // 有图标就画 `Image.memory`，不再显示占位图标
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
  });
}

// ══════════════════════════════════════════════════════════════════════════
// 图标：裁剪数学与编解码
// ══════════════════════════════════════════════════════════════════════════

/// 造一张 PNG（真走 `dart:ui` 的编码器，不是手拼字节）。
Future<Uint8List> paintPng(
  int width,
  int height,
  void Function(ui.Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// 读 PNG 里某个像素的 RGBA。
Future<List<int>> pixelAt(Uint8List png, int x, int y) async {
  final decoded = await decodeImage(png);
  final image = decoded!.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final at = (y * image.width + x) * 4;
    return [bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]];
  } finally {
    image.dispose();
  }
}

void _iconImageTests() {
  group('裁剪框落在原图哪里（纯计算）', () {
    test('图片正好填满框：裁的就是整张图', () {
      final rect = iconSourceRect(
        imageWidth: 100,
        imageHeight: 100,
        cropBox: 300,
        zoom: 3,
        pan: Offset.zero,
      );
      expect(rect, const Rect.fromLTWH(0, 0, 100, 100));
    });

    test('放大后裁的是中间那一块', () {
      // 100×100 的图放大 6 倍放进 300 的框 → 可视区域是中间 50×50
      final rect = iconSourceRect(
        imageWidth: 100,
        imageHeight: 100,
        cropBox: 300,
        zoom: 6,
        pan: Offset.zero,
      );
      expect(rect, const Rect.fromLTWH(25, 25, 50, 50));
    });

    test('平移到头也不会越出图外（越界会裁到透明像素，图标边上多一圈黑边）', () {
      for (final pan in const [Offset(-9999, 0), Offset(9999, 0)]) {
        final rect = iconSourceRect(
          imageWidth: 100,
          imageHeight: 200,
          cropBox: 300,
          zoom: 3,
          pan: pan,
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(100));
        expect(rect.bottom, lessThanOrEqualTo(200));
        expect(rect.width, rect.height, reason: '裁剪框是方的');
      }
    });
  });

  testWidgets('解码：真 PNG 认得出尺寸，垃圾字节返回 null', (tester) async {
    await tester.runAsync(() async {
      final png = await paintPng(120, 80, (canvas) {
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 120, 80),
          ui.Paint()..color = const Color(0xFF00FF00),
        );
      });

      final decoded = await decodeImage(png);
      expect(decoded, isNotNull);
      expect(decoded!.width, 120);
      expect(decoded.height, 80);
      decoded.dispose();

      expect(await decodeImage(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  testWidgets('裁剪 = 真的取出那块像素 + 缩到 64×64 PNG', (tester) async {
    await tester.runAsync(() async {
      // 左半红、右半蓝的 128×128
      final source = await paintPng(128, 128, (canvas) {
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 64, 128),
          ui.Paint()..color = const Color(0xFFFF0000),
        );
        canvas.drawRect(
          const ui.Rect.fromLTWH(64, 0, 64, 128),
          ui.Paint()..color = const Color(0xFF0000FF),
        );
      });
      final decoded = (await decodeImage(source))!;

      final left = await encodeIconPng(
        decoded.image,
        const ui.Rect.fromLTWH(0, 0, 64, 64),
      );
      final right = await encodeIconPng(
        decoded.image,
        const ui.Rect.fromLTWH(64, 0, 64, 64),
      );
      decoded.dispose();

      // 输出一定是 64×64（daemon 也只认这个尺寸）
      for (final png in [left, right]) {
        final out = await decodeImage(png);
        expect(out!.width, kIconSide);
        expect(out.height, kIconSide);
        out.dispose();
      }

      // 左半裁出来是红的、右半是蓝的 —— 说明 rect 真被当成源区域了
      expect(await pixelAt(left, 32, 32), [255, 0, 0, 255]);
      expect(await pixelAt(right, 32, 32), [0, 0, 255, 255]);
    });
  });
}

// ══════════════════════════════════════════════════════════════════════════
// 图标：裁剪页
// ══════════════════════════════════════════════════════════════════════════

void _iconPageTests() {
  /// 推进若干帧（**不能用 `pumpAndSettle`**：保存时那个转圈是无限动画，
  /// settle 会一直等到超时）。
  Future<void> frames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('裁剪页：解码成功后给出确认按钮与拖动提示', (tester) async {
    final source = (await tester.runAsync(
      () => paintPng(300, 300, (canvas) {
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 300, 300),
          ui.Paint()..color = const Color(0xFF3366CC),
        );
      }),
    ))!;

    await tester.pumpWidget(MaterialApp(home: IconCropPage(imageBytes: source)));
    // 解码走的是引擎的真异步：放它跑完，再泵一帧把 setState 画出来
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await frames(tester);

    expect(find.text('裁剪图标'), findsOneWidget);
    expect(find.text('拖动调整位置，双指缩放'), findsOneWidget);
    expect(find.byKey(const Key('icon_crop_confirm')), findsOneWidget);
  });

  testWidgets('裁剪页：确认后回一份 64×64 的 PNG', (tester) async {
    final source = (await tester.runAsync(
      () => paintPng(300, 300, (canvas) {
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 300, 300),
          ui.Paint()..color = const Color(0xFF3366CC),
        );
      }),
    ))!;

    Uint8List? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                // 从一个宿主页 push 进去，好拿到 pop 回来的字节
                onPressed: () async {
                  result = await Navigator.of(context).push<Uint8List>(
                    MaterialPageRoute(
                      builder: (_) => IconCropPage(imageBytes: source),
                    ),
                  );
                },
                child: const Text('打开裁剪'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开裁剪'));
    await frames(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await frames(tester);

    await tester.tap(find.byKey(const Key('icon_crop_confirm')));
    // 裁剪（drawImageRect + PNG 编码）也是真异步
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await frames(tester);

    expect(result, isNotNull, reason: '确认裁剪应当回一份 PNG');
    // 尺寸必须是 64×64 —— daemon 那边也只认这个
    final decoded = await tester.runAsync(() => decodeImage(result!));
    expect(decoded!.width, kIconSide);
    expect(decoded.height, kIconSide);
    decoded.dispose();
  });

  testWidgets('裁剪页：不是图片就报错，不给确认按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IconCropPage(
          imageBytes: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await frames(tester);

    expect(find.text('无法解码图片'), findsOneWidget);
    expect(find.byKey(const Key('icon_crop_confirm')), findsNothing);
  });
}

void main() {
  _parserTests();
  _iconImageTests();
  _pageTests();
  _iconPageTests();
}
