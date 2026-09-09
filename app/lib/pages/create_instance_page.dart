import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'current_instance.dart';
import 'instance_wizard/download_flow_state.dart';
import 'instance_wizard/wizard_tile.dart';
import 'labels.dart';

/// 创建实例页(对齐 V1「名称 + 创建方式磁贴」向导根页):
/// 输入名称 → 选择创建方式:
/// - 下载服务端:进入「下载服务端」向导(类型 → 分类/服务端 → 版本 → 加载器 → 下载)
/// - 创建空实例:直接创建(generic 类型,稍后再安装服务端)
/// 导入服务端 / 导入压缩包 / 导入整合包(V1 另有入口)暂未迁移:后端对应接口未就绪。
class CreateInstancePage extends ConsumerStatefulWidget {
  const CreateInstancePage({super.key});

  @override
  ConsumerState<CreateInstancePage> createState() => _CreateInstancePageState();
}

class _CreateInstancePageState extends ConsumerState<CreateInstancePage> {
  final _nameController = TextEditingController();
  bool _creating = false;

  /// 已安装运行时(创建空实例时的运行环境候选)。
  List<RuntimeInfo> _runtimes = [];
  RuntimeInfo? _selectedRuntime;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _loadRuntimes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 拉取已安装运行时供选择;失败静默(仅缺候选,不阻断创建)。
  Future<void> _loadRuntimes() async {
    final client = _client;
    if (client == null) return;
    try {
      final list = (await client.getRuntimesApi().listRuntimes()).data!;
      if (!mounted) return;
      setState(() => _runtimes = list.toList());
    } catch (_) {}
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 名称非空校验(重名由后端 409 提示)。
  bool _validateName() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) return true;
    _snack('请输入实例名称');
    return false;
  }

  /// 进入「下载服务端」向导:重置会话状态并跳转版本类型选择页。
  void _goDownloadFlow() {
    if (!_validateName() || _creating) return;
    FocusScope.of(context).unfocus();
    ref.read(downloadFlowProvider.notifier)
        .enter(DownloadFlowState(name: _nameController.text.trim()));
    context.push('/servers/instances/create/download/edition');
  }

  /// 创建空实例:直接提交(不带下载信息,daemon 同步返回 201)。
  Future<void> _createEmpty() async {
    if (!_validateName() || _creating) return;
    final client = _client;
    if (client == null) {
      _snack('未连接到服务器');
      return;
    }
    setState(() => _creating = true);
    try {
      final resp = await client.getInstancesApi().createInstance(
            instanceConfig: InstanceConfig((b) => b
              ..name = _nameController.text.trim()
              ..type = InstanceType.generic
              ..runtimeId = _selectedRuntime?.id),
          );
      // 创建成功即设为全局当前实例(对齐 V1 createInstance 自动选中)
      final created = resp.data;
      final createdId = created?.id;
      if (created != null && createdId != null) {
        await ref.read(currentInstanceProvider.notifier).select(
              InstanceSummary((b) => b
                ..id = createdId
                ..name = created.name
                ..status = InstanceStatus.stopped
                ..type = created.type ?? InstanceType.generic),
            );
      }
      if (!mounted) return;
      _snack('实例「${_nameController.text.trim()}」创建成功');
      context.go('/servers');
    } on Exception catch (e) {
      if (!mounted) return;
      _snack(apiErrorMessage(e));
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('命名实例'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '实例名称',
              hintText: '例如:我的世界 生存服',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _runtimePicker(),
          const SizedBox(height: 8),
          WizardTile(
            icon: Icons.cloud_download_outlined,
            title: '下载服务端',
            subtitle: '从官方源下载服务端并自动创建实例',
            onTap: _goDownloadFlow,
          ),
          const SizedBox(height: 12),
          WizardTile(
            icon: Icons.create_new_folder_outlined,
            title: '创建空实例',
            subtitle: '仅创建空实例,稍后再安装服务端',
            onTap: _creating ? () {} : _createEmpty,
          ),
        ],
      ),
    );
  }

  /// 运行环境下拉(作用于「创建空实例」;下载服务端向导创建的实例
  /// 可在实例控制面板修改运行环境)。
  Widget _runtimePicker() {
    return DropdownButtonFormField<RuntimeInfo?>(
      initialValue: _selectedRuntime,
      decoration: const InputDecoration(
        labelText: '运行环境(可选)',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<RuntimeInfo?>(
          value: null,
          child: Text('不指定(使用系统环境)'),
        ),
        for (final r in _runtimes)
          DropdownMenuItem<RuntimeInfo?>(
            value: r,
            child: Text('${runtimeTypeLabel(r.type)} ${r.version}'),
          ),
      ],
      onChanged: (value) => setState(() => _selectedRuntime = value),
    );
  }
}