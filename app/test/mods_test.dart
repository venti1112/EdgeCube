import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/mods/mod_download_page.dart';
import 'package:edgecube_app/mods/mods_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

/// 模组与插件页。
///
/// 钉这几件事：列表怎么呈现（元数据来自 daemon，读不出来的退回文件名）、
/// 「目录不存在就不显示标签」这条规矩、启停与删除真的发出对应的调用、
/// 更新检查的结果怎么落到行上，以及下载那条路（搜索 → 版本页 → 提交
/// `mods-install`）。
///
/// **不在这里重演 daemon 侧的判断**（jar 元数据解析、sha1 反查、目录选择
/// 规则）—— 那些已经由 daemon 的单测与 `framework.rs` 的端到端用例钉住了。

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

/// `mods.sources` 的返回：筛选器的唯一出处。
Map<String, Object?> _sources() => {
  'sources': [
    {
      'id': 'modrinth',
      'name': 'Modrinth',
      'url': 'https://modrinth.com',
      'sorts': ['relevance', 'downloads'],
    },
  ],
  'project_types': [
    {
      'id': 'mod',
      'name': '模组',
      'description': '装到 mods/',
      'dir': 'mods',
      'loaders': ['fabric', 'neoforge'],
    },
    {
      'id': 'plugin',
      'name': '插件',
      'description': '装到 plugins/',
      'dir': 'plugins',
      'loaders': ['paper', 'spigot'],
    },
  ],
  'loaders': [
    {'id': 'fabric', 'name': 'Fabric'},
    {'id': 'neoforge', 'name': 'NeoForge'},
    {'id': 'paper', 'name': 'Paper'},
  ],
  'sorts': [
    {'id': 'relevance', 'name': '相关度'},
    {'id': 'downloads', 'name': '下载量'},
  ],
  'file_ext': 'jar',
  'disabled_suffix': '.disabled',
};

/// `mods.tags`：游戏版本（**带类型**，上游顺序是「新的在前」）+ 该类型可筛的加载器。
///
/// 加载器**按项目类型分成两张表**（daemon 的 `PROJECT_TYPES[].loaders`）——
/// 插件那一栏绝不能出现 Fabric / Forge。
Map<String, Object?> _tags({String projectType = 'mod'}) => {
  'project_type': projectType,
  // 故意把快照放在前面：菜单里应当由 App 把正式版挑到前面
  'game_versions': [
    {'version': '26.4-snapshot-1', 'version_type': 'snapshot'},
    {'version': '1.21.8', 'version_type': 'release'},
    {'version': '1.21.7', 'version_type': 'release'},
  ],
  'loaders': projectType == 'plugin'
      ? [
          {'id': 'paper', 'name': 'Paper'},
          {'id': 'spigot', 'name': 'Spigot'},
          {'id': 'bukkit', 'name': 'Bukkit'},
          {'id': 'bungeecord', 'name': 'BungeeCord'},
          {'id': 'velocity', 'name': 'Velocity'},
          {'id': 'waterfall', 'name': 'Waterfall'},
          {'id': 'folia', 'name': 'Folia'},
          {'id': 'purpur', 'name': 'Purpur'},
        ]
      : [
          {'id': 'fabric', 'name': 'Fabric'},
          {'id': 'forge', 'name': 'Forge'},
          {'id': 'quilt', 'name': 'Quilt'},
          {'id': 'neoforge', 'name': 'NeoForge'},
        ],
};

/// `mods.installed` 的返回。
///
/// 两个目录都给出来（带 `exists` 标），**由前端决定要不要显示标签** ——
/// 这正是 daemon 把 `exists` 放进响应里的原因。
/// `mods.installed` 的返回。
///
/// 两个目录都给出来（带 `exists` 标），**由前端决定要不要显示标签** ——
/// 这正是 daemon 把 `exists` 放进响应里的原因。
///
/// [pmmp] 为真时插件那一栏用 `.phar`（PocketMine），与 daemon 的判定一致。
/// [clientOnly] 为真时多一个 `environment: client` 的模组，用来看「清理客户端模组」。
Map<String, Object?> _installed({
  bool withMods = true,
  bool withPlugins = false,
  bool pmmp = false,
  bool clientOnly = false,
}) {
  final modFiles = <Object?>[
    if (withMods)
      {
        'file_name': 'sodium.jar',
        'base_name': 'sodium.jar',
        'enabled': true,
        'size': 1621285,
        'modified_ms': 1700000000000,
        // 名字/版本/描述/加载器/侧别都是从 jar 里读出来的（daemon 做的）
        'meta': {
          'id': 'sodium',
          'name': 'Sodium',
          'version': '0.7.3',
          'description': 'A rendering engine replacement.',
          'authors': 'jellysquid3',
          'url': 'https://caffeinemc.net',
          'from': 'fabric.mod.json',
          'loader': 'fabric',
          'environment': 'both',
        },
      },
    if (withMods)
      {
        'file_name': 'broken.jar',
        'base_name': 'broken.jar',
        'enabled': true,
        'size': 100,
        'modified_ms': 1700000000000,
        // 读不出元数据的 jar 照样列出来，meta 为 null → 副行退回文件大小
        'meta': null,
      },
    if (clientOnly)
      {
        'file_name': 'sodium-extra.jar',
        'base_name': 'sodium-extra.jar',
        'enabled': true,
        'size': 900,
        'modified_ms': 1700000000000,
        'meta': {
          'id': 'sodium-extra',
          'name': 'Sodium Extra',
          'version': '0.6.0',
          'description': 'client only addon',
          'authors': null,
          'url': null,
          'from': 'fabric.mod.json',
          'loader': 'fabric',
          // 客户端专属 —— 「清理客户端模组」唯一的判据
          'environment': 'client',
        },
      },
  ];

  final pluginFile = pmmp
      ? {
          'file_name': 'EconomyAPI.phar.disabled',
          'base_name': 'EconomyAPI.phar',
          'enabled': false,
          'size': 4096,
          'modified_ms': 1700000000000,
          'meta': {
            'id': 'EconomyAPI',
            'name': 'EconomyAPI',
            'version': '5.0.0',
            'description': '经济系统',
            'authors': 'onebone',
            'url': null,
            'from': 'plugin.yml',
            'loader': 'pocketmine',
            'environment': 'unknown',
          },
        }
      : {
          'file_name': 'luckperms.jar.disabled',
          'base_name': 'luckperms.jar',
          'enabled': false,
          'size': 500,
          'modified_ms': 1700000000000,
          'meta': {
            'id': 'LuckPerms',
            'name': 'LuckPerms',
            'version': '5.4.102',
            'description': '权限管理',
            'authors': 'Luck',
            'url': 'https://luckperms.net',
            'from': 'plugin.yml',
            // 插件系统一是 bukkit 那一档（前端显示成「Plugin」）
            'loader': 'bukkit',
            'environment': 'unknown',
          },
        };

  return {
    'instance_id': 'i1',
    // 实例是不是 PocketMine —— 判断在 daemon
    'pmmp': pmmp,
    'dirs': [
      {
        'project_type': 'mod',
        'dir': 'mods',
        'exists': withMods,
        'count': modFiles.length,
        'files': modFiles,
      },
      {
        'project_type': 'plugin',
        'dir': 'plugins',
        'exists': withPlugins,
        'count': withPlugins ? 1 : 0,
        'files': withPlugins ? [pluginFile] : <Object?>[],
      },
    ],
  };
}

/// 一条搜索命中（形状照 daemon 的中立模型）。
Map<String, Object?> _hit({
  String title = 'Sodium',
  String projectId = 'AANobbMI',
  String? serverSide = 'optional',
}) => {
  'source': 'modrinth',
  'project_id': projectId,
  'slug': 'sodium',
  'title': title,
  'description': 'A high-performance rendering engine replacement.',
  'author': 'jellysquid3',
  // 测试里不给图标 URL：`Image.network` 在 widget 测试里会去打真网络
  'icon_url': null,
  'downloads': 233640873,
  'follows': 41248,
  'categories': ['fabric', 'optimization'],
  'project_type': 'mod',
  'loaders': ['fabric'],
  'latest_version': 'NM9w06Kr',
  'server_side': serverSide,
  'page_url': 'https://modrinth.com/mod/sodium',
};

Map<String, Object?> _searchPage({List<Object?>? hits}) => {
  'source': 'modrinth',
  'source_name': 'Modrinth',
  'query': 'sodium',
  'project_type': 'mod',
  'loader': null,
  'game_version': null,
  'sort': 'relevance',
  'offset': 0,
  'limit': 20,
  'total': 2,
  'has_more': false,
  'hits': hits ?? [_hit(), _hit(title: 'Sodium Extra', projectId: 'PtjYWJkn')],
};

Map<String, Object?> _file(String name) => {
  'url': 'https://cdn.modrinth.com/data/AANobbMI/versions/v1/$name',
  'filename': name,
  'size': 1621285,
  'sha1': 'c9ed2b00385ea191e81ea4da51c008755fe90a26',
  'primary': true,
};

Map<String, Object?> _version({
  required String id,
  required String versionNumber,
  String kind = 'release',
  List<Object?> dependencies = const [],
}) => {
  'id': id,
  'project_id': 'AANobbMI',
  'name': 'Sodium $versionNumber',
  'version_number': versionNumber,
  'version_type': kind,
  'game_versions': ['1.21.8'],
  'loaders': ['fabric'],
  'date_published': '2025-11-10T18:49:39.796580Z',
  'files': [_file('sodium-$versionNumber.jar')],
  'dependencies': dependencies,
};

Map<String, Object?> _versions() => {
  'project_id': 'AANobbMI',
  'loader': null,
  'game_version': null,
  'versions': [
    _version(id: 'v1', versionNumber: '0.7.3'),
    _version(
      id: 'v2',
      versionNumber: '0.7.2',
      kind: 'beta',
      dependencies: [
        {
          'project_id': 'P7dR8mSH',
          'version_id': null,
          'file_name': 'fabric-api-0.1.jar',
          'dependency_type': 'required',
        },
      ],
    ),
  ],
};

Map<String, Object?> _updates() => {
  'instance_id': 'i1',
  'loader': null,
  'game_version': null,
  'checked': 2,
  'truncated': false,
  'updates': [
    {
      'file_name': 'sodium.jar',
      'sha1': 'c9ed2b00385ea191e81ea4da51c008755fe90a26',
      'known': true,
      'has_update': true,
      'latest': _version(id: 'v3', versionNumber: '0.7.4'),
    },
    {
      // 手放进去的 jar，上游不认得 —— 界面上不该说它有更新
      'file_name': 'broken.jar',
      'sha1': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'known': false,
      'has_update': false,
      'latest': null,
    },
  ],
};

/// `task.submit` 的返回：一份刚提交、正在跑的任务（形状与 `task.get` 一致）。
Map<String, Object?> _runningTask(String id) => {
  'id': id,
  'flow': 'mods-install',
  'title': '下载并安装模组 / 插件',
  'params': const <String, Object?>{},
  'state': 'running',
  'current_step': 'download',
  'steps': [
    {
      'name': 'plan',
      'title': '解析下载地址',
      'status': 'completed',
      'error': null,
      'progress': null,
    },
    {
      'name': 'download',
      'title': '下载并安装',
      'status': 'running',
      'error': null,
      'progress': null,
    },
  ],
  'error': null,
  'rolled_back': false,
  'created_at_ms': 1700000000000,
  'started_at_ms': 1700000000001,
  'finished_at_ms': null,
  'total_duration_ms': null,
};

Future<
  ({
    ProviderContainer container,
    FakeTransportFactory transports,
    FakeInstanceStore instances,
  })
>
_boot({
  Map<String, Object?> responses = const {},
  Map<String, Object? Function(Map<String, dynamic> params)>? responders,
  bool withInstance = true,
  bool withMods = true,
  bool withPlugins = false,
  bool pmmp = false,
  bool clientOnly = false,
  String tagsProjectType = 'mod',
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final instances = FakeInstanceStore();
  if (withInstance) {
    // 实例 id 写死成 i1，与假数据里的 `instance_id` 对齐，断言里就不必到处替换
    instances.instances['i1'] = {
      'id': 'i1',
      'name': '模组测试服',
      'startup_command': 'java -jar server.jar nogui',
      'compat_mode': false,
      'auto_restart_on_exit': false,
      'path': null,
      'line_ending': '\n',
      'created_at_ms': 1700000000000,
      'updated_at_ms': 1700000000000,
    };
    instances.selected = 'i1';
  }

  final transports = FakeTransportFactory(
    instances: instances,
    responses: {
      'mods.sources': _sources(),
      'mods.tags': _tags(projectType: tagsProjectType),
      'mods.installed': _installed(
        withMods: withMods,
        withPlugins: withPlugins,
        pmmp: pmmp,
        clientOnly: clientOnly,
      ),
      // 列表左侧的图标走这条（按 sha1 对回上游项目）；假数据只给 sodium 一个有图标的
      'mods.match_projects': {
        'instance_id': 'i1',
        'matched': 1,
        'truncated': false,
        'matches': [
          {
            'file_name': 'sodium.jar',
            'sha1': 'c9ed2b00385ea191e81ea4da51c008755fe90a26',
            'known': true,
            'project': {
              'project_id': 'AANobbMI',
              'slug': 'sodium',
              'title': 'Sodium',
              'icon_url': null,
              'project_type': 'mod',
              'page_url': 'https://modrinth.com/mod/sodium',
            },
          },
        ],
      },
      'mods.search': _searchPage(),
      'mods.versions': _versions(),
      'mods.check_updates': _updates(),
      'mods.set_enabled': {
        'instance_id': 'i1',
        'project_type': 'mod',
        'file_name': 'sodium.jar',
        'enabled': false,
      },
      'mods.remove': {
        'instance_id': 'i1',
        'project_type': 'mod',
        'file_name': 'sodium.jar',
      },
      // 下载页的队列横幅会拉 `download.list`；默认给空队列，避免假传输未注册报错。
      'download.list': {'tasks': []},
      ...responses,
    },
    responders: responders,
  );

  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: transports.call,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  return (container: container, transports: transports, instances: instances);
}

/// 推几帧把异步 RPC、路由转场与菜单/对话框动画走完。
///
/// **不能用 `pumpAndSettle`**：安装进度页上的进度环是无限动画，settle 会一直
/// 等下去（项目里其它测试也是这么绕的，见 `download_wizard_test.dart`）。
Future<void> _flush(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    ),
  );
  await _flush(tester);
}

/// 发出去过几次某个方法。
int _callsTo(FakeTransportFactory transports, String method) => transports
    .latest
    .sent
    .where((envelope) => envelope['method'] == method)
    .length;

/// 最后一次某方法的参数（没发过就是 `null`）。
Map<String, dynamic>? _lastParams(
  FakeTransportFactory transports,
  String method,
) {
  final calls = transports.latest.sent
      .where((envelope) => envelope['method'] == method)
      .toList(growable: false);
  if (calls.isEmpty) return null;
  return (calls.last['params'] as Map).cast<String, dynamic>();
}

/// 找「主行是这个文本的那张卡」。
Finder _cardOf(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card));

void main() {
  testWidgets('标签由目录决定：只有 mods → 两个标签，标题是「模组/插件管理」', (tester) async {
    final boot = await _boot(withMods: true, withPlugins: false);
    await _pump(tester, boot.container, const ModsPage());

    // 页面标题 = 模组/插件管理
    expect(find.text('模组/插件管理'), findsOneWidget);
    // 两个目录各出「管理 + 下载」，只有 mods 时就是这两个
    expect(find.text('模组管理'), findsOneWidget);
    expect(find.text('模组下载'), findsOneWidget);
    expect(find.text('插件管理'), findsNothing);
    expect(find.text('插件下载'), findsNothing);
    // 顶行是「共 N 项」
    expect(find.text('共 2 项'), findsOneWidget);
  });

  testWidgets('两个目录都在 → 四个标签', (tester) async {
    final boot = await _boot(withMods: true, withPlugins: true);
    await _pump(tester, boot.container, const ModsPage());

    for (final label in ['插件管理', '插件下载', '模组管理', '模组下载']) {
      expect(find.text(label), findsOneWidget, reason: '缺标签 $label');
    }
  });

  testWidgets('一个目录都没有 → 空态（固定两句）', (tester) async {
    final boot = await _boot(withMods: false, withPlugins: false);
    await _pump(tester, boot.container, const ModsPage());

    expect(find.text('暂无模组/插件目录'), findsOneWidget);
    expect(find.text('当前实例目录下未发现 plugins 或 mods 文件夹。'), findsOneWidget);
    // 目录存不存在要先问 daemon
    expect(_callsTo(boot.transports, 'mods.installed'), greaterThan(0));
  });

  testWidgets('PocketMine 实例：插件那一栏的标签是「Poggit 插件」', (tester) async {
    final boot = await _boot(withMods: false, withPlugins: true, pmmp: true);
    await _pump(tester, boot.container, const ModsPage());

    expect(find.text('Poggit 插件'), findsOneWidget);
    expect(find.text('插件下载'), findsNothing);
    // `.phar` 也要被当成插件列出来（与 daemon 的后缀表一致）
    expect(find.text('EconomyAPI'), findsOneWidget);
  });

  testWidgets('列表项：主行是元数据名字，副行是「版本 · 加载器」+ 描述', (tester) async {
    final boot = await _boot();
    await _pump(tester, boot.container, const ModsPage());

    expect(find.text('Sodium'), findsOneWidget);
    // 副行 = 版本号 · 加载器标签，有描述再换一行（`bukkit` 显示成「Plugin」）
    expect(
      find.textContaining('0.7.3 · Fabric'),
      findsOneWidget,
      reason: '副行是「版本 · 加载器」',
    );
    expect(find.textContaining('A rendering engine replacement.'), findsOneWidget);

    // 读不出元数据的 jar：主行退回文件名，副行退回**文件大小**
    expect(find.text('broken.jar'), findsOneWidget);
    expect(find.text('100 B'), findsOneWidget, reason: '没有元数据时副行是文件大小');
  });

  testWidgets('禁用图标 → 确认框 → mods.set_enabled（参数按行给）', (tester) async {
    final boot = await _boot();
    await _pump(tester, boot.container, const ModsPage());

    // 行上的开关是**独立的图标按钮**，不是 Switch
    expect(find.byType(Switch), findsNothing);
    await tester.tap(
      find.descendant(
        of: _cardOf('Sodium'),
        matching: find.byTooltip('禁用'),
      ),
    );
    await _flush(tester);

    // 有确认框
    expect(find.text('确认禁用'), findsOneWidget);
    expect(find.text('sodium.jar'), findsOneWidget);
    expect(_callsTo(boot.transports, 'mods.set_enabled'), 0, reason: '确认之前不该改名');

    await tester.tap(find.widgetWithText(FilledButton, '禁用'));
    await _flush(tester);

    final params = _lastParams(boot.transports, 'mods.set_enabled');
    expect(params, isNotNull);
    expect(params!['instance_id'], 'i1');
    // 项目类型决定它落在 mods/ 还是 plugins/，一定不能传错
    expect(params['project_type'], 'mod');
    expect(params['file_name'], 'sodium.jar');
    expect(params['enabled'], isFalse);
  });

  testWidgets('删除：确认框带文件名，确认后才调 mods.remove', (tester) async {
    final boot = await _boot();
    await _pump(tester, boot.container, const ModsPage());

    await tester.tap(
      find.descendant(
        of: _cardOf('Sodium'),
        matching: find.byTooltip('删除'),
      ),
    );
    await _flush(tester);

    // 删除确认 = 确定删除「{name}」吗？
    expect(find.text('确定删除「sodium.jar」吗？'), findsOneWidget);
    expect(_callsTo(boot.transports, 'mods.remove'), 0, reason: '确认之前不该删');

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _flush(tester);

    final params = _lastParams(boot.transports, 'mods.remove');
    expect(params, isNotNull);
    expect(params!['file_name'], 'sodium.jar');
    expect(params['project_type'], 'mod');
  });

  testWidgets('删除：取消就不删（确认框不是摆设）', (tester) async {
    final boot = await _boot();
    await _pump(tester, boot.container, const ModsPage());

    await tester.tap(
      find.descendant(
        of: _cardOf('Sodium'),
        matching: find.byTooltip('删除'),
      ),
    );
    await _flush(tester);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await _flush(tester);

    expect(_callsTo(boot.transports, 'mods.remove'), 0);
  });

  testWidgets('检查更新：出「N 个模组可更新」横幅，行上多出更新按钮', (tester) async {
    final boot = await _boot();
    await _pump(tester, boot.container, const ModsPage());

    // 还没查过时既没有横幅也没有更新按钮
    expect(find.textContaining('个模组可更新'), findsNothing);
    expect(find.byTooltip('更新'), findsNothing);

    await tester.tap(find.byTooltip('检查更新'));
    await _flush(tester);

    final params = _lastParams(boot.transports, 'mods.check_updates');
    expect(params, isNotNull);
    expect(params!['project_type'], 'mod');

    // 更新提示文案 = {count} 个模组可更新。
    // **两处都用这一句**：横幅一处、按钮点完的 SnackBar 一处，
    // 所以这里命中 2 个才是对的。
    expect(find.text('1 个模组可更新'), findsNWidgets(2));
    expect(find.text('选择更新'), findsOneWidget);
    // 有更新那一行才有更新按钮（broken.jar 上游不认得，它那行没有）
    expect(
      find.descendant(of: _cardOf('Sodium'), matching: find.byTooltip('更新')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _cardOf('broken.jar'), matching: find.byTooltip('更新')),
      findsNothing,
    );
  });

  testWidgets('清理客户端模组：没有可识别的 → 只提示，不弹窗', (tester) async {
    final boot = await _boot();
    await _pump(tester, boot.container, const ModsPage());

    await tester.tap(find.byTooltip('清理客户端模组'));
    await _flush(tester);

    expect(find.text('未找到可识别的客户端模组'), findsOneWidget);
    expect(find.text('清理客户端模组'), findsNothing, reason: '没有就不该弹窗');
  });

  testWidgets('清理客户端模组：列出来、默认全选，移除走 mods.remove', (tester) async {
    final boot = await _boot(clientOnly: true);
    await _pump(tester, boot.container, const ModsPage());

    // 只有 environment=client 的那个进列表（判定在 daemon，前端只看 isClientOnly）
    expect(find.text('Sodium Extra'), findsOneWidget);

    await tester.tap(find.byTooltip('清理客户端模组'));
    await _flush(tester);

    expect(find.text('清理客户端模组'), findsOneWidget);
    expect(
      find.text('检测到 1 个客户端专属模组，它们在服务端运行会导致崩溃，建议移除。'),
      findsOneWidget,
    );
    // 默认全选 → 按钮显示「取消全选」
    expect(find.text('取消全选'), findsOneWidget);
    expect(_callsTo(boot.transports, 'mods.remove'), 0);

    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await _flush(tester);

    final params = _lastParams(boot.transports, 'mods.remove');
    expect(params, isNotNull);
    expect(params!['file_name'], 'sodium-extra.jar');
    expect(params['project_type'], 'mod');
  });

  testWidgets('每次进页面都重扫目录：新建目录后回来就能看到', (tester) async {
    var calls = 0;
    final boot = await _boot(
      responders: {
        'mods.installed': (params) {
          calls++;
          // 第一次进来：plugins/ 与 mods/ 都还没建；之后再问就已经建好了。
          // 这就是「在别处新建了目录，回到这一页」的那个场景。
          return calls == 1
              ? _installed(withMods: false, withPlugins: false)
              : _installed(withMods: true, withPlugins: false);
        },
      },
    );

    await _pump(tester, boot.container, const ModsPage());
    expect(find.text('暂无模组/插件目录'), findsOneWidget);

    // 「离开这一页」：换成别的 widget（等价于把 /mods 从栈上弹掉）
    await _pump(tester, boot.container, const SizedBox.shrink());
    expect(find.text('暂无模组/插件目录'), findsNothing);

    // 再进来：必须重扫
    await _pump(tester, boot.container, const ModsPage());
    expect(
      find.text('暂无模组/插件目录'),
      findsNothing,
      reason: '进页面重扫之后目录已经存在了，不该还停在空态',
    );
    expect(find.text('模组管理'), findsOneWidget);
    expect(calls, 2, reason: '每次进页面都该重新问一次 daemon');
  });

  testWidgets('没有实例时给空态，不发 mods.installed', (tester) async {
    final boot = await _boot(withInstance: false);
    await _pump(tester, boot.container, const ModsPage());

    expect(find.text('还没有实例'), findsOneWidget);
    expect(_callsTo(boot.transports, 'mods.installed'), 0);
  });

  testWidgets('下载页：搜索框与搜索按钮，进页自动出结果', (tester) async {
    final boot = await _boot(
      responders: {
        // 进页按默认排序自动搜一次，这里把两条结果换成自定义的（含一条别的名字）
        'mods.search': (params) => _searchPage(
          hits: [_hit(serverSide: 'unsupported'), _hit(title: 'Krypton')],
        ),
      },
    );
    await _pump(
      tester,
      boot.container,
      const ModDownloadPage(projectType: 'mod', instanceId: 'i1'),
    );
    await _flush(tester);

    // 标题 + 搜索行（输入框 + 「搜索」按钮）
    expect(find.text('下载模组'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '搜索'), findsOneWidget);
    // 自动搜出来的结果卡
    expect(find.text('Sodium'), findsOneWidget);
    expect(find.text('Krypton'), findsOneWidget);

    // 搜的确实是这个类型、从头开始
    final params = _lastParams(boot.transports, 'mods.search');
    expect(params, isNotNull);
    expect(params!['project_type'], 'mod');
    expect(params['offset'], 0);
  });

  testWidgets('插件下载：加载器菜单只列插件加载器，不出现模组加载器', (tester) async {
    // 用户报的 bug：插件页的加载器菜单里出现了 fabric / forge。
    // 根因是菜单取了「全平台合并的总表」而不是该类型自己的那一张。
    final boot = await _boot(tagsProjectType: 'plugin');
    await _pump(
      tester,
      boot.container,
      const ModDownloadPage(projectType: 'plugin', instanceId: 'i1'),
    );
    await _flush(tester);

    await tester.tap(find.textContaining('加载器: '));
    await _flush(tester);

    // Modrinth 插件加载器表
    for (final label in [
      'Paper',
      'Spigot',
      'Bukkit',
      'Bungeecord',
      'Velocity',
      'Waterfall',
      'Folia',
      'Purpur',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '插件加载器表里应当有 $label');
    }
    expect(find.text('任意'), findsOneWidget);
    // ⚠️ 模组加载器一个都不许出现
    for (final label in ['Fabric', 'Forge', 'Quilt', 'Neoforge']) {
      expect(
        find.text(label),
        findsNothing,
        reason: '插件那一栏不该出现模组加载器 $label',
      );
    }
  });

  testWidgets('游戏版本菜单：正式版排在前面，快照带类型副标题', (tester) async {
    final boot = await _boot();
    await _pump(
      tester,
      boot.container,
      const ModDownloadPage(projectType: 'mod', instanceId: 'i1'),
    );
    await _flush(tester);

    await tester.tap(find.textContaining('游戏版本: '));
    await _flush(tester);

    // daemon 给的是「新的在前」的混合顺序，分组与排序由 App 做
    final release = tester.getTopLeft(find.text('1.21.8')).dy;
    final snapshot = tester.getTopLeft(find.text('26.4-snapshot-1')).dy;
    expect(release, lessThan(snapshot), reason: '正式版要排在快照前面');
    // 非正式版的副标题写它的类型
    expect(find.text('snapshot'), findsOneWidget);
  });

  testWidgets('游戏版本兼容旧 daemon 的纯字符串数组（不再只剩「任意」）', (tester) async {
    // 真踩过：daemon 把 `game_versions` 的元素从字符串改成了对象，
    // 旧 daemon 一跑，前端一条都解析不出来 → 菜单里只剩「任意」。
    final boot = await _boot(
      responders: {
        'mods.tags': (params) => {
          'project_type': 'mod',
          // 旧形状：纯字符串，没有 version_type
          'game_versions': ['1.21.8', '1.21.7'],
          'loaders': [
            {'id': 'fabric', 'name': 'Fabric'},
          ],
        },
      },
    );
    await _pump(
      tester,
      boot.container,
      const ModDownloadPage(projectType: 'mod', instanceId: 'i1'),
    );
    await _flush(tester);

    await tester.tap(find.textContaining('游戏版本: '));
    await _flush(tester);

    expect(find.text('1.21.8'), findsOneWidget);
    expect(find.text('1.21.7'), findsOneWidget);
  });

  testWidgets('游戏版本形状对不上时，筛选条上直接说「需重启守护进程」', (tester) async {
    final boot = await _boot(
      responders: {
        'mods.tags': (params) => {
          'project_type': 'mod',
          // 给了东西但一个 `version` 都没有 —— 前端认不出来
          'game_versions': [
            {'kind': 'release'},
          ],
          'loaders': [
            {'id': 'fabric', 'name': 'Fabric'},
          ],
        },
      },
    );
    await _pump(
      tester,
      boot.container,
      const ModDownloadPage(projectType: 'mod', instanceId: 'i1'),
    );
    await _flush(tester);

    // 静默降级成「只有任意」是最难查的，所以要直接写在筛选条上
    expect(find.textContaining('需重启守护进程'), findsOneWidget);
  });

  testWidgets('版本选择弹层：点版本进详情，下载此版本提交 mods-install',
      (tester) async {
    final boot = await _boot(
      responders: {
        'task.submit': (params) => _runningTask('t1'),
      },
    );
    await _pump(
      tester,
      boot.container,
      const ModDownloadPage(projectType: 'mod', instanceId: 'i1'),
    );
    await _flush(tester);

    await tester.tap(find.text('Sodium'));
    await _flush(tester);

    // 点结果卡 → 版本选择弹层（mods.versions 按 project_id 拉）
    final versionParams = _lastParams(boot.transports, 'mods.versions');
    expect(versionParams, isNotNull);
    expect(versionParams!['project_id'], 'AANobbMI');

    // 版本行：正式版、测试版都列出，且带上中文标签与前置数
    expect(find.textContaining('0.7.3'), findsWidgets);
    expect(find.text('正式版'), findsOneWidget);
    expect(find.text('测试版'), findsOneWidget);
    expect(find.textContaining('个前置'), findsOneWidget);

    // 点版本进详情
    await tester.tap(find.textContaining('0.7.3').first);
    await _flush(tester);

    expect(find.text('版本详情'), findsOneWidget);

    // 详情页 body 是 ListView，按钮在底部，滚到可见再断言/点击
    await tester.scrollUntilVisible(
      find.text('下载此版本'),
      100.0,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('下载此版本'), findsOneWidget);

    await tester.tap(find.text('下载此版本'));
    await _flush(tester);

    // 提交 mods-install，参数落到实例 / 项目 / 版本
    final params = _lastParams(boot.transports, 'task.submit');
    expect(params, isNotNull);
    expect(params!['flow'], 'mods-install');
    final inner = (params['params'] as Map).cast<String, dynamic>();
    expect(inner['instance_id'], 'i1');
    expect(inner['project_id'], 'AANobbMI');
    expect(inner['project_type'], 'mod');
    expect(inner['version_id'], 'v1');

    // 提交成功后由父页面弹 SnackBar「已加入下载队列」
    expect(find.text('已加入下载队列'), findsOneWidget);
  });

  testWidgets('下载队列横幅：读 daemon 队列，清除/取消按约定置灰',
      (tester) async {
    final boot = await _boot(
      responders: {
        'download.list': (params) => {
          'tasks': [
            {
              'id': 'd1',
              'state': 'downloading',
              'instance_id': 'i1',
              'filename': 'sodium.jar',
              'total_size': 1000,
              'completed_size': 500,
            },
          ],
        },
      },
    );
    await _pump(
      tester,
      boot.container,
      const ModDownloadPage(projectType: 'mod', instanceId: 'i1'),
    );
    await _flush(tester);

    // 横幅出现（只显示属于 i1 的任务）
    expect(find.textContaining('sodium.jar'), findsOneWidget);
    // 点开队列详情
    await tester.tap(find.textContaining('sodium.jar'));
    await _flush(tester);

    expect(find.text('下载队列'), findsOneWidget);
    // daemon 的 download 模块暂无 clear / cancel，按约定置灰
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '清除已结束'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '全部取消'))
          .onPressed,
      isNull,
    );
  });
}
