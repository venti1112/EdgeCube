import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/runtime/runtime_download_page.dart';
import 'package:edgecube_app/runtime/runtime_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

/// 运行环境页。
///
/// 钉三件事：列表怎么呈现（含失败态的原因与重试）、删除要有确认且真的发
/// `runtime.delete`、下载页点「安装」会提交 `runtime-install` 工作流。进度条那条链路
/// （`download.progress` 事件）在下载向导的测试里已经钉过，这里不重复。

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

/// 一个已装好的环境（形状照 daemon 的 `runtime.list` 单项）。
Map<String, Object?> _installedEnv() => {
  'id': 'zulu-jdk-21-linux-x64',
  'vendor': 'zulu',
  'package_type': 'jdk',
  'version': '21',
  'version_name': '21.0.12.1',
  'vendor_version': '21.52.203',
  'os': 'linux',
  'arch': 'x64',
  'archive_type': 'tar.gz',
  'package_uuid': 'uuid-1',
  'file_name': 'zulu21.tar.gz',
  'url': 'https://cdn.azul.com/zulu/bin/zulu21.tar.gz',
  'sha256': 'a' * 64,
  'size': 213089000,
  'support_term': 'lts',
  'state': 'installed',
  'home': 'zulu21.52.203-ca-jdk21.0.12.1-linux_x64',
  'binary': 'zulu21.52.203-ca-jdk21.0.12.1-linux_x64/bin/java',
  'created_at_ms': 1700000000000,
  'installed_at_ms': 1700000001000,
  'updated_at_ms': 1700000001000,
};

/// 一个装失败的环境（死在解压那一步）。
Map<String, Object?> _failedEnv() => {
  ..._installedEnv(),
  'id': 'zulu-jdk-17-linux-x64',
  'version': '17',
  'version_name': '17.0.16',
  'state': 'failed',
  'stage': 'extract',
  'error': '解压出来的包里没有 bin/java —— 这不是一份能用的 JDK',
  'home': null,
  'binary': null,
  'installed_at_ms': null,
  'task_id': null,
};

Map<String, Object?> _catalog({bool supported = true, bool includeFrp = false}) => {
  'providers': [
    {
      'id': 'zulu',
      'name': 'Zulu',
      'homepage': 'https://www.azul.com/downloads/',
      'package_types': ['jdk'],
    },
    if (includeFrp)
      {
        'id': 'frp',
        'name': 'frp',
        'homepage': 'https://github.com/fatedier/frp',
        'package_types': ['frpc'],
      },
  ],
  'package_types': [
    {'id': 'jdk', 'name': 'JDK', 'description': '开发工具包'},
    if (includeFrp)
      {'id': 'frpc', 'name': 'frp 客户端', 'description': '内网穿透客户端'},
  ],
  'default_provider': 'zulu',
  'default_package_type': 'jdk',
  'host': {'os': 'linux', 'arch': 'x64', 'archive_type': 'tar.gz', 'libc': 'glibc'},
  'supported': supported,
};

Map<String, Object?> _versions() => {
  'provider': 'zulu',
  'package_type': 'jdk',
  'os': 'linux',
  'arch': 'x64',
  'archive_type': 'tar.gz',
  // 默认只给最新那个（`all = false`）—— 前端据此决定要不要显示「历史版本」
  'all': false,
  'versions': [
    {'version': '21', 'label': 'Java 21', 'subtitle': '21.0.12.1'},
    {'version': '17', 'label': 'Java 17', 'subtitle': '17.0.16'},
  ],
};

/// `task.submit` 的返回：一份刚提交、正在跑的任务（形状与 `task.get` 一致）。
Map<String, Object?> _runningTask(String id) => {
  'id': id,
  'flow': 'runtime-install',
  'title': '下载并安装运行环境',
  'params': const <String, Object?>{},
  'state': 'running',
  'current_step': 'download',
  'steps': const <Object?>[],
  'error': null,
  'rolled_back': false,
  'created_at_ms': 1700000000000,
  'started_at_ms': 1700000000001,
  'finished_at_ms': null,
  'total_duration_ms': null,
};

Future<({
  ProviderContainer container,
  FakeTransportFactory transports,
})>
_boot({
  required Map<String, Object?> responses,
  Map<String, Object? Function(Map<String, dynamic> params)>? responders,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final transports = FakeTransportFactory(
    responses: responses,
    responders: responders,
  );
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: transports.call,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  return (container: container, transports: transports);
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
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// 发出去过几次某个方法。
int _calls(FakeTransportFactory transports, String method) => transports
    .latest
    .sent
    .where((envelope) => envelope['method'] == method)
    .length;

/// 最后一次某方法的参数。
Map<String, dynamic> _lastParams(
  FakeTransportFactory transports,
  String method,
) {
  final envelopes = transports.latest.sent
      .where((envelope) => envelope['method'] == method)
      .toList();
  return (envelopes.last as Map)['params'] as Map<String, dynamic>;
}

void main() {
  testWidgets('列表展示已装环境与失败环境的原因', (tester) async {
    final booted = await _boot(
      responses: {
        'runtime.catalog': _catalog(),
        'runtime.list': {
          'environments': [_installedEnv(), _failedEnv()],
          'count': 2,
          'dir': '/data/runtimes',
        },
      },
    );

    await _pump(
      tester,
      booted.container,
      const RuntimePage(),
    );

    expect(find.textContaining('Zulu JDK · 21.0.12.1'), findsOneWidget);
    // 装好的那份：可执行文件的位置要给出来（用户以后拼启动命令要用）
    expect(find.textContaining('可执行文件'), findsOneWidget);
    // 失败的那份：原因 + 重试按钮，不能只有一句「失败」
    expect(find.textContaining('解压失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('删除要走确认框，确认后才发 runtime.delete', (tester) async {
    final booted = await _boot(
      responses: {
        'runtime.catalog': _catalog(),
        'runtime.list': {
          'environments': [_installedEnv()],
          'count': 1,
          'dir': '/data/runtimes',
        },
      },
    );

    await _pump(tester, booted.container, const RuntimePage());

    // 点删除 → 先弹确认框
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除运行环境'), findsOneWidget);
    expect(_calls(booted.transports, 'runtime.delete'), 0);

    // 确认 → 才发
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(_calls(booted.transports, 'runtime.delete'), 1);
    final envelope = booted.transports.latest.sent
        .where((e) => e['method'] == 'runtime.delete')
        .single;
    expect((envelope['params'] as Map)['id'], 'zulu-jdk-21-linux-x64');
  });

  testWidgets('失败环境的重试会重新提交一次安装工作流', (tester) async {
    final booted = await _boot(
      responses: {
        'runtime.catalog': _catalog(),
        'runtime.list': {
          'environments': [_failedEnv()],
          'count': 1,
          'dir': '/data/runtimes',
        },
        'task.submit': _runningTask('task-1'),
      },
    );

    await _pump(tester, booted.container, const RuntimePage());
    expect(_calls(booted.transports, 'task.submit'), 0);

    await tester.tap(find.text('重试'));
    await tester.pump(const Duration(milliseconds: 10));

    // 装环境现在**只能**走 `runtime-install` 工作流（`runtime.install` 已删）
    expect(_calls(booted.transports, 'task.submit'), 1);
    final params = _lastParams(booted.transports, 'task.submit');
    expect(params['flow'], 'runtime-install');
    final args = params['params'] as Map;
    expect(args['version'], '17', reason: '重试要装同一个大版本');
    expect(args['provider'], 'zulu');
    expect(args['package_type'], 'jdk');
  });

  testWidgets('下载页列出大版本，点安装提交 runtime-install 并回到列表', (tester) async {
    final booted = await _boot(
      responses: {
        'runtime.catalog': _catalog(),
        'runtime.versions': _versions(),
        'task.submit': _runningTask('task-1'),
      },
    );

    await _pump(tester, booted.container, const RuntimeDownloadPage());

    expect(find.text('Java 21'), findsOneWidget);
    expect(find.text('Java 17'), findsOneWidget);
    // 版本列表是降序的（新的在前）
    expect(
      tester.getTopLeft(find.text('Java 21')).dy <
          tester.getTopLeft(find.text('Java 17')).dy,
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilledButton, '安装').first);
    await tester.pump(const Duration(milliseconds: 10));

    expect(_calls(booted.transports, 'task.submit'), 1);
    final params = _lastParams(booted.transports, 'task.submit');
    expect(params['flow'], 'runtime-install');
    expect((params['params'] as Map)['version'], '21');

    // 发完就回列表页（进度在列表里看）；pop 有转场动画，多等几帧
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(RuntimeDownloadPage), findsNothing);
  });

  testWidgets('本机不支持时入口置灰并说明，不出现下载按钮', (tester) async {
    final booted = await _boot(
      responses: {
        'runtime.catalog': _catalog(supported: false),
        'runtime.list': {'environments': [], 'count': 0, 'dir': '/data/runtimes'},
      },
    );

    await _pump(tester, booted.container, const RuntimePage());

    expect(find.textContaining('没有对应的 Zulu 构建'), findsOneWidget);
    expect(find.text('下载运行环境'), findsNothing);
  });

  testWidgets('下载页默认只拉最新，点「历史版本」才拉完整列表', (tester) async {
    // `runtime.versions` 按 `all` 参数回不同的东西：这是「历史版本」按钮要验的
    // 核心行为 —— 默认只拉 latest（省一次上游请求，frp 走 GitHub 配额紧），
    // 点了才拉全部。
    final booted = await _boot(
      responses: {
        'runtime.catalog': _catalog(includeFrp: true),
      },
      responders: {
        'runtime.versions': (params) {
          final all = params['all'] == true;
          return {
            'provider': 'frp',
            'package_type': 'frpc',
            'os': 'linux',
            'arch': 'x64',
            'archive_type': 'tar.gz',
            'all': all,
            'versions': all
                ? [
                    {'version': '0.71.0', 'label': '0.71.0', 'subtitle': '2026-08-14'},
                    {'version': '0.70.0', 'label': '0.70.0', 'subtitle': '2026-07-01'},
                  ]
                : [
                    {'version': '0.71.0', 'label': '0.71.0', 'subtitle': '2026-08-14'},
                  ],
          };
        },
      },
    );

    await _pump(
      tester,
      booted.container,
      const RuntimeDownloadPage(provider: 'frp'),
    );

    // 默认只要最新那个：列表里只有一条，且「历史版本」按钮还在
    expect(find.text('0.71.0'), findsOneWidget);
    expect(find.text('0.70.0'), findsNothing);
    expect(find.text('历史版本'), findsOneWidget);

    // 点「历史版本」→ 换 query（all=true）重新拉
    await tester.tap(find.text('历史版本'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    // 完整列表出来了，旧版本也看得到
    expect(find.text('0.71.0'), findsOneWidget);
    expect(find.text('0.70.0'), findsOneWidget);
    // 已经拉到全部了，按钮就不必再显示
    expect(find.text('历史版本'), findsNothing);
  });
}
