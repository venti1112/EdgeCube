import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../files/providers.dart' show fileApiProvider;
import '../frp/models.dart' show FrpSavedTunnel;
import '../frp/providers.dart' show frpTunnelsProvider;
import '../runtime/models.dart'
    show RuntimeEnv, RuntimeEnvState, runtimeEnvTitle;
import '../runtime/providers.dart'
    show runtimeCatalogProvider, runtimeListProvider;
import 'api.dart';
import 'models.dart';
import 'providers.dart';

/// 编辑实例元数据的对话框。
///
/// 启动配置有**两条路线**（与 daemon 的 `instance/model.rs` 一一对应）：
///
/// * **表单模式**（默认）：填「运行环境 + 服务端 jar + 最大内存 +
///   自定义 JVM 参数」，命令由 daemon 现拼成 `java … -jar … nogui`；
/// * **手动模式**：打开「手动命令」开关，表单收起来换成一个随便写的命令框
///   —— 跨语言服务端、自定义启动脚本都靠它。
///
/// 拼命令的那点活**不在前端**：运行环境装在哪、实例目录在哪，只有 daemon 算得对
/// （它回给前端的 `launch_command` 就是最终会跑的那条）。这里只管存字段。
Future<void> showInstanceSettingsDialog(
  BuildContext context,
  WidgetRef ref,
  Instance instance,
) => showDialog<void>(
  context: context,
  builder: (_) => _InstanceSettingsDialog(instance: instance),
);

/// 实例目录根下的 `.jar`（服务端 jar 的候选）。
///
/// 只列根目录的直接子项、只认 `.jar` —— 口径就这一个：
/// 服务端 jar 会被拼进启动命令，填一个路径就等于给 daemon 一条「执行任意文件」
/// 的口子（daemon 那边也会挡掉带路径分隔符的写法）。
final _instanceJarsProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, instanceId) async {
      final api = ref.watch(fileApiProvider);
      if (api == null) return const <String>[];
      final listing = await api.list(instanceId);
      final jars = [
        for (final entry in listing.entries)
          if (!entry.isDir && entry.name.toLowerCase().endsWith('.jar'))
            entry.name,
      ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return jars;
    });

class _InstanceSettingsDialog extends ConsumerStatefulWidget {
  const _InstanceSettingsDialog({required this.instance});

  final Instance instance;

  @override
  ConsumerState<_InstanceSettingsDialog> createState() =>
      _InstanceSettingsDialogState();
}

class _InstanceSettingsDialogState
    extends ConsumerState<_InstanceSettingsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _startupCommand;
  late final TextEditingController _maxMemory;
  late final TextEditingController _jvmArgs;
  late final TextEditingController _stopCommand;
  late bool _manualCommand;
  String? _runtimeEnvId;
  String? _serverFile;
  late bool _compatMode;
  late bool _autoRestart;
  late String _lineEnding;
  String? _frpTunnelId;
  late bool _upnpEnabled;
  late String _upnpProtocol;
  late final TextEditingController _upnpExternalPort;
  late bool _stunEnabled;
  late bool _stunProxyProtocol;
  late final TextEditingController _stunTargetPort;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final instance = widget.instance;
    _name = TextEditingController(text: instance.name);
    _startupCommand = TextEditingController(
      text: instance.startupCommand ?? '',
    );
    _maxMemory = TextEditingController(
      text: instance.maxMemory == null ? '' : '${instance.maxMemory}',
    );
    _jvmArgs = TextEditingController(text: instance.customJvmArgs ?? '');
    // 没配过就预填 daemon 那边生效的默认值 —— 让人看见「现在实际发的是什么」，
    // 想改成 ^C 也一眼知道该写在哪。
    _stopCommand = TextEditingController(
      text: instance.stopCommand?.trim().isNotEmpty ?? false
          ? instance.stopCommand!.trim()
          : kDefaultStopCommand,
    );
    _manualCommand = instance.manualCommand;
    _runtimeEnvId = instance.runtimeEnvId;
    _serverFile = instance.serverFile;
    _compatMode = instance.compatMode;
    _autoRestart = instance.autoRestartOnExit;
    _lineEnding = instance.lineEnding;
    _frpTunnelId = instance.frpTunnelId;
    _upnpEnabled = instance.upnpEnabled;
    _upnpProtocol = instance.upnpProtocol;
    _upnpExternalPort = TextEditingController(
      text: instance.upnpExternalPort == null
          ? ''
          : '${instance.upnpExternalPort}',
    );
    _stunEnabled = instance.stunEnabled;
    _stunProxyProtocol = instance.stunProxyProtocol;
    _stunTargetPort = TextEditingController(
      text: instance.stunTargetPort == null ? '' : '${instance.stunTargetPort}',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _startupCommand.dispose();
    _maxMemory.dispose();
    _jvmArgs.dispose();
    _stopCommand.dispose();
    _upnpExternalPort.dispose();
    _stunTargetPort.dispose();
    super.dispose();
  }

  /// 「最大内存」输入框 → MB；空 / 0 / 负数 = 不传 `-Xmx`（JVM 自己按机器内存定）。
  ///
  /// 非整数没法表示成 MB，这里给 `-1` 当哨兵 —— [_save] 见到它就报错，
  /// 所以它到不了 daemon。
  int? _parseMaxMemory() {
    final text = _maxMemory.text.trim();
    if (text.isEmpty) return null;
    final mb = int.tryParse(text);
    if (mb == null) return -1;
    return mb <= 0 ? null : mb;
  }

  /// 「外部端口」输入框 → 端口；留空 = 跟随服务端端口（daemon 侧是 `None`）。
  ///
  /// 同最大内存：非整数给 `-1` 当哨兵，[_save] 见到就报错。
  int? _parseUpnpPort() {
    final text = _upnpExternalPort.text.trim();
    if (text.isEmpty) return null;
    final port = int.tryParse(text);
    if (port == null || port < 1 || port > 65535) return -1;
    return port;
  }

  /// 「转发目标端口」输入框 → 端口；留空 = 跟随服务端端口（daemon 侧是 `None`）。
  int? _parseStunTargetPort() {
    final text = _stunTargetPort.text.trim();
    if (text.isEmpty) return null;
    final port = int.tryParse(text);
    if (port == null || port < 1 || port > 65535) return -1;
    return port;
  }

  /// 收集表单，组装成给 daemon 的补丁。
  ///
  /// **所有字段都发**（空 → `null`）：daemon 的语义是「给哪些改哪些，
  /// 传 null 表示清空」，所以清空输入框能真的清掉字段。
  Map<String, dynamic> _collectPatch() {
    String? optional(TextEditingController controller) {
      final text = controller.text.trim();
      return text.isEmpty ? null : text;
    }

    final patch = <String, dynamic>{
      'name': _name.text.trim(),
      'manual_command': _manualCommand,
      // 表单那四个字段**两种模式都发**：手动模式下它们是留档，留着下次切回
      // 表单时不用重填（daemon 那边也是这么存的）
      'runtime_env_id': _runtimeEnvId,
      'server_file': _serverFile,
      'max_memory': _parseMaxMemory(),
      'custom_jvm_args': optional(_jvmArgs),
      'stop_command': optional(_stopCommand),
      'compat_mode': _compatMode,
      'auto_restart_on_exit': _autoRestart,
      'line_ending': _lineEnding,
      // 连带启动的隧道（`null` = 不连带）。用哪个 frpc、跑没跑，都不在实例上
      'frp_tunnel_id': _frpTunnelId,
      // 路由器端口映射（UPnP）：开关 + 协议 + 外部端口（null = 跟随服务端端口）
      'upnp_enabled': _upnpEnabled,
      'upnp_protocol': _upnpProtocol,
      'upnp_external_port': _parseUpnpPort(),
      // STUN 隧道：开关 + PROXY protocol v2 + 转发目标端口（null = 跟随服务端端口）
      'stun_enabled': _stunEnabled,
      'stun_proxy_protocol': _stunProxyProtocol,
      'stun_target_port': _parseStunTargetPort(),
    };
    // 启动命令**只在手动模式下发**：表单模式下它只是留档，发 `null` 会把它抹掉
    if (_manualCommand) {
      patch['startup_command'] = optional(_startupCommand);
    }
    return patch;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      await _error('实例名称不能为空');
      return;
    }
    if (_manualCommand &&
        _startupCommand.text.trim().length > kStartupCommandMaxChars) {
      await _error('启动命令过长（上限 $kStartupCommandMaxChars 字）');
      return;
    }
    final maxMemory = _parseMaxMemory();
    if (maxMemory == -1) {
      await _error('最大内存要填整数（单位 MB），留空表示不限制');
      return;
    }
    if (maxMemory != null && maxMemory > kMaxMemoryMbLimit) {
      await _error('最大内存过大（上限 $kMaxMemoryMbLimit MB）');
      return;
    }
    if (_jvmArgs.text.trim().length > kCustomJvmArgsMaxChars) {
      await _error('自定义 JVM 参数过长（上限 $kCustomJvmArgsMaxChars 字）');
      return;
    }
    if (_stopCommand.text.trim().length > kStopCommandMaxChars) {
      await _error('停止命令过长（上限 $kStopCommandMaxChars 字）');
      return;
    }
    if (_parseUpnpPort() == -1) {
      await _error('外部端口要填 1-65535 的整数，留空表示跟随服务端端口');
      return;
    }
    if (_parseStunTargetPort() == -1) {
      await _error('转发目标端口要填 1-65535 的整数，留空表示跟随服务端端口');
      return;
    }

    final api = ref.read(instanceApiProvider);
    if (api == null) return;
    setState(() => _saving = true);
    try {
      await api.update(widget.instance.id, _collectPatch());
      ref.invalidate(instanceListProvider);
      ref.invalidate(selectedInstanceDetailProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await _error(describeInstanceError(e));
    }
  }

  Future<void> _error(String message) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('保存失败'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('实例设置'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('settings_instance_name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '实例名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),

              // ── 启动配置：两条路线，开关说了算 ──
              SwitchListTile(
                key: const Key('settings_instance_manual_command'),
                contentPadding: EdgeInsets.zero,
                title: const Text('手动命令'),
                subtitle: const Text('打开后自己写一整条启动命令，下面的表单不再参与启动'),
                value: _manualCommand,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _manualCommand = value),
              ),
              const SizedBox(height: 8),
              if (_manualCommand)
                TextField(
                  key: const Key('settings_instance_startup_command'),
                  controller: _startupCommand,
                  maxLines: 5,
                  minLines: 3,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: '启动命令',
                    hintText: 'java -Xmx2G -jar server.jar nogui',
                    helperText: '写全解释器与参数；留空则该实例无法启动',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                )
              else ...[
                _RuntimeEnvPicker(
                  value: _runtimeEnvId,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _runtimeEnvId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('settings_instance_max_memory'),
                  controller: _maxMemory,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '最大内存',
                    suffixText: 'MB',
                    hintText: '2048',
                    helperText: '拼成 -Xmx；留空表示不限制',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                _ServerJarPicker(
                  instanceId: widget.instance.id,
                  value: _serverFile,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _serverFile = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('settings_instance_custom_jvm_args'),
                  controller: _jvmArgs,
                  maxLines: 4,
                  minLines: 2,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: '自定义 JVM 参数',
                    hintText: '-XX:+UseG1GC -XX:MaxGCPauseMillis=100',
                    helperText: '空白分隔，原样加在 -jar 之前；不确定就留空',
                    helperMaxLines: 2,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                // 拼出来长什么样：静态模板（不是此刻的命令），省得用户猜
                Text(
                  '保存后 daemon 按上面的设置拼成：'
                  'java 路径 [-Xmx<内存>M] [JVM 参数] -jar <服务端 jar> nogui',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // 关机怎么关：普通命令写一行（如 stop），没有控制台命令的服务端用 ^C
              TextField(
                key: const Key('settings_instance_stop_command'),
                controller: _stopCommand,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: '停止命令',
                  hintText: 'stop',
                  helperText: '写进服务端控制台的一行命令；填 ^C 表示发 Ctrl+C 中断',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                key: const Key('settings_instance_compat'),
                contentPadding: EdgeInsets.zero,
                title: const Text('兼容模式'),
                subtitle: const Text('服务端不输出 Done 标志时，进程起来就视为运行中'),
                value: _compatMode,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _compatMode = value),
              ),
              SwitchListTile(
                key: const Key('settings_instance_autorestart'),
                contentPadding: EdgeInsets.zero,
                title: const Text('关服自动重启'),
                subtitle: const Text('服务端正常退出时自动用相同的启动命令重新拉起'),
                value: _autoRestart,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _autoRestart = value),
              ),
              const SizedBox(height: 8),

              // ── 连带启动的映射隧道 ──
              //
              // 这里**只是一个引用**：选一条隧道，起这个实例时顺手把那个
              // FRP 实例也拉起来。隧道本身是一个独立实例（有自己的进程、
              // 自己启停），用哪个 frpc、现在跑没跑都在「网络映射」那边管 ——
              // 所以这里只有「选哪条」，没有开关、没有 frpc 版本。
              //
              // 也**不会**跟着实例停：一条隧道可能被好几个实例连着，
              // 跟着停会误伤（要停去「网络映射 → 管理隧道」里停）。
              const Divider(height: 32),
              _FrpTunnelPicker(
                value: _frpTunnelId,
                enabled: !_saving,
                onChanged: (value) => setState(() => _frpTunnelId = value),
              ),
              const SizedBox(height: 8),

              // ── 路由器端口映射（UPnP）──
              //
              // 每个实例单独开关：起这个实例时让 daemon 在路由器上加一条映射，
              // 停止时撤掉。协议与外部端口也是**这个实例自己的**参数 ——
              // 全局视角（网关状态、每实例映射行）在「网络映射」页的那张卡上。
              const Divider(height: 32),
              SwitchListTile(
                key: const Key('settings_instance_upnp_enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('路由器端口映射'),
                subtitle: const Text(
                  '实例启动时自动在路由器上开放端口，停止时撤销；需路由器支持 UPnP',
                ),
                value: _upnpEnabled,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _upnpEnabled = value),
              ),
              if (_upnpEnabled) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('settings_instance_upnp_protocol'),
                  initialValue: _upnpProtocol,
                  decoration: const InputDecoration(
                    labelText: '传输协议',
                    helperText: 'Java 版服务端通常用 TCP，基岩版用 UDP',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: kUpnpProtocolTcp,
                      child: Text('TCP'),
                    ),
                    DropdownMenuItem(
                      value: kUpnpProtocolUdp,
                      child: Text('UDP'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _upnpProtocol = value);
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('settings_instance_upnp_external_port'),
                  controller: _upnpExternalPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '外部端口',
                    hintText: '留空则使用服务端端口',
                    helperText: '路由器上对外开放的端口；留空跟随服务端实际端口',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 8),

              // ── STUN 隧道 ──
              //
              // 与 UPnP 同一套取舍（每实例独立）：起这个实例时 daemon 自动打洞，
              // 停止时拆除。隧道为「这个实例的服务端端口」而建 —— 全局视角
              // （公网地址、流量统计、连接日志）在「网络映射」页的那张卡上。
              const Divider(height: 32),
              SwitchListTile(
                key: const Key('settings_instance_stun_enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('STUN 隧道'),
                subtitle: const Text(
                  '实例启动时向 STUN 服务器探测并打洞，停止时拆除；仅全锥形 NAT（NAT1）可用',
                ),
                value: _stunEnabled,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _stunEnabled = value),
              ),
              if (_stunEnabled) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('settings_instance_stun_target_port'),
                  controller: _stunTargetPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '转发目标端口',
                    hintText: '留空则使用服务端端口',
                    helperText: '隧道收下连接后转发到本机哪个端口；留空跟随服务端实际端口',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                SwitchListTile(
                  key: const Key('settings_instance_stun_proxy_protocol'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('发送 PROXY protocol v2'),
                  subtitle: const Text(
                    '让服务端看到玩家真实 IP，需服务端已开启对应支持，否则玩家将无法进入',
                  ),
                  value: _stunProxyProtocol,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _stunProxyProtocol = value),
                ),
              ],
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                key: const Key('settings_instance_line_ending'),
                initialValue: _lineEnding,
                decoration: const InputDecoration(
                  labelText: '命令尾换行符',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: kLineEndingLf,
                    child: Text('Linux（\\n）'),
                  ),
                  DropdownMenuItem(
                    value: kLineEndingCrlf,
                    child: Text('Windows（\\r\\n）'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _lineEnding = value);
                      },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('settings_instance_save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}

/// 「用哪个运行环境」下拉（表单模式的第一项）。
///
/// 选项来自 `runtime.list` 里**已装好的 JDK** —— 没装完的（下载中 / 失败）混进来
/// 只会让用户选到一个跑不起来的东西。空列表时不去禁用整个控件，而是把
/// 「为什么没得选」写出来（并指向该去哪装）。
class _RuntimeEnvPicker extends ConsumerWidget {
  const _RuntimeEnvPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(runtimeListProvider);
    final catalog = ref.watch(runtimeCatalogProvider).value;
    final scheme = Theme.of(context).colorScheme;

    final jdks = (list.value?.environments ?? const <RuntimeEnv>[])
        .where(
          (env) =>
              env.packageType == 'jdk' &&
              env.state == RuntimeEnvState.installed,
        )
        .toList(growable: false);

    // 一个都没装时不去禁用整个控件，而是把「为什么没得选」写出来（并指向该去哪装）。
    // 但**存过值的例外**：那时要让人看见自己选的是哪个（哪怕它已经不在列表里）。
    final saved = (value ?? '').isNotEmpty;
    if (jdks.isEmpty && list.hasValue && !saved) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: '运行环境',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(
          '还没有装好的 Java 运行环境 —— 去「运行环境」里下载一个',
          style: TextStyle(fontSize: 12, color: scheme.error),
        ),
      );
    }

    return _IdPicker(
      key: const Key('settings_instance_runtime_env'),
      label: '运行环境',
      helperText: '装好的 JDK；服务端就用它跑',
      value: value,
      options: [
        for (final env in jdks)
          (id: env.id, label: runtimeEnvTitle(catalog, env)),
      ],
      missingSuffix: '（环境不在了）',
      // 环境列表还没拉回来时别把保存过的值显示成「不在了」
      loading: !list.hasValue,
      enabled: enabled,
      onChanged: onChanged,
    );
  }
}

/// 「用哪个服务端 jar」下拉（表单模式的第二项）。
///
/// 选项是**实例目录根下面的** `.jar`；保存过的名字可能已经不在那儿了
/// （jar 被删或被改名），这时保留它并标注出来，而不是静默清空。
class _ServerJarPicker extends ConsumerWidget {
  const _ServerJarPicker({
    required this.instanceId,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String instanceId;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jars = ref.watch(_instanceJarsProvider(instanceId));
    final scheme = Theme.of(context).colorScheme;

    if (jars.hasError) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: '服务端 jar',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(
          '读不到实例目录：${jars.error}',
          style: TextStyle(fontSize: 12, color: scheme.error),
        ),
      );
    }

    final names = jars.value ?? const <String>[];
    // 同运行环境：目录里一个 .jar 都没有时给一句「去哪传」；但存过值时
    // 照旧进下拉，把那个（可能已经不在的）名字显示出来。
    final saved = (value ?? '').isNotEmpty;
    if (names.isEmpty && jars.hasValue && !saved) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: '服务端 jar',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(
          '未在实例目录里找到 .jar —— 先去「文件」页把服务端传上去',
          style: TextStyle(fontSize: 12, color: scheme.error),
        ),
      );
    }

    return _IdPicker(
      key: const Key('settings_instance_server_file'),
      label: '服务端 jar',
      helperText: '实例目录根下的 .jar（启动时拼成 -jar <文件名>）',
      value: value,
      options: [for (final name in names) (id: name, label: name)],
      missingSuffix: '（实例目录里没有）',
      loading: !jars.hasValue,
      enabled: enabled,
      onChanged: onChanged,
    );
  }
}

/// 一个「选 id」的下拉：`(id, 显示名)` 的选项 + 可能已经不在选项里的当前值。
///
/// 保存过的值不在选项里是常事（环境被卸了、jar 改名了）。直接丢掉它会让
/// **保存时静默清空**用户的设置，所以补一条标注了「（不在了）」的选项，
/// 让人看得见、也改得掉。
class _IdPicker extends StatelessWidget {
  const _IdPicker({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
    this.helperText,
    this.missingSuffix = '（不在了）',
    this.loading = false,
  });

  final String label;
  final String? value;
  final List<({String id, String label})> options;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  final String? helperText;
  final String missingSuffix;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ids = [for (final option in options) option.id];
    final missing = value != null && !ids.contains(value);

    if (loading && options.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: const Text('读取中…', style: TextStyle(fontSize: 12)),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: value,
      // 展开：让长选项（环境 id / 隧道名可能很长）被约束住、按省略号截断，
      // 而不是把行撑破
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        if (missing)
          DropdownMenuItem(
            value: value,
            child: Text(
              '$value$missingSuffix',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        for (final option in options)
          DropdownMenuItem(
            value: option.id,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// 「连带启动哪条映射隧道」下拉。
///
/// 选项来自 `frp.tunnels.list`（「网络映射 → 管理隧道」里保存的那些）。
/// **第一项永远是「不连带启动」**（值是 `null`）：不选也是一条明确的说法，
/// 而不是一个空着、没法回退的组合框。
class _FrpTunnelPicker extends ConsumerWidget {
  const _FrpTunnelPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tunnels = ref.watch(frpTunnelsProvider);
    final scheme = Theme.of(context).colorScheme;
    final saved = tunnels.value ?? const <FrpSavedTunnel>[];

    // 保存过的隧道可能已经被删了 —— 那样 `initialValue` 不在 items 里，
    // Flutter 的断言会拦下，所以先对一遍
    final known = saved.any((tunnel) => tunnel.localId == value);

    return DropdownButtonFormField<String?>(
      key: const Key('settings_instance_frp_tunnel'),
      initialValue: known ? value : null,
      // 隧道名是用户起的，可能很长
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '随实例启动的映射隧道',
        helperText: saved.isEmpty
            ? '还没有隧道 —— 去「网络映射 → 管理隧道」里建一条'
            : '起这个实例时顺手把那条隧道也拉起来；它不跟着停',
        helperStyle: saved.isEmpty
            ? TextStyle(fontSize: 12, color: scheme.error)
            : null,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('不连带启动')),
        for (final tunnel in saved)
          DropdownMenuItem<String?>(
            value: tunnel.localId,
            child: Text(tunnel.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}
