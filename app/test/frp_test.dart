import 'package:edgecube_app/connection/client.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/frp/frp_custom_config_page.dart';
import 'package:edgecube_app/frp/frp_login_page.dart';
import 'package:edgecube_app/frp/frp_provider_picker_page.dart';
import 'package:edgecube_app/frp/frp_provider_tunnels_page.dart';
import 'package:edgecube_app/frp/frp_run_page.dart';
import 'package:edgecube_app/frp/frp_tunnel_config_page.dart';
import 'package:edgecube_app/frp/frp_tunnel_list_page.dart';
import 'package:edgecube_app/frp/models.dart';
import 'package:edgecube_app/frp/providers.dart';
import 'package:edgecube_app/pages/port_mapping_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

// ══════════════════════════════════════════════════════════════════════════
// 夹具
// ══════════════════════════════════════════════════════════════════════════

typedef FrpFixture = ({
  ProviderContainer container,
  FakeFrpStore store,
  FakeDaemonTransport transport,
  FakeUpnpStore upnp,
  FakeStunStore stun,
});

/// 连上假 daemon。平台侧的一切（登录、隧道、配置生成）都在 daemon 侧，
/// 所以这里摆的是 daemon 的返回值（[FakeFrpStore]），不铺别的。
/// `upnp` / `stun` 不给就用工厂默认的空后端（网关未探测、零行、零日志）。
Future<FrpFixture> bootFrp({FakeUpnpStore? upnp, FakeStunStore? stun}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final frp = FakeFrpStore();
  final upnpStore = upnp ?? FakeUpnpStore();
  final stunStore = stun ?? FakeStunStore();
  final factory = FakeTransportFactory(
    frp: frp,
    upnp: upnpStore,
    stun: stunStore,
  );
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: factory.call,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  return (
    container: container,
    store: frp,
    transport: factory.latest,
    upnp: upnpStore,
    stun: stunStore,
  );
}

/// frp 那几条路由（照 `lib/router.dart` 抄，测试只跑这一支）。
GoRouter frpRouter(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    // 与 `lib/router.dart` 同一套结构：网络映射 → 映射隧道 → 各子页。
    // 测试自带路由是为了不起整个 shell（底栏、连接守卫都不相关）。
    GoRoute(
      path: '/manage/network',
      builder: (context, state) => const PortMappingPage(),
      routes: [
        GoRoute(
          path: 'tunnels',
          builder: (context, state) => const FrpTunnelListPage(),
          routes: [
            GoRoute(
              path: 'picker',
              builder: (context, state) => const FrpProviderPickerPage(),
            ),
            GoRoute(
              path: 'custom',
              builder: (context, state) => const FrpCustomConfigPage(),
            ),
            GoRoute(
              path: 'login/:provider',
              builder: (context, state) => FrpLoginPage(
                providerKey: state.pathParameters['provider'] ?? '',
              ),
            ),
            GoRoute(
              path: 'provider/:provider',
              builder: (context, state) => FrpProviderTunnelsPage(
                providerKey: state.pathParameters['provider'] ?? '',
              ),
            ),
            GoRoute(
              path: 'run/:localId',
              builder: (context, state) => FrpRunPage(
                localId: state.pathParameters['localId'] ?? '',
              ),
            ),
            GoRoute(
              path: 'config/:localId',
              builder: (context, state) => FrpTunnelConfigPage(
                localId: state.pathParameters['localId'] ?? '',
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// 推进若干帧，把在飞的 RPC / 路由动画跑完。
///
/// 这些页面上到处是 `CircularProgressIndicator`（等待授权、加载隧道…），
/// 它一帧一帧地画，`pumpAndSettle` 永远等不到「静止」，只会超时。
Future<void> pumpFrames(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpFrp(
  WidgetTester tester,
  FrpFixture fixture, {
  String initial = '/manage/network/tunnels',
}) => pumpFrpContainer(tester, fixture.container, initial: initial);

Future<void> pumpFrpContainer(
  WidgetTester tester,
  ProviderContainer container, {
  String initial = '/manage/network/tunnels',
}) async {
  final router = frpRouter(initial);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await pumpFrames(tester);
}

/// 按标签找输入框（`labelText` 渲染成 Text，且是 TextField 的后代）。
Finder fieldWithLabel(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

/// 滚到可见再点（长表单底部的按钮在小屏上会落在视口外）。
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await pumpFrames(tester);
  await tester.tap(finder);
  await pumpFrames(tester);
}

/// 切到某个标签页（按 TabBar 里的标签点，避开正文里的同名文字）。
Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.text(label)),
  );
  await pumpFrames(tester);
}

Finder createTunnelButton() => find.widgetWithText(FilledButton, '创建隧道');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 剪贴板走平台通道，测试环境里没人应答；而复制链接是「await 完才提示」，
  // 不给个应答者的话那句话永远不出现。
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

  // ══════════════════════════════════════════════════════════════════════
  // 模型（形状与文案照 daemon）
  // ══════════════════════════════════════════════════════════════════════

  test('平台清单：能力、展示名与副标题', () {
    final sakura = FrpProvider.fromJson(const {
      'key': 'sakurafrp',
      'name': 'Sakura Frp',
      'requires_login': true,
      'browser_login': false,
      'token_login': true,
    });
    expect(sakura.isCustom, isFalse);
    expect(sakura.displayName, 'Sakura Frp');
    expect(sakura.subtitle, '樱花内网穿透');
    expect(sakura.tokenHelp, '在 SakuraFrp 官网「用户信息」页复制访问密钥');
    expect(sakura.browserLogin, isFalse);

    final custom = FrpProvider.fromJson(const {'key': 'custom', 'name': ''});
    expect(custom.isCustom, isTrue);
    expect(custom.displayName, '自定义 FRP');
    expect(custom.subtitle, '手动填写或粘贴 frpc 配置，连接任意 frps 服务器');
    expect(custom.requiresLogin, isTrue, reason: '字段缺失时按「要登录」处理');

    // 清单里挑一个：找不到给 null（页面据此显示「未知的映射平台」）
    expect(findFrpProvider([sakura], 'sakurafrp')?.name, 'Sakura Frp');
    expect(findFrpProvider([sakura], 'openfrp'), isNull);
  });

  test('登录态：令牌非空且账号名非空才跳得过登录页', () {
    FrpAccountStatus status({
      required bool loggedIn,
      String? username,
    }) => FrpAccountStatus.fromJson({
      'provider': 'openfrp',
      'logged_in': loggedIn,
      'account': username == null ? null : {'username': username},
    });

    expect(status(loggedIn: true, username: 'steve').canSkipLogin, isTrue);
    expect(
      status(loggedIn: true, username: '').canSkipLogin,
      isFalse,
      reason: '令牌在但账号名空：也要再登录一次',
    );
    expect(status(loggedIn: true).canSkipLogin, isFalse);
    expect(status(loggedIn: false, username: 'steve').canSkipLogin, isFalse);

    final account = FrpAccount.fromJson(const {
      'username': 'steve',
      'group': '普通用户',
      'used_tunnels': 2,
      'max_tunnels': 5,
    });
    expect(account.displayText, 'steve (普通用户) · 2/5');
    expect(FrpAccount.fromJson(const {'username': 'steve'}).displayText, 'steve');
  });

  test('会话状态：waiting / success / error / idle', () {
    final waiting = FrpLoginSession.fromJson(const {
      'provider': 'chmlfrp',
      'session_id': 's',
      'state': 'waiting',
      'url': 'https://example.com/a',
      'user_code': 'ABCD-1234',
    });
    expect(waiting.isWaiting, isTrue);
    expect(waiting.isSuccess, isFalse);
    expect(waiting.userCode, 'ABCD-1234');

    expect(
      FrpLoginSession.fromJson(const {'state': 'success'}).isSuccess,
      isTrue,
    );
    expect(
      FrpLoginSession.fromJson(const {'state': 'cancelled'}).state,
      FrpLoginState.idle,
      reason: '取消后回到未登录态',
    );
    expect(FrpLoginSession.fromJson(const {}).state, FrpLoginState.idle);
  });

  test('展示地址与节点标签的回退', () {
    expect(
      FrpNode.fromJson(const {
        'id': '1',
        'name': 'cn-1',
        'vip': true,
        'online': false,
      }).label,
      'cn-1 [VIP]（离线）',
    );
    expect(FrpNode.fromJson(const {'id': '1', 'name': 'cn-1'}).label, 'cn-1');

    FrpRemoteTunnel remote(Map<String, Object?> json) =>
        FrpRemoteTunnel.fromJson(json);
    expect(
      remote(const {
        'id': '1',
        'node_name': 'cn-1',
        'remote_port': 2,
        'remote_address': 'a.example.com:2',
      }).displayAddress,
      'a.example.com:2',
    );
    expect(
      remote(const {'id': '1', 'node_name': 'cn-1', 'remote_port': 2})
          .displayAddress,
      'cn-1:2',
    );
    expect(
      remote(const {'id': '1', 'node_name': 'cn-1'}).displayAddress,
      'cn-1',
    );

    // 本地保存的那条：节点名空时不再硬拼 `:端口`
    expect(
      FrpSavedTunnel.fromJson(const {
        'local_id': 'a',
        'provider': 'custom',
        'name': 'x',
        'remote_port': 2,
      }).displayAddress,
      '',
    );
    expect(
      FrpSavedTunnel.fromJson(const {
        'local_id': 'a',
        'provider': 'openfrp',
        'name': 'x',
        'node_name': 'cn-1',
        'remote_port': 2,
      }).displayAddress,
      'cn-1:2',
    );
  });

  test('错误翻译：按 code 分支，令牌失效单独一类', () {
    expect(
      describeFrpError(const DaemonException('frp_network_error', '连接超时')),
      '网络请求失败：连接超时',
    );
    expect(
      describeFrpError(const DaemonException('frp_not_logged_in', '尚未登录 x')),
      '登录已失效，请重新登录',
    );
    expect(
      describeFrpError(const DaemonException('frp_tunnel_not_found', '没了')),
      '本地没有这条隧道（可能已被删除）',
    );
    expect(
      describeFrpError(const DaemonException('frp_api_error', '隧道数已达上限')),
      '隧道数已达上限',
      reason: '平台业务错误直接用平台那句话',
    );

    expect(isFrpTokenInvalid(const DaemonException('frp_unauthorized', 'x')), isTrue);
    expect(isFrpTokenInvalid(const DaemonException('frp_not_logged_in', 'x')), isTrue);
    expect(isFrpTokenInvalid(const DaemonException('frp_api_error', 'x')), isFalse);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 数据层：方法与参数名跟 daemon 一致（协议回归的守门员）
  // ══════════════════════════════════════════════════════════════════════

  test('FrpApi：方法名与参数名与 daemon 逐字一致', () async {
    final fixture = await bootFrp();
    final api = fixture.container.read(frpApiProvider)!;
    final transport = fixture.transport;
    Map<String, dynamic> lastParams() =>
        (transport.sent.last['params'] as Map).cast<String, dynamic>();

    expect((await api.providers()).length, 6);

    await api.loginStart('openfrp');
    expect(transport.sent.last['method'], 'frp.login.start');
    expect(lastParams(), {'provider': 'openfrp'});

    await api.account('sakurafrp', verify: true);
    expect(transport.sent.last['method'], 'frp.account');
    expect(lastParams(), {'provider': 'sakurafrp', 'verify': true});

    await api.loginWithToken('mefrp', 'tok');
    expect(transport.sent.last['method'], 'frp.login.token');
    expect(lastParams(), {'provider': 'mefrp', 'token': 'tok'});

    await api.loginCancel('openfrp');
    expect(transport.sent.last['method'], 'frp.login.cancel');

    await api.logout('openfrp');
    expect(transport.sent.last['method'], 'frp.logout');

    // 创建隧道：两个端口留空就不发这两个键（由 daemon 报提示语）
    fixture.store.login('openfrp');
    fixture.store.seedNode('openfrp', name: 'cn-1');
    await expectLater(
      api.createRemoteTunnel(
        provider: 'openfrp',
        nodeId: '1',
        name: 'x',
        type: 'tcp',
        localIp: '127.0.0.1',
      ),
      throwsA(
        isA<DaemonException>().having(
          (error) => error.message,
          'message',
          '请完整填写隧道名称与端口',
        ),
      ),
      reason: '端口留空时不拦在前端，交给 daemon 报那句话',
    );
    expect(transport.sent.last['method'], 'frp.remote.create');
    expect(lastParams().containsKey('local_port'), isFalse);
    expect(lastParams().containsKey('remote_port'), isFalse);

    // 填了就照发（键名与 daemon 的取值逐字一致）
    await api.createRemoteTunnel(
      provider: 'openfrp',
      nodeId: '1',
      name: 'x',
      type: 'udp',
      localIp: '127.0.0.1',
      localPort: 25565,
      remotePort: 15000,
    );
    expect(lastParams(), {
      'provider': 'openfrp',
      'node_id': '1',
      'name': 'x',
      'type': 'udp',
      'local_ip': '127.0.0.1',
      'local_port': 25565,
      'remote_port': 15000,
    });
    expect(fixture.store.created, hasLength(2));

    await api.deleteRemoteTunnel('openfrp', '1');
    expect(lastParams(), {'provider': 'openfrp', 'remote_tunnel_id': '1'});

    await api.remoteTunnels('openfrp');
    expect(transport.sent.last['method'], 'frp.remote.tunnels');
    await api.remoteNodes('openfrp');
    expect(transport.sent.last['method'], 'frp.remote.nodes');

    await api.tunnels();
    expect(transport.sent.last['method'], 'frp.tunnels.list');
    expect(lastParams(), isEmpty);

    // 自定义隧道：只发用户填的字段，TOML 由 daemon 拼
    final saved = await api.saveTunnel(
      FrpTunnelInput.customForm(
        name: '我的',
        serverAddr: 'frp.example.com',
        serverPort: 7000,
        localPort: 25565,
        remotePort: 25566,
      ),
    );
    expect(transport.sent.last['method'], 'frp.tunnels.save');
    expect(lastParams()['provider'], 'custom');
    expect(lastParams()['custom_form'], {
      'server_addr': 'frp.example.com',
      'server_port': 7000,
      'user': '',
      'auth_token': '',
      'kind': 'tcp',
      'local_ip': '127.0.0.1',
      'local_port': 25565,
      'remote_port': 25566,
      'tls_enable': true,
    });

    final localId = saved.tunnel.localId;
    expect(localId, isNotEmpty);
    expect(saved.configError, isEmpty);

    final config = await api.tunnelConfig(localId);
    expect(lastParams(), {'local_id': localId});
    expect(config.generated, isFalse, reason: '保存时已经写盘了');
    expect(config.path, endsWith('/config/frp/toml/$localId.toml'));

    await api.tunnelConfig(localId, refresh: true);
    expect(lastParams(), {'local_id': localId, 'refresh': true});

    await api.removeTunnel(localId);
    expect(lastParams(), {'local_id': localId});
    expect(fixture.store.savedTunnels, isEmpty);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 列表页
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('列表页：空态给「添加隧道」，点进平台选择页', (tester) async {
    final fixture = await bootFrp();
    await pumpFrp(tester, fixture);

    expect(find.text('映射隧道'), findsOneWidget);
    expect(find.text('还没有隧道，点击下方按钮添加'), findsOneWidget);

    await tester.tap(find.text('添加隧道'));
    await pumpFrames(tester);
    expect(find.text('选择映射平台'), findsOneWidget);
    expect(find.text('OpenFrp 免费内网穿透'), findsOneWidget);
  });

  testWidgets('列表页：卡片显示平台名与公网地址，删除只删本地记录', (tester) async {
    final fixture = await bootFrp();
    fixture.store.seedSavedTunnel(
      provider: 'openfrp',
      name: '生存服',
      type: 'udp',
      nodeName: 'cn-1',
      remotePort: 30000,
      remoteAddress: 'cn-1.example.com:30000',
    );
    await pumpFrp(tester, fixture);

    expect(find.text('生存服'), findsOneWidget);
    expect(
      find.text('OpenFrp · UDP'),
      findsOneWidget,
      reason: '平台名取清单里的展示名，不是 key',
    );
    expect(find.text('cn-1.example.com:30000'), findsOneWidget);

    await tester.tap(find.byTooltip('复制连接地址'));
    await pumpFrames(tester);
    expect(find.text('连接地址已复制'), findsOneWidget);
    // 等它自己退场：提示条是排队的，不散掉下一条「已删除」不会显示
    await tester.pump(const Duration(seconds: 5));
    await pumpFrames(tester);

    await tester.tap(find.byTooltip('删除'));
    await pumpFrames(tester);
    expect(
      find.text('确定从列表中删除隧道「生存服」吗？（不会删除平台上的隧道）'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await pumpFrames(tester);

    expect(fixture.store.savedTunnels, isEmpty);
    expect(fixture.store.calls['frp.remote.delete'], isNull, reason: '只删本地那条');
    expect(find.text('已删除「生存服」'), findsOneWidget);
    expect(find.text('还没有隧道，点击下方按钮添加'), findsOneWidget);
  });

  testWidgets('列表页：点卡片进运行页（启停 + 日志）', (tester) async {
    final fixture = await bootFrp();
    final localId = fixture.store.seedSavedTunnel(
      provider: 'custom',
      name: '我的穿透',
    );
    fixture.store.seedRun(localId, tunnelName: '我的穿透');
    fixture.store.runLogs[localId] = ['[fake] 已连接 frps'];
    await pumpFrp(tester, fixture);

    await tester.tap(find.text('我的穿透'));
    await pumpFrames(tester);

    // 运行页：标题是隧道名，开关开着，日志显示出来了
    expect(find.text('启动隧道'), findsOneWidget);
    expect(find.text('运行中'), findsWidgets);
    expect(find.text('[fake] 已连接 frps'), findsOneWidget);

    // 关掉 → 发 `frp.run.stop`（状态由 daemon 的事件推回来，本地不猜）
    await tester.tap(find.byKey(const Key('frp_run_switch')));
    await pumpFrames(tester);
    expect(fixture.store.calls['frp.run.stop'], 1);
  });

  testWidgets('运行页：起不来的原因直接写在卡片上，不用去翻日志', (tester) async {
    final fixture = await bootFrp();
    final localId = fixture.store.seedSavedTunnel(
      provider: 'custom',
      name: '起不来的穿透',
    );
    fixture.store.seedRun(localId, state: 'failed', message: '没装 frpc');
    await pumpFrp(
      tester,
      fixture,
      initial: '/manage/network/tunnels/run/$localId',
    );

    expect(find.text('没装 frpc'), findsOneWidget);
    expect(find.text('起不来'), findsOneWidget);
  });

  testWidgets('运行页：右上角进配置页，配置文本来自 daemon', (tester) async {
    final fixture = await bootFrp();
    final localId = fixture.store.seedSavedTunnel(
      provider: 'custom',
      name: '我的穿透',
      toml: 'serverAddr = "frp.example.com"\n',
    );
    await pumpFrp(
      tester,
      fixture,
      initial: '/manage/network/tunnels/run/$localId',
    );

    await tester.tap(find.byKey(const Key('frp_run_config')));
    await pumpFrames(tester);

    expect(find.text('$localId.toml'), findsOneWidget, reason: '盘上就叫这个名字');
    expect(find.textContaining('/config/frp/toml/$localId.toml'), findsOneWidget);
    expect(find.text('serverAddr = "frp.example.com"\n'), findsOneWidget);
    expect(find.text('读取的是已生成的配置（点右上角可重新生成）：'), findsOneWidget);

    await tester.tap(find.byTooltip('重新生成'));
    await pumpFrames(tester);
    expect(find.text('已生成并写入守护进程的磁盘：'), findsOneWidget);
  });

  testWidgets('列表页：跑着的画实心云，起不来的画断云并写上原因', (tester) async {
    final fixture = await bootFrp();
    final running = fixture.store.seedSavedTunnel(
      provider: 'custom',
      name: '跑着的',
    );
    fixture.store.seedRun(running, tunnelName: '跑着的');
    final broken = fixture.store.seedSavedTunnel(
      provider: 'custom',
      name: '坏掉的',
    );
    fixture.store.seedRun(broken, state: 'failed', message: '没装 frpc');
    await pumpFrp(tester, fixture);

    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('起不来'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 网络映射页（FRP 卡 + STUN 卡 + UPnP 卡 + DDNS 置灰卡）
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('网络映射：FRP 卡能选 frpc 环境，只剩下 DDNS 卡置灰', (tester) async {
    // 这一页很长（四张卡），把视口放宽让整页都建出来 —— 否则 `ListView`
    // 只建可见的那几屏，屏幕外的卡断言不到
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fixture = await bootFrp();
    fixture.store.frpcRuntimes.add((
      id: 'frp-frpc-0.71.0-linux-x64',
      name: 'frp 0.71.0',
    ));
    await pumpFrp(tester, fixture, initial: '/manage/network');

    // FRP 卡：运行环境下拉（回显生效的那个）+ 管理隧道
    expect(find.text('FRP 隧道'), findsOneWidget);
    expect(find.text('FRP 运行环境'), findsOneWidget);
    expect(find.text('frp 0.71.0'), findsOneWidget);
    expect(find.text('管理隧道'), findsOneWidget);

    // STUN 卡是真的（默认零隧道 + 全局设置的默认值）；UPnP 卡也是真的；
    // 只剩 DDNS 一张标着「未实现」、开关点不动
    expect(find.text('STUN 隧道'), findsOneWidget);
    expect(find.text('路由器端口映射'), findsOneWidget);
    expect(find.text('DDNS 动态域名'), findsOneWidget);
    expect(find.text('未实现'), findsOneWidget);
    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '启用 DDNS 动态域名解析'),
    );
    expect(tile.onChanged, isNull, reason: 'DDNS 开关应当置灰');

    // STUN 卡：还没有实例开开关 + 全局设置回填 daemon 的默认值
    expect(find.textContaining('还没有实例开启 STUN 隧道'), findsOneWidget);
    expect(find.text('STUN 服务器'), findsOneWidget);
    expect(find.text('隧道日志'), findsOneWidget);
    expect(find.text('暂无日志'), findsOneWidget);
    final servers = tester.widget<TextField>(
      find.byKey(const Key('port_mapping_stun_servers')),
    );
    expect(servers.controller!.text, contains('fwa.lifesizecloud.com'));

    // UPnP 卡：没探测过网关 + 还没有实例开开关
    expect(find.text('未探测'), findsOneWidget);
    expect(find.textContaining('还没探测过网关'), findsOneWidget);
    expect(find.textContaining('还没有实例开启端口映射'), findsOneWidget);

    // 「管理隧道」进隧道列表
    await tapVisible(tester, find.text('管理隧道'));
    expect(find.text('映射隧道'), findsOneWidget);
  });

  testWidgets('网络映射：UPnP 卡显示网关与每实例映射行', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final upnp = FakeUpnpStore();
    upnp.seedGateway(externalIp: '198.51.100.9', address: '192.168.1.1:1900');
    upnp.seedRow(
      'aaaa',
      instanceName: '主世界',
      running: true,
      state: 'mapped',
      externalPort: 25570,
      publicAddress: '198.51.100.9:25570',
    );
    upnp.seedRow(
      'bbbb',
      instanceName: '空岛',
      protocol: 'udp',
      state: 'idle',
    );
    final fixture = await bootFrp(upnp: upnp);
    await pumpFrp(tester, fixture, initial: '/manage/network');

    // 网关一行：状态 + 地址 + 公网 IP
    expect(find.text('已连接网关'), findsOneWidget);
    expect(
      find.text('网关 192.168.1.1:1900 · 公网 IP 198.51.100.9'),
      findsOneWidget,
    );

    // 已映射的行：外网地址 + 端口映射 + 状态
    expect(find.text('主世界'), findsOneWidget);
    expect(find.text('198.51.100.9:25570 · 25565 → 25570/TCP'), findsOneWidget);
    expect(find.text('已映射'), findsOneWidget);
    // 开关开着但实例没跑：写明「实例未在运行」，端口列按 UDP 画
    expect(find.text('空岛'), findsOneWidget);
    expect(find.text('实例未在运行 · 25565/UDP'), findsOneWidget);
    expect(find.text('未映射'), findsOneWidget);
  });

  testWidgets('网络映射：CGNAT 警示条 + 「重新探测」拿到新快照', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final upnp = FakeUpnpStore();
    upnp.seedGateway(externalIp: '100.64.0.5', cgnat: true);
    final fixture = await bootFrp(upnp: upnp);
    await pumpFrp(tester, fixture, initial: '/manage/network');

    // 进来先拉了一次；CGNAT 的警示条在
    expect(upnp.calls['upnp.status'], 1);
    expect(
      find.text(
        '公网 IP 是运营商级 NAT（CGNAT）地址：映射成功外网也连不进来，'
        '建议改用 FRP 隧道。',
      ),
      findsOneWidget,
    );

    // 点上「重新探测」：这次网关发现失败，卡片跟着新快照走
    upnp.seedGateway(
      state: 'error',
      externalIp: null,
      address: null,
      error: '没有找到 UPnP 网关',
    );
    await tester.tap(find.byKey(const Key('port_mapping_upnp_probe')));
    await pumpFrames(tester);

    expect(upnp.calls['upnp.probe'], 1);
    expect(find.text('发现失败'), findsOneWidget);
    expect(find.text('没有找到 UPnP 网关'), findsOneWidget);
    expect(find.textContaining('运营商级 NAT（CGNAT）地址'), findsNothing);
  });

  testWidgets('网络映射：STUN 卡显示每实例隧道行（地址 / 端口 / 连接数 / 状态）', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final stun = FakeStunStore();
    stun.seedTunnel(
      'aaaa',
      instanceName: '主世界',
      running: true,
      state: 'running',
      publicAddress: '203.0.113.7:25570',
      localPort: 25570,
      targetPort: 25565,
      activeConnections: 2,
      upSpeed: 1024,
      downSpeed: 2048,
    );
    stun.seedTunnel('bbbb', instanceName: '空岛', running: false);
    final fixture = await bootFrp(stun: stun);
    await pumpFrp(tester, fixture, initial: '/manage/network');

    // 进来先拉了一次快照；之后有活隧道就每秒再拉，所以只验「拉过」
    expect(stun.calls['stun.status'], greaterThanOrEqualTo(1));

    // 运行中的行：公网地址 + 端口链路 + 连接数 + 速率
    expect(find.text('主世界'), findsOneWidget);
    expect(
      find.text('公网 203.0.113.7:25570 · 25570 → 目标 25565 · 连接 2/128 · ↑1.0 KB/s ↓2.0 KB/s'),
      findsOneWidget,
    );
    expect(find.text('运行中'), findsOneWidget);

    // 开关开着但实例没跑：写明「实例未在运行」
    expect(find.text('空岛'), findsOneWidget);
    expect(find.text('实例未在运行 · 目标 25565'), findsOneWidget);
    expect(find.text('未启动'), findsOneWidget);

    // 复制公网直连地址
    await tapVisible(tester, find.byKey(const Key('stun_row_copy_aaaa')));
    expect(find.text('已复制 203.0.113.7:25570'), findsOneWidget);
  });

  testWidgets('网络映射：STUN 全局设置保存发 patch（空行丢掉、日志开关随行）', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fixture = await bootFrp();
    await pumpFrp(tester, fixture, initial: '/manage/network');

    // 改服务器列表（空行丢掉）、并发、保活，并关掉连接日志
    await tester.enterText(
      find.byKey(const Key('port_mapping_stun_servers')),
      'stun.example.com:3479\n\nstun2.example.com',
    );
    await tester.enterText(
      find.byKey(const Key('port_mapping_stun_max_connections')),
      '64',
    );
    await tester.enterText(
      find.byKey(const Key('port_mapping_stun_keep_alive')),
      '45',
    );
    await tapVisible(tester, find.byKey(const Key('port_mapping_stun_show_log')));
    await tapVisible(tester, find.byKey(const Key('port_mapping_stun_save')));

    // patch 式：只带这几个字段（keepalive_http 不动，daemon 保留原值）
    expect(fixture.stun.lastSettingsPatch, {
      'servers': ['stun.example.com:3479', 'stun2.example.com'],
      'keep_alive_seconds': 45,
      'max_connections': 64,
      'show_connection_log': false,
    });
    expect(find.text('设置已保存'), findsOneWidget);
  });

  testWidgets('网络映射：STUN 日志带实例标记，清空后回到「暂无日志」', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final stun = FakeStunStore();
    stun.seedLog(
      '隧道已就绪：203.0.113.7:25570',
      instanceId: 'aaaa',
      instanceName: '主世界',
    );
    stun.seedLog('入站连接 1.2.3.4:5000', instanceId: 'bbbb', instanceName: '空岛');
    final fixture = await bootFrp(stun: stun);
    await pumpFrp(tester, fixture, initial: '/manage/network');

    // 前缀是 [时间] [实例名]，按内容找
    expect(find.textContaining('隧道已就绪：203.0.113.7:25570'), findsOneWidget);
    expect(find.textContaining('[空岛] 入站连接 1.2.3.4:5000'), findsOneWidget);

    // 清空：发给 daemon 后重拉，回到空态
    await tapVisible(
      tester,
      find.byKey(const Key('port_mapping_stun_clear_logs')),
    );
    expect(stun.calls['stun.logs.clear'], 1);
    await pumpFrames(tester);
    expect(find.text('暂无日志'), findsOneWidget);
  });

  testWidgets('网络映射：stun.evt 事件到达时整体替换快照（不用回拉）', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fixture = await bootFrp();
    await pumpFrp(tester, fixture, initial: '/manage/network');

    // 起步：卡里还是「还没有实例开启 STUN 隧道」
    expect(find.textContaining('还没有实例开启 STUN 隧道'), findsOneWidget);

    // daemon 侧多了一条探测中的隧道，推一份完整快照过来
    fixture.stun.seedTunnel(
      'aaaa',
      instanceName: '主世界',
      running: true,
      state: 'probing',
    );
    fixture.stun.calls.clear();
    fixture.transport.pushEvent('stun.evt', fixture.stun.snapshot);
    // 只推 300ms：不够轮询（1s）触发，界面变了就证明吃的是事件里的快照
    await pumpFrames(tester, frames: 6);

    expect(fixture.stun.calls['stun.status'], isNull);
    expect(find.text('主世界'), findsOneWidget);
    expect(find.text('正在探测公网映射… · 目标 25565'), findsOneWidget);
    expect(find.text('探测中…'), findsOneWidget);
  });

  testWidgets('网络映射：一个 frpc 都没装时给警示条，而不是一个空下拉', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fixture = await bootFrp();
    await pumpFrp(tester, fixture, initial: '/manage/network');

    expect(find.textContaining('未安装 FRP 客户端运行环境'), findsOneWidget);
    expect(find.text('FRP 运行环境'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 平台选择页
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('选择平台页：自定义直进配置页', (tester) async {
    final fixture = await bootFrp();
    await pumpFrp(tester, fixture, initial: '/manage/network/tunnels/picker');

    await tester.tap(find.text('自定义 FRP'));
    await pumpFrames(tester);
    expect(find.text('简易表单'), findsOneWidget);
    expect(find.text('粘贴配置'), findsOneWidget);
    expect(fixture.store.calls['frp.account'], isNull, reason: '自定义没有登录态可查');
  });

  testWidgets('选择平台页：没登录去登录页，登录过直接进隧道页', (tester) async {
    final fixture = await bootFrp();
    await pumpFrp(tester, fixture, initial: '/manage/network/tunnels/picker');

    await tester.tap(find.text('Sakura Frp'));
    await pumpFrames(tester);
    expect(find.text('账号登录'), findsOneWidget);
    expect(find.byKey(const Key('frp_access_token')), findsOneWidget);

    // 摆上登录态再来一次：这次跳过登录页
    fixture.store.login('openfrp');
    await tester.pageBack();
    await pumpFrames(tester);
    await tester.tap(find.text('OpenFrp'));
    await pumpFrames(tester);
    expect(find.text('我的隧道'), findsOneWidget);
    expect(find.text('创建隧道'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 登录页（发请求、轮询、存令牌都在 daemon，App 只显示）
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('登录页：粘贴 Token 登录（令牌由 daemon 落盘）→ 进隧道页', (tester) async {
    final fixture = await bootFrp();
    await pumpFrp(
      tester,
      fixture,
      initial: '/manage/network/tunnels/login/sakurafrp',
    );

    expect(find.text('Sakura Frp'), findsOneWidget);
    expect(find.text('账号登录'), findsOneWidget);
    expect(find.text('在 SakuraFrp 官网「用户信息」页复制访问密钥'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('frp_access_token')), 'abc123');
    await tester.tap(find.text('登录'));
    await pumpFrames(tester);

    expect(fixture.store.tokens['sakurafrp'], 'abc123');
    expect(find.text('我的隧道'), findsOneWidget);
    expect(find.text('steve (普通用户) · 1/3'), findsOneWidget);
  });

  testWidgets('登录页：浏览器授权等 daemon 推 success（App 不轮询）', (tester) async {
    final fixture = await bootFrp();
    await pumpFrp(
      tester,
      fixture,
      initial: '/manage/network/tunnels/login/chmlfrp',
    );

    await tester.tap(find.text('浏览器登录'));
    await pumpFrames(tester);
    expect(find.text('已打开授权页面，请在浏览器中完成授权…'), findsOneWidget);
    expect(find.text('ABCD-1234'), findsOneWidget, reason: '设备码只有 ChmlFrp 有');

    // 「重新打开 / 复制链接 / 取消」都在
    expect(find.text('重新打开'), findsOneWidget);
    await tester.tap(find.text('复制链接'));
    await pumpFrames(tester);
    expect(find.text('链接已复制'), findsOneWidget);

    // 授权进度全靠 daemon 推：App 自己不轮询
    final polls = fixture.store.calls['frp.login.status'] ?? 0;
    await tester.pump(const Duration(seconds: 30));
    expect(fixture.store.calls['frp.login.status'], polls);

    fixture.transport.pushEvent('frp.login', {
      'provider': 'chmlfrp',
      'session_id': 'session-chmlfrp',
      'state': 'success',
      'message': '',
      'url': '',
      'user_code': '',
      'account': {'username': 'steve', 'group': '普通用户'},
    });
    await pumpFrames(tester);
    expect(find.text('我的隧道'), findsOneWidget);
  });

  testWidgets('登录页：回到页面时接上 daemon 正在跑的授权，取消就回表单', (tester) async {
    final fixture = await bootFrp();
    fixture.store.seedSession('openfrp', url: 'https://example.com/a?c=1');
    await pumpFrp(
      tester,
      fixture,
      initial: '/manage/network/tunnels/login/openfrp',
    );

    expect(find.text('已打开授权页面，请在浏览器中完成授权…'), findsOneWidget);
    expect(find.text('浏览器登录'), findsNothing);

    await tester.tap(find.text('取消'));
    await pumpFrames(tester);
    expect(fixture.store.sessions, isEmpty);
    expect(find.text('浏览器登录'), findsOneWidget);
  });

  testWidgets('登录页：挂载早于连上时，连上后补问会话状态', (tester) async {
    // App 冷启动 / 刷新：页面先挂载，WS 还没接上，那会儿问不到会话状态
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = FakeFrpStore();
    final container = bootContainer(
      storage: prefs,
      persisted: _settings,
      transportFactory: FakeTransportFactory(frp: store).call,
    );
    addTearDown(container.dispose);
    store.seedSession('openfrp', url: 'https://example.com/a?c=1');
    await pumpFrpContainer(
      tester,
      container,
      initial: '/manage/network/tunnels/login/openfrp',
    );
    // 未连接时平台清单也拿不到，卡片只能提示「未知平台」
    expect(find.text('未知的映射平台，请返回重新选择。'), findsOneWidget);
    expect(find.text('已打开授权页面，请在浏览器中完成授权…'), findsNothing);

    await container.read(connectionProvider.notifier).connect(_settings);
    await pumpFrames(tester);

    // 连上后补问：接上 daemon 正在跑的授权，而不是当成没登录
    expect(find.text('已打开授权页面，请在浏览器中完成授权…'), findsOneWidget);
    expect(find.text('浏览器登录'), findsNothing);
  });

  testWidgets('登录页：已存令牌复核通过就直接进去，复核失败清令牌回表单', (tester) async {
    final fixture = await bootFrp();
    fixture.store.login('openfrp', usedTunnels: 2, maxTunnels: 5);
    await pumpFrp(
      tester,
      fixture,
      initial: '/manage/network/tunnels/login/openfrp',
    );
    expect(find.text('我的隧道'), findsOneWidget);
    expect(find.text('steve (普通用户) · 2/5'), findsOneWidget);

    // 复核失败：daemon 顺手清掉令牌，页面老实显示登录表单
    final again = await bootFrp();
    again.store.login('openfrp');
    again.store.verifyFails = true;
    await pumpFrp(
      tester,
      again,
      initial: '/manage/network/tunnels/login/openfrp',
    );
    expect(again.store.tokens, isEmpty);
    expect(find.text('浏览器登录'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 自定义配置页
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('自定义配置页：简易表单保存 → daemon 拼 TOML 落盘', (tester) async {
    final fixture = await bootFrp();
    await pumpFrp(tester, fixture, initial: '/manage/network/tunnels/custom');

    await tester.enterText(find.byKey(const Key('frp_custom_name')), '我的穿透');
    await tester.enterText(fieldWithLabel('服务器地址'), 'frp.example.com');
    await tester.enterText(fieldWithLabel('用户名（可选）'), 'steve');
    await tapVisible(tester, find.text('保存'));

    // 前端只发用户填的字段
    expect(fixture.store.savedInputs.single['provider'], 'custom');
    expect(fixture.store.savedInputs.single['name'], '我的穿透');
    expect(fixture.store.savedInputs.single['custom_form'], {
      'server_addr': 'frp.example.com',
      'server_port': 7000,
      'user': 'steve',
      'auth_token': '',
      'kind': 'tcp',
      'local_ip': '127.0.0.1',
      'local_port': 25565,
      'remote_port': 25566,
      'tls_enable': true,
    });

    // 配置已在 daemon 的盘上
    final localId = fixture.store.savedTunnels.keys.single;
    expect(
      fixture.store.tomls[localId],
      contains('serverAddr = "frp.example.com"'),
    );
    expect(fixture.store.tomls[localId], contains('name = "我的穿透"'));
    expect(fixture.store.tomls[localId], contains('remotePort = 25566'));

    // 保存完退回列表页，新隧道就在那儿
    expect(find.text('映射隧道'), findsOneWidget);
    expect(find.text('我的穿透'), findsOneWidget);
    expect(find.text('隧道已保存到列表'), findsOneWidget);
  });

  testWidgets('自定义配置页：校验文案由 daemon 给', (tester) async {
    final fixture = await bootFrp();
    await pumpFrp(tester, fixture, initial: '/manage/network/tunnels/custom');

    // 简易表单：缺服务器地址
    await tapVisible(tester, find.text('保存'));
    expect(find.text('请完整填写隧道名称与端口'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await pumpFrames(tester);
    expect(fixture.store.savedTunnels, isEmpty);

    // 粘贴模式：配置空着
    await tester.tap(find.text('粘贴配置'));
    await pumpFrames(tester);
    await tapVisible(tester, find.text('保存'));
    expect(find.text('配置内容不能为空'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await pumpFrames(tester);
    expect(fixture.store.savedTunnels, isEmpty);

    // 粘贴模式：原文交给 daemon
    await tester.enterText(
      find.byKey(const Key('frp_custom_raw')),
      'serverAddr = "raw.example.com"\n',
    );
    await tapVisible(tester, find.text('保存'));
    expect(
      fixture.store.customToml.values.single,
      'serverAddr = "raw.example.com"\n',
    );
    expect(find.text('我的穿透'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 平台隧道页
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('平台隧道页：使用平台上的隧道 → 存到本地并退回列表页', (tester) async {
    final fixture = await bootFrp();
    fixture.store.login('openfrp', usedTunnels: 2, maxTunnels: 5);
    fixture.store.seedNode(
      'openfrp',
      id: '1',
      name: 'cn-1',
      hostname: 'cn-1.example.com',
      minPort: 10000,
      maxPort: 20000,
    );
    fixture.store.seedRemoteTunnel(
      'openfrp',
      id: '77',
      name: '生存服',
      remotePort: 15000,
      remoteAddress: 'cn-1.example.com:15000',
    );
    await pumpFrp(tester, fixture, initial: '/manage/network/tunnels/picker');

    await tester.tap(find.text('OpenFrp'));
    await pumpFrames(tester);
    expect(find.text('steve (普通用户) · 2/5'), findsOneWidget);
    expect(find.text('TCP · 127.0.0.1:25565 → cn-1.example.com:15000'), findsOneWidget);

    await tester.tap(find.text('使用'));
    await pumpFrames(tester);

    final saved = fixture.store.savedTunnels.values.single;
    expect(saved['provider'], 'openfrp');
    expect(saved['remote_tunnel_id'], '77');
    expect(saved['node_name'], 'cn-1');
    expect(saved['remote_address'], 'cn-1.example.com:15000');
    expect(find.text('隧道已保存到列表'), findsOneWidget);
    expect(find.text('映射隧道'), findsOneWidget, reason: '保存后弹回列表页');
    expect(find.text('生存服'), findsOneWidget);
  });

  testWidgets('平台隧道页：创建隧道（端口留空由 daemon 报提示，填好就创建成功）', (tester) async {
    final fixture = await bootFrp();
    fixture.store.login('openfrp');
    fixture.store.seedNode(
      'openfrp',
      name: 'cn-1',
      hostname: 'cn-1.example.com',
      minPort: 10000,
      maxPort: 20000,
    );
    await pumpFrp(
      tester,
      fixture,
      initial: '/manage/network/tunnels/provider/openfrp',
    );
    await openTab(tester, '创建隧道');

    expect(find.text('cn-1'), findsOneWidget, reason: '下拉默认选第一个在线节点');
    await tester.enterText(find.byKey(const Key('frp_create_name')), '新隧道');
    await tester.enterText(fieldWithLabel('本地端口'), '');
    await tester.enterText(fieldWithLabel('远程端口'), '');
    await tapVisible(tester, createTunnelButton());

    expect(find.text('请完整填写隧道名称与端口'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await pumpFrames(tester);
    expect(fixture.store.remoteTunnels['openfrp'], isNull);

    await tester.enterText(fieldWithLabel('本地端口'), '25565');
    await tester.enterText(fieldWithLabel('远程端口'), '15000');
    await tapVisible(tester, createTunnelButton());

    expect(find.text('隧道创建成功'), findsOneWidget);
    final created = fixture.store.created.last;
    expect(created['node_id'], '1');
    expect(created['local_port'], 25565);
    expect(created['remote_port'], 15000);
    expect(fixture.store.remoteTunnels['openfrp']!.single['name'], '新隧道');

    // 建完自动切回「我的隧道」并刷新
    expect(find.widgetWithText(Card, '新隧道'), findsOneWidget);
  });

  testWidgets('平台隧道页：令牌失效 → 清登录、提示、换登录页', (tester) async {
    final fixture = await bootFrp();
    fixture.store.login('openfrp');
    fixture.store.unauthorized = true;
    await pumpFrp(
      tester,
      fixture,
      initial: '/manage/network/tunnels/provider/openfrp',
    );

    expect(find.text('登录已失效，请重新登录'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await pumpFrames(tester);

    expect(fixture.store.tokens, isEmpty);
    expect(find.text('账号登录'), findsOneWidget);
    expect(find.byKey(const Key('frp_access_token')), findsNothing);
    expect(find.text('浏览器登录'), findsOneWidget, reason: 'OpenFrp 走浏览器授权');
  });

  testWidgets('平台隧道页：退出登录后回上一页', (tester) async {
    final fixture = await bootFrp();
    fixture.store.login('openfrp');
    await pumpFrp(tester, fixture, initial: '/manage/network/tunnels/picker');
    await tester.tap(find.text('OpenFrp'));
    await pumpFrames(tester);

    await tester.tap(find.byTooltip('退出登录'));
    await pumpFrames(tester);

    expect(fixture.store.tokens, isEmpty);
    expect(find.text('选择映射平台'), findsOneWidget);
  });
}
