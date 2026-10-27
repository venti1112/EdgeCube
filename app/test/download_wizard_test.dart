import 'package:edgecube_app/connection/client.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/instance/download/progress_page.dart';
import 'package:edgecube_app/instance/download/wizard.dart';
import 'package:edgecube_app/mcserver/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

/// 下载服务端向导的进度页。
///
/// 这一页现在**只做两件事**：把用户的选择提交给 `instance-provision` 工作流、
/// 把任务的进展画出来。以前那套「前端串 plan → create → download.add、失败
/// 自己删实例」的编排已经全交给 daemon 了 —— 所以这里钉的是：
///
/// * 提交的参数对不对（用户选了什么都带过去）；
/// * 渲染的是任务里的**步骤清单**与步骤进度；
/// * 失败时显示**失败那一步**的原因，并且**不再自己调 `instance.delete`**
///   （回滚是 daemon 的事），只在 `rolled_back` 时说一句「已自动删除」；
/// * 重试就是重新提交一次。

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

/// 一个选好类型的向导（版本也选了，就差走流程）。
DownloadWizard _wizard() =>
    DownloadWizard(name: '下载测试服')
      ..kind = const ServerKind(
        id: 'paper',
        name: 'Paper',
        description: '最常用的高性能插件服务端',
        category: 'plugin',
        fileName: 'server.jar',
        startupCommand: 'java -jar server.jar nogui',
        checksum: 'sha256',
        needsVersion: true,
        needsLoader: false,
      )
      ..version = '1.21.8';

/// 一个步骤对象（形状与 daemon 的 `task.get` / 事件里的 data 一致）。
Map<String, Object?> _step({
  required String name,
  required String title,
  required String stepType,
  required String status,
  Map<String, Object?>? progress,
  String? error,
}) => {
  'id': 'step-$name',
  'name': name,
  'title': title,
  'step_type': stepType,
  'status': status,
  'progress': progress,
  'output': null,
  'error': error,
  'attempts': 1,
  'duration_ms': 5,
};

/// 「准备服务端 / 创建实例 / 下载服务端」三步。
List<Map<String, Object?>> _steps({
  String plan = 'completed',
  String create = 'running',
  String download = 'pending',
  Map<String, Object?>? downloadProgress,
  String? downloadError,
}) => [
  _step(
    name: 'plan',
    title: '准备服务端',
    stepType: 'mcserver.plan',
    status: plan,
  ),
  _step(
    name: 'create',
    title: '创建实例',
    stepType: 'instance.create',
    status: create,
  ),
  _step(
    name: 'download',
    title: '下载服务端',
    stepType: 'instance.download',
    status: download,
    progress: downloadProgress,
    error: downloadError,
  ),
];

/// 一份任务对象（形状与 `task.get` / `task.state` / `task.progress` 一致）。
Map<String, Object?> _task({
  required String id,
  required String state,
  List<Map<String, Object?>>? steps,
  Map<String, Object?>? error,
  bool rolledBack = false,
}) => {
  'id': id,
  'flow': 'instance-provision',
  'title': '创建实例并下载服务端',
  'params': {'name': '下载测试服', 'type': 'paper', 'version': '1.21.8'},
  'state': state,
  'current_step': null,
  'steps': steps ?? _steps(),
  'error': error,
  'rolled_back': rolledBack,
  'created_at_ms': 1700000000000,
  'started_at_ms': 1700000000001,
  'finished_at_ms': null,
  'total_duration_ms': null,
};

typedef _Booted =
    ({
      ProviderContainer container,
      FakeTransportFactory transports,
      /// 假 `task.submit` 发出去的任务 id，按提交顺序 —— 每个新提交换一个，
      /// 否则两轮会命中同一个 `taskProvider` 实例、上一轮的状态留到下一轮。
      List<String> taskIds,
    });

/// 建好容器并连上假 daemon。
///
/// 假的 `task.submit` **每次给一个新任务 id**（真后端每次都是一个新 UUID）。
Future<_Booted> _boot({
  Map<String, Object?> Function(Map<String, dynamic> params)? onSubmit,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final taskIds = <String>[];
  final current = <String, Map<String, Object?>>{};

  final transports = FakeTransportFactory(
    responders: {
      'task.submit': (params) {
        if (onSubmit != null) return onSubmit(params);
        final id = 'task-${taskIds.length + 1}';
        taskIds.add(id);
        final view = _task(id: id, state: 'running');
        current[id] = view;
        return view;
      },
      // 快照按问的那个 id 回（真后端就是这样）
      'task.get': (params) {
        final id = params['id'] as String? ?? '';
        return current[id] ?? _task(id: id, state: 'running');
      },
    },
  );
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: transports.call,
  );
  // 连上假 daemon（否则 `taskApiProvider` 是 null，页面会直接报「未连接」）
  await container.read(connectionProvider.notifier).connect(_settings);
  return (container: container, transports: transports, taskIds: taskIds);
}

/// 把进度页推上屏，并把提交那一步走完。
///
/// **不能用 `pumpAndSettle`**：进度环是无限动画，settle 会一直等下去。
Future<void> _pumpPage(
  WidgetTester tester,
  ProviderContainer container,
  DownloadWizard wizard,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: DownloadProgressPage(wizard: wizard)),
    ),
  );
  await _flush(tester);
}

/// 推几帧把异步 RPC（假传输在下一个微任务回包）走完。
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// 某个方法发出去过几次。
int _callsTo(FakeTransportFactory transports, String method) => transports
    .latest
    .sent
    .where((envelope) => envelope['method'] == method)
    .length;

/// 最后一次某方法的参数。
Map<String, dynamic> _lastParams(FakeTransportFactory transports, String method) {
  final envelopes = transports.latest.sent
      .where((envelope) => envelope['method'] == method)
      .toList();
  return (envelopes.last as Map)['params'] as Map<String, dynamic>;
}

void main() {
  testWidgets('提交 instance-provision，并把用户的选择原样带过去', (tester) async {
    final booted = await _boot();
    await _pumpPage(tester, booted.container, _wizard());

    expect(_callsTo(booted.transports, 'task.submit'), 1);
    final params = _lastParams(booted.transports, 'task.submit');
    expect(params['flow'], 'instance-provision');
    expect(params['params'], {
      'name': '下载测试服',
      'type': 'paper',
      'version': '1.21.8',
    });

    // 前端不再自己建实例、也不再自己提交下载 —— 那两步都在 daemon 的工作流里
    expect(
      _callsTo(booted.transports, 'instance.create'),
      0,
      reason: '建实例是工作流的第二步，前端不该自己来',
    );
    expect(
      _callsTo(booted.transports, 'download.add'),
      0,
      reason: '下载是工作流的第三步，前端不该自己来',
    );
  });

  testWidgets('画出三步清单，并按任务的步骤进度显示下载量', (tester) async {
    final booted = await _boot();
    await _pumpPage(tester, booted.container, _wizard());

    // 三步清单都在（标题那句是「创建实例（2/3）」，与清单里的「创建实例」不同串）
    expect(find.text('准备服务端'), findsOneWidget);
    expect(find.text('创建实例'), findsOneWidget);
    expect(find.text('下载服务端'), findsOneWidget);
    expect(find.text('创建实例（2/3）'), findsOneWidget);

    // 推到「正在下载」：进度来自**任务的步骤进度**，不是 download.progress
    booted.transports.latest.pushEvent('task.progress', {
      ..._task(id: booted.taskIds.single, state: 'running'),
      'steps': _steps(
        create: 'completed',
        download: 'running',
        downloadProgress: {
          'percent': 40.0,
          'downloaded': 400,
          'total': 1000,
          'speed': 100,
          'eta_seconds': 6,
        },
      ),
    });
    await _flush(tester);

    expect(find.text('下载服务端（3/3）'), findsOneWidget);
    expect(find.textContaining('40.0%'), findsOneWidget);
    expect(find.textContaining('剩余 6s'), findsOneWidget);
  });

  testWidgets('失败时显示失败那一步的原因，并说明实例已自动删除', (tester) async {
    final booted = await _boot();
    await _pumpPage(tester, booted.container, _wizard());

    // 下载那一步失败 + daemon 回滚过（rolled_back = true）
    booted.transports.latest.pushEvent('task.state', {
      ..._task(
        id: booted.taskIds.single,
        state: 'failed',
        rolledBack: true,
        steps: _steps(
          create: 'completed',
          download: 'failed',
          downloadError: 'download_checksum_mismatch：文件校验不通过',
        ),
        error: {
          'step': 'download',
          'message': 'download_checksum_mismatch：文件校验不通过',
        },
      ),
    });
    await _flush(tester);

    // 错误码前缀被剥掉，只留给人看的那半句
    expect(find.textContaining('文件校验不通过'), findsOneWidget);
    expect(
      find.textContaining('已自动删除'),
      findsOneWidget,
      reason: 'rolled_back 时要说清楚，别让用户以为列表里少了个实例',
    );
    // 回滚是 daemon 做的：前端**不**自己调 instance.delete
    expect(
      _callsTo(booted.transports, 'instance.delete'),
      0,
      reason: '回滚已经交给工作流了，前端不该再删一次',
    );
  });

  testWidgets('没回滚过就不说「已删除」', (tester) async {
    final booted = await _boot();
    await _pumpPage(tester, booted.container, _wizard());

    // 第一步（准备服务端）就挂了：这时根本没建过实例，谈不上回滚
    booted.transports.latest.pushEvent('task.state', {
      ..._task(
        id: booted.taskIds.single,
        state: 'failed',
        steps: _steps(
          plan: 'failed',
          create: 'skipped',
          download: 'skipped',
        ),
        error: {
          'step': 'plan',
          'message': 'mcserver_type_not_found：不认识的服务端类型 `paper`',
        },
      ),
    });
    await _flush(tester);

    expect(find.textContaining('不认识的服务端类型'), findsOneWidget);
    expect(
      find.textContaining('已自动删除'),
      findsNothing,
      reason: '没建过实例就别提「已删除」',
    );
    // 被跳过的那两步按「未执行」画出来
    expect(find.text('未执行'), findsNWidgets(2));
  });

  testWidgets('重试就是重新提交一次，而不是自己收拾残局', (tester) async {
    final booted = await _boot();
    await _pumpPage(tester, booted.container, _wizard());

    booted.transports.latest.pushEvent('task.state', {
      ..._task(
        id: booted.taskIds.single,
        state: 'failed',
        rolledBack: true,
        steps: _steps(
          create: 'completed',
          download: 'failed',
          downloadError: 'download_failed：连接被重置',
        ),
      ),
    });
    await _flush(tester);

    await tester.tap(find.text('重试'));
    await _flush(tester);

    expect(_callsTo(booted.transports, 'task.submit'), 2);
    // 两次提交是**不同的任务 id**（新的一轮）
    expect(booted.taskIds.length, 2);
    expect(booted.taskIds[0], isNot(booted.taskIds[1]));
    // 重试期间不碰任何清理接口
    expect(_callsTo(booted.transports, 'instance.delete'), 0);
  });

  testWidgets('提交当场被拒时显示可读的提示，且不进入任务态', (tester) async {
    final booted = await _boot(
      onSubmit: (_) =>
          throw const DaemonException('task_invalid_params', '参数 `name` 不能为空'),
    );
    await _pumpPage(tester, booted.container, _wizard());

    expect(find.textContaining('参数 `name` 不能为空'), findsOneWidget);
    // 没拿到任务 id，所以清单不该画出来
    expect(find.text('准备服务端'), findsNothing);
    // 重试按钮还在（再试一次没有副作用：提交失败什么都没建）
    expect(find.text('重试'), findsOneWidget);
  });
}
