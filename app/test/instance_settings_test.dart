import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/instance/instance_settings_dialog.dart';
import 'package:edgecube_app/instance/models.dart';
import 'package:edgecube_app/instance/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

// ══════════════════════════════════════════════════════════════════════════
// 夹具
// ══════════════════════════════════════════════════════════════════════════

typedef SettingsFixture = ({
  ProviderContainer container,
  FakeInstanceStore store,
  FakeRuntimeStore runtime,
  FakeDaemonTransport transport,
  String id,
  Instance instance,
});

/// 连上假 daemon，并把实例元数据取回来（对话框要一份 [Instance] 才打得开）。
///
/// 三个假后端都得挂上：对话框要读 `runtime.list`（运行环境）、
/// `frp.tunnels.list`（隧道）、`instance.files.list`（服务端 jar 候选）。
/// 少一个都会以 `method_not_found` 失败 —— riverpod 给失败的服务排重试定时器，
/// widget 收尾时撞上「A Timer is still pending」。
Future<SettingsFixture> _connect({
  required FakeInstanceStore store,
  required FakeRuntimeStore runtime,
  required String id,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final factory = FakeTransportFactory(
    instances: store,
    runtime: runtime,
    frp: FakeFrpStore(),
  );
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: factory.call,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  final api = container.read(instanceApiProvider)!;
  return (
    container: container,
    store: store,
    runtime: runtime,
    transport: factory.latest,
    id: id,
    instance: await api.get(id),
  );
}

/// 表单模式的实例：运行环境 + 服务端 jar + 最大内存 + JVM 参数都填好，
/// 没存过启动命令（daemon 那边算出来是表单模式）。
///
/// [plantJar] = false 时**不**往实例目录里放那个 jar —— 验「保存过的
/// 文件已经不在了」时的显示。
Future<SettingsFixture> bootFormSettings({
  String name = '生存服',
  int maxMemory = 2048,
  String customJvmArgs = '-XX:+UseG1GC -XX:MaxGCPauseMillis=100',
  bool plantJar = true,
  bool upnpEnabled = false,
  String upnpProtocol = 'tcp',
  int? upnpExternalPort,
  bool stunEnabled = false,
  bool stunProxyProtocol = false,
  int? stunTargetPort,
}) async {
  final store = FakeInstanceStore();
  final runtime = FakeRuntimeStore();
  final envId = runtime.seedEnv(); // 一个装好的 Zulu JDK 21
  final id = store.seed(
    name: name,
    startupCommand: null,
    runtimeEnvId: envId,
    serverFile: 'server.jar',
    maxMemory: maxMemory,
    customJvmArgs: customJvmArgs,
    upnpEnabled: upnpEnabled,
    upnpProtocol: upnpProtocol,
    upnpExternalPort: upnpExternalPort,
    stunEnabled: stunEnabled,
    stunProxyProtocol: stunProxyProtocol,
    stunTargetPort: stunTargetPort,
  );
  if (plantJar) store.filesFor(id).addFile('server.jar', '假 jar');
  return _connect(store: store, runtime: runtime, id: id);
}

/// 手动模式的实例：只存了一条自己写的启动命令。
Future<SettingsFixture> bootManualSettings({
  String startupCommand = 'python3 main.py',
}) async {
  final store = FakeInstanceStore();
  final runtime = FakeRuntimeStore();
  runtime.seedEnv();
  final id = store.seed(
    name: '脚本服',
    startupCommand: startupCommand,
    manualCommand: true,
  );
  return _connect(store: store, runtime: runtime, id: id);
}

/// 打开发送对话框的宿主页（对话框要一个挂在 ProviderScope 里的 `ref`）。
class _SettingsHost extends ConsumerWidget {
  const _SettingsHost({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: FilledButton(
        key: const Key('open_instance_settings'),
        onPressed: () => showInstanceSettingsDialog(context, ref, instance),
        child: const Text('打开设置'),
      ),
    ),
  );
}

Future<void> openDialog(WidgetTester tester, SettingsFixture fixture) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(home: _SettingsHost(instance: fixture.instance)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open_instance_settings')));
  await tester.pumpAndSettle();
}

/// 发出去的 [method] 调用参数（最后一条）。
Map<String, dynamic> lastCallParams(
  FakeDaemonTransport transport,
  String method,
) {
  final call = transport.sent.lastWhere(
    (envelope) => envelope['type'] == 'call' && envelope['method'] == method,
  );
  return (call['params'] as Map).cast<String, dynamic>();
}

int callCount(FakeDaemonTransport transport, String method) => transport.sent
    .where(
      (envelope) => envelope['type'] == 'call' && envelope['method'] == method,
    )
    .length;

/// 输入框里的文本。
///
/// 不 `find.text`：`hintText` 也挂在树里（淡出但没拆），数字类 hint
/// （如最大内存的 `2048`）会和真实值撞在一起。
String fieldText(WidgetTester tester, Key key) =>
    tester.widget<TextField>(find.byKey(key)).controller!.text;

/// 表单模式那四个控件在不在。
void expectFormVisible({required bool visible}) {
  final matcher = visible ? findsOneWidget : findsNothing;
  expect(
    find.byKey(const Key('settings_instance_runtime_env')),
    matcher,
    reason: '运行环境',
  );
  expect(
    find.byKey(const Key('settings_instance_max_memory')),
    matcher,
    reason: '最大内存',
  );
  expect(
    find.byKey(const Key('settings_instance_server_file')),
    matcher,
    reason: '服务端 jar',
  );
  expect(
    find.byKey(const Key('settings_instance_custom_jvm_args')),
    matcher,
    reason: '自定义 JVM 参数',
  );
}

// ══════════════════════════════════════════════════════════════════════════
// 两条路线：表单（默认）/ 手动
// ══════════════════════════════════════════════════════════════════════════

void main() {
  testWidgets('默认是表单模式：显示那套字段并回填当前值', (tester) async {
    final fixture = await bootFormSettings();
    await openDialog(tester, fixture);

    expectFormVisible(visible: true);
    expect(
      find.byKey(const Key('settings_instance_startup_command')),
      findsNothing,
      reason: '表单模式下不显示命令框',
    );
    // 回填：内存、JVM 参数是输入框；环境与 jar 是下拉的选中项
    expect(fieldText(tester, const Key('settings_instance_max_memory')), '2048');
    expect(
      fieldText(tester, const Key('settings_instance_custom_jvm_args')),
      '-XX:+UseG1GC -XX:MaxGCPauseMillis=100',
    );
    expect(find.text('Zulu JDK · 21'), findsOneWidget, reason: '运行环境的显示名');
    expect(find.text('server.jar'), findsOneWidget, reason: '服务端 jar 的选中项');
  });

  testWidgets('打开「手动命令」收起表单、换成命令框，关掉又回来', (tester) async {
    final fixture = await bootFormSettings();
    await openDialog(tester, fixture);

    await tester.tap(find.byKey(const Key('settings_instance_manual_command')));
    await tester.pumpAndSettle();

    expectFormVisible(visible: false);
    expect(
      find.byKey(const Key('settings_instance_startup_command')),
      findsOneWidget,
    );
    // 表单值只是收起来了，没丢：切回去还在
    await tester.tap(find.byKey(const Key('settings_instance_manual_command')));
    await tester.pumpAndSettle();
    expectFormVisible(visible: true);
    expect(fieldText(tester, const Key('settings_instance_max_memory')), '2048');
  });

  testWidgets('手动模式的实例打开就是命令框', (tester) async {
    final fixture = await bootManualSettings();
    await openDialog(tester, fixture);

    expectFormVisible(visible: false);
    expect(find.text('python3 main.py'), findsOneWidget);
  });

  // ════════════════════════════════════════════════════════════════════════
  // 保存发出去的补丁
  // ════════════════════════════════════════════════════════════════════════

  testWidgets('表单模式保存：发四个表单字段，不发 startup_command', (tester) async {
    final fixture = await bootFormSettings();
    await openDialog(tester, fixture);

    await tester.enterText(
      find.byKey(const Key('settings_instance_max_memory')),
      '4096',
    );
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();

    expect(find.text('已保存'), findsOneWidget);
    final params = lastCallParams(fixture.transport, 'instance.update');
    expect(params['manual_command'], isFalse);
    expect(params['max_memory'], 4096);
    expect(params['runtime_env_id'], 'zulu-jdk-21-linux-x64');
    expect(params['server_file'], 'server.jar');
    expect(params['custom_jvm_args'], '-XX:+UseG1GC -XX:MaxGCPauseMillis=100');
    expect(
      params.containsKey('startup_command'),
      isFalse,
      reason: '表单模式下启动命令只是留档，发出去会把它抹掉',
    );

    // 命令由 daemon 现拼：这里验假后端照真规则拼出了新内存
    expect(
      FakeInstanceStore.launchCommandFor(fixture.store.instances[fixture.id]!),
      'java -Xmx4096M -XX:+UseG1GC -XX:MaxGCPauseMillis=100 '
      '-jar server.jar nogui',
    );
  });

  testWidgets('手动模式保存：发 startup_command', (tester) async {
    final fixture = await bootManualSettings();
    await openDialog(tester, fixture);

    await tester.enterText(
      find.byKey(const Key('settings_instance_startup_command')),
      './start.sh --port 25565',
    );
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();

    final params = lastCallParams(fixture.transport, 'instance.update');
    expect(params['manual_command'], isTrue);
    expect(params['startup_command'], './start.sh --port 25565');
    expect(
      FakeInstanceStore.launchCommandFor(fixture.store.instances[fixture.id]!),
      './start.sh --port 25565',
    );
  });

  testWidgets('最大内存填了非整数：拦下并报错，不发 update', (tester) async {
    final fixture = await bootFormSettings();
    await openDialog(tester, fixture);

    await tester.enterText(
      find.byKey(const Key('settings_instance_max_memory')),
      '2G',
    );
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();

    expect(find.text('保存失败'), findsOneWidget);
    expect(find.textContaining('最大内存要填整数'), findsOneWidget);
    expect(callCount(fixture.transport, 'instance.update'), 0);

    // 改对了就能存下去
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings_instance_max_memory')),
      '3072',
    );
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();
    expect(callCount(fixture.transport, 'instance.update'), 1);
    expect(fixture.store.instances[fixture.id]!['max_memory'], 3072);
  });

  testWidgets('最大内存留空 = 不限制（-Xmx 那截整个不拼）', (tester) async {
    final fixture = await bootFormSettings();
    await openDialog(tester, fixture);

    await tester.enterText(
      find.byKey(const Key('settings_instance_max_memory')),
      '',
    );
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();

    expect(fixture.store.instances[fixture.id]!['max_memory'], isNull);
    expect(
      FakeInstanceStore.launchCommandFor(fixture.store.instances[fixture.id]!),
      'java -XX:+UseG1GC -XX:MaxGCPauseMillis=100 -jar server.jar nogui',
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // 两个下拉的选项
  // ════════════════════════════════════════════════════════════════════════

  testWidgets('服务端 jar 只列实例目录根下的 .jar', (tester) async {
    final fixture = await bootFormSettings();
    final tree = fixture.store.filesFor(fixture.id);
    tree.addFile('spigot-1.21.jar', '另一个 jar');
    tree.addFile('plugins/nested.jar', '目录里的不算');
    tree.addFile('README.txt', '不是 jar');
    await openDialog(tester, fixture);

    await tester.tap(find.byKey(const Key('settings_instance_server_file')));
    await tester.pumpAndSettle();

    expect(find.text('spigot-1.21.jar'), findsOneWidget);
    expect(find.text('nested.jar'), findsNothing);
    expect(find.text('README.txt'), findsNothing);
  });

  testWidgets('服务端 jar 保存过但文件不在了：保留并标注「（实例目录里没有）」', (tester) async {
    final fixture = await bootFormSettings(plantJar: false);
    await openDialog(tester, fixture);

    expect(find.text('server.jar（实例目录里没有）'), findsOneWidget);
    // 还能照常保存 —— 别静默把设置清掉
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();
    expect(
      lastCallParams(fixture.transport, 'instance.update')['server_file'],
      'server.jar',
    );
  });

  testWidgets('运行环境下拉只列装好的 JDK（frpc 与没装完的不进来）', (tester) async {
    final fixture = await bootFormSettings();
    fixture.runtime.seedEnv(packageType: 'frpc', vendor: 'frp', version: '0.71.0');
    fixture.runtime.seedEnv(version: '17', state: 'downloading');
    await openDialog(tester, fixture);

    await tester.tap(find.byKey(const Key('settings_instance_runtime_env')));
    await tester.pumpAndSettle();

    expect(find.text('Zulu JDK · 21'), findsWidgets);
    expect(find.text('Zulu JDK · 17'), findsNothing, reason: '还在下载的不该可选');
    expect(find.textContaining('0.71.0'), findsNothing, reason: 'frpc 不是 JDK');
  });

  testWidgets('运行环境被删了：列表里没有它，照实标「（环境不在了）」', (tester) async {
    final fixture = await bootFormSettings();
    fixture.runtime.environments.clear();
    await openDialog(tester, fixture);

    expect(
      find.text('zulu-jdk-21-linux-x64（环境不在了）'),
      findsOneWidget,
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // 路由器端口映射（UPnP）那段
  // ════════════════════════════════════════════════════════════════════════

  /// 对话框很高，给个高视口让 UPnP 那段不用滚动就能点到。
  void widen(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('UPnP：开关打开才有协议与外部端口，保存发三个字段', (tester) async {
    widen(tester);
    final fixture = await bootFormSettings();
    await openDialog(tester, fixture);

    // 默认关着：子字段摆出来才有鬼
    expect(
      find.byKey(const Key('settings_instance_upnp_protocol')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('settings_instance_upnp_external_port')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const Key('settings_instance_upnp_enabled')),
    );
    await tester.tap(find.byKey(const Key('settings_instance_upnp_enabled')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings_instance_upnp_protocol')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings_instance_upnp_external_port')),
      findsOneWidget,
    );

    // 选 UDP + 填外部端口
    await tester.tap(find.byKey(const Key('settings_instance_upnp_protocol')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UDP').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings_instance_upnp_external_port')),
      '19133',
    );
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();

    expect(find.text('已保存'), findsOneWidget);
    final params = lastCallParams(fixture.transport, 'instance.update');
    expect(params['upnp_enabled'], isTrue);
    expect(params['upnp_protocol'], 'udp');
    expect(params['upnp_external_port'], 19133);
    final stored = fixture.store.instances[fixture.id]!;
    expect(stored['upnp_enabled'], isTrue);
    expect(stored['upnp_protocol'], 'udp');
    expect(stored['upnp_external_port'], 19133);
  });

  testWidgets('UPnP：回填已存的开关 / 协议 / 端口', (tester) async {
    widen(tester);
    final fixture = await bootFormSettings(
      upnpEnabled: true,
      upnpProtocol: 'udp',
      upnpExternalPort: 19133,
    );
    await openDialog(tester, fixture);

    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('settings_instance_upnp_enabled')),
    );
    expect(tile.value, isTrue);
    expect(find.text('UDP'), findsOneWidget, reason: '协议下拉回显 UDP');
    expect(
      fieldText(tester, const Key('settings_instance_upnp_external_port')),
      '19133',
    );

    // 原样保存：三个字段原值发出去（不是被默认值覆盖）
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();
    final params = lastCallParams(fixture.transport, 'instance.update');
    expect(params['upnp_enabled'], isTrue);
    expect(params['upnp_protocol'], 'udp');
    expect(params['upnp_external_port'], 19133);
  });

  testWidgets('UPnP：外部端口填非法值拦下并报错，不发 update', (tester) async {
    widen(tester);
    final fixture = await bootFormSettings(upnpEnabled: true);
    await openDialog(tester, fixture);

    await tester.enterText(
      find.byKey(const Key('settings_instance_upnp_external_port')),
      '70000',
    );
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();

    expect(find.text('保存失败'), findsOneWidget);
    expect(find.textContaining('外部端口要填 1-65535'), findsOneWidget);
    expect(callCount(fixture.transport, 'instance.update'), 0);
  });

  // ════════════════════════════════════════════════════════════════════════
  // STUN 隧道那段
  // ════════════════════════════════════════════════════════════════════════

  testWidgets('STUN：开关打开才有目标端口与 PROXY 开关，保存发三个字段', (tester) async {
    widen(tester);
    final fixture = await bootFormSettings();
    await openDialog(tester, fixture);

    // 默认关着：子字段摆出来才有鬼
    expect(
      find.byKey(const Key('settings_instance_stun_target_port')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('settings_instance_stun_proxy_protocol')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const Key('settings_instance_stun_enabled')),
    );
    await tester.tap(find.byKey(const Key('settings_instance_stun_enabled')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings_instance_stun_target_port')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings_instance_stun_proxy_protocol')),
      findsOneWidget,
    );

    // 开 PROXY protocol v2 + 填转发目标端口
    await tester.ensureVisible(
      find.byKey(const Key('settings_instance_stun_proxy_protocol')),
    );
    await tester.tap(
      find.byKey(const Key('settings_instance_stun_proxy_protocol')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings_instance_stun_target_port')),
      '25570',
    );
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();

    expect(find.text('已保存'), findsOneWidget);
    final params = lastCallParams(fixture.transport, 'instance.update');
    expect(params['stun_enabled'], isTrue);
    expect(params['stun_proxy_protocol'], isTrue);
    expect(params['stun_target_port'], 25570);
    final stored = fixture.store.instances[fixture.id]!;
    expect(stored['stun_enabled'], isTrue);
    expect(stored['stun_proxy_protocol'], isTrue);
    expect(stored['stun_target_port'], 25570);
  });

  testWidgets('STUN：回填已存的开关 / PROXY / 目标端口', (tester) async {
    widen(tester);
    final fixture = await bootFormSettings(
      stunEnabled: true,
      stunProxyProtocol: true,
      stunTargetPort: 25570,
    );
    await openDialog(tester, fixture);

    final enabled = tester.widget<SwitchListTile>(
      find.byKey(const Key('settings_instance_stun_enabled')),
    );
    expect(enabled.value, isTrue);
    final proxy = tester.widget<SwitchListTile>(
      find.byKey(const Key('settings_instance_stun_proxy_protocol')),
    );
    expect(proxy.value, isTrue);
    expect(
      fieldText(tester, const Key('settings_instance_stun_target_port')),
      '25570',
    );

    // 原样保存：三个字段原值发出去（不是被默认值覆盖）
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();
    final params = lastCallParams(fixture.transport, 'instance.update');
    expect(params['stun_enabled'], isTrue);
    expect(params['stun_proxy_protocol'], isTrue);
    expect(params['stun_target_port'], 25570);
  });

  testWidgets('STUN：目标端口填非法值拦下并报错，不发 update', (tester) async {
    widen(tester);
    final fixture = await bootFormSettings(stunEnabled: true);
    await openDialog(tester, fixture);

    await tester.ensureVisible(
      find.byKey(const Key('settings_instance_stun_target_port')),
    );
    await tester.enterText(
      find.byKey(const Key('settings_instance_stun_target_port')),
      '70000',
    );
    await tester.tap(find.byKey(const Key('settings_instance_save')));
    await tester.pumpAndSettle();

    expect(find.text('保存失败'), findsOneWidget);
    expect(find.textContaining('转发目标端口要填 1-65535'), findsOneWidget);
    expect(callCount(fixture.transport, 'instance.update'), 0);
  });
}
