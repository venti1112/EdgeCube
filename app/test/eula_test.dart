import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/instance/eula.dart';
import 'package:edgecube_app/instance/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

/// EULA 同意机制。
///
/// 钉三件事：**已同意就不弹框**、**未同意要弹那个框**（文案是固定的两句）、
/// **点「不同意」什么都不写**（直接不启动）。

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

/// 一个只有按钮的壳：点它跑一遍 [ensureEulaAgreed]，结果回显在按钮上。
class _Probe extends ConsumerStatefulWidget {
  const _Probe();

  @override
  ConsumerState<_Probe> createState() => _ProbeState();
}

class _ProbeState extends ConsumerState<_Probe> {
  bool? result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final api = ref.read(instanceApiProvider);
            if (api == null) return;
            final agreed = await ensureEulaAgreed(context, api, 'i1');
            if (mounted) setState(() => result = agreed);
          },
          child: Text('结果 ${result ?? '未跑'}'),
        ),
      ),
    );
  }
}

Future<({ProviderContainer container, FakeInstanceStore instances})> _boot() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final transports = FakeTransportFactory();
  // 假后端的 `_require` 会校验实例存在（与真 daemon 一样回 `instance_not_found`），
  // 所以先摆一个实例
  transports.instances.instances['i1'] = {
    'id': 'i1',
    'name': 'EULA 测试服',
    'startup_command': 'java -jar server.jar nogui',
    'compat_mode': false,
    'auto_restart_on_exit': false,
    'path': null,
    'line_ending': '\n',
    'created_at_ms': 1700000000000,
    'updated_at_ms': 1700000000000,
  };
  transports.instances.selected = 'i1';
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: transports.call,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  return (container: container, instances: transports.instances);
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _Probe()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('已同意：直接放行，不弹框、不写文件', (tester) async {
    final boot = await _boot();
    // 服务端自己生成过、或用户以前同意过
    boot.instances.eula['i1'] = (exists: true, agreed: true);

    await _pump(tester, boot.container);
    await tester.tap(find.textContaining('结果'));
    await tester.pumpAndSettle();

    expect(find.text('结果 true'), findsOneWidget);
    expect(find.text('Minecraft EULA'), findsNothing, reason: '已同意就不该弹框');
    expect(boot.instances.eulaAccepts, 0, reason: '已同意不该再写一次');
  });

  testWidgets('未同意：弹框，点「同意」写入并放行', (tester) async {
    final boot = await _boot();
    // 什么都不摆 = 新实例（服务端还没生成 eula.txt）

    await _pump(tester, boot.container);
    await tester.tap(find.textContaining('结果'));
    await tester.pumpAndSettle();

    // 文案是固定的两句
    expect(find.text('Minecraft EULA'), findsOneWidget);
    expect(
      find.text('启动 Minecraft 服务端前需要同意 Minecraft 最终用户许可协议（EULA）。'),
      findsOneWidget,
    );
    expect(find.text('https://aka.ms/MinecraftEULA'), findsOneWidget);
    expect(
      find.text('点击下方「同意」将向 eula.txt 写入 eula=true，表示你已阅读并同意该协议。'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, '不同意'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '同意'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '同意'));
    await tester.pumpAndSettle();

    expect(boot.instances.eulaAccepts, 1, reason: '同意之后要让 daemon 写 eula.txt');
    expect(find.text('结果 true'), findsOneWidget);
  });

  testWidgets('未同意：点「不同意」什么都不写、不放行', (tester) async {
    final boot = await _boot();

    await _pump(tester, boot.container);
    await tester.tap(find.textContaining('结果'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '不同意'));
    await tester.pumpAndSettle();

    expect(find.text('结果 false'), findsOneWidget, reason: '不同意 = 不放行');
    expect(boot.instances.eulaAccepts, 0, reason: '不同意时不写文件');
    expect(
      boot.instances.eula['i1'],
      isNull,
      reason: '不同意不该在磁盘上留下任何痕迹',
    );
  });

  testWidgets('点外面关不掉（barrierDismissible: false）', (tester) async {
    final boot = await _boot();

    await _pump(tester, boot.container);
    await tester.tap(find.textContaining('结果'));
    await tester.pumpAndSettle();

    // 点对话框外面（左上角）
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(
      find.text('Minecraft EULA'),
      findsOneWidget,
      reason: '必须明确选一个，不能点外面关掉',
    );
    expect(find.text('结果 未跑'), findsOneWidget);
  });
}
