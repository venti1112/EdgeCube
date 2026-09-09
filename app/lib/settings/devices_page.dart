import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../pages/api_error.dart';
import '../server/server_service.dart';

/// 已登录设备管理页:列出 /auth/tokens 已登录设备列表,
/// 支持吊销指定设备的长期 token(吊销后该设备立即断开)。
class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  List<DeviceInfo>? _devices;
  bool _loading = true;
  String? _error;
  String? _revokingId;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  /// 当前设备 id(登录时回写,存储于会话内存)。
  String? get _currentDeviceId => ref.read(sessionProvider)?.deviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final list = (await client.getAuthApi().listDevices()).data!;
      if (!mounted) return;
      setState(() {
        _devices = list.toList();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 重命名设备:弹出名称编辑对话框,调用 PATCH /auth/tokens/{deviceId}。
  Future<void> _rename(DeviceInfo device) async {
    final controller = TextEditingController(text: device.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名设备'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: const InputDecoration(
            labelText: '设备名称',
            hintText: '输入新的设备名称',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == device.name) return;
    final client = _client;
    if (client == null) return;
    try {
      await client.getAuthApi().renameDevice(
            deviceId: device.id,
            renameDeviceRequest:
                RenameDeviceRequest((b) => b..name = newName),
          );
      if (!mounted) return;
      _snack('已重命名为「$newName」');
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack(apiErrorMessage(e));
    }
  }

  /// 吊销指定设备 token:确认后调用 /auth/tokens/{deviceId} DELETE。
  /// 吊销当前设备时本机 token 立即失效,断开连接并退回服务器管理页。
  Future<void> _revoke(DeviceInfo device) async {
    if (_revokingId != null) return;
    final isCurrent = device.id == _currentDeviceId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('吊销设备'),
        content: Text(isCurrent
            ? '即将吊销当前设备「${device.name}」的登录凭证,'
                '吊销后本设备将立即断开连接,需要重新登录。'
            : '确定吊销设备「${device.name}」的登录凭证吗?\n'
                '该设备将立即断开,需重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('吊销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final client = _client;
    if (client == null) return;
    setState(() => _revokingId = device.id);
    try {
      await client.getAuthApi().revokeDevice(deviceId: device.id);
      if (!mounted) return;
      if (isCurrent) {
        _snack('当前设备已吊销,连接已断开');
        ref.read(serverServiceProvider).disconnect();
        if (mounted) context.go('/settings/servers');
      } else {
        _snack('已吊销设备「${device.name}」');
        _load();
      }
    } catch (e) {
      if (!mounted) return;
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('已登录设备'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _loading && devices == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: devices == null
                  ? _errorView()
                  : devices.isEmpty
                      ? _emptyView()
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: devices.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            final device = devices[index];
                            return _deviceTile(device);
                          },
                        ),
            ),
    );
  }

  Widget _deviceTile(DeviceInfo device) {
    final cs = Theme.of(context).colorScheme;
    final isCurrent = device.id == _currentDeviceId;
    final revoking = _revokingId == device.id;
    return ListTile(
      leading: Icon(
        _deviceIcon(device.deviceType),
        color: isCurrent ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              device.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '当前设备',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.onPrimaryContainer),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          '设备ID: ${_shortDeviceId(device.id)}',
          '创建于 ${_fmtDateTime(device.createdAt)}',
          if (device.lastSeenAt != null)
            '最近活动 ${_fmtDateTime(device.lastSeenAt)}',
        ].join(' · '),
      ),
      trailing: revoking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '重命名',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _rename(device),
                ),
                IconButton(
                  tooltip: '吊销设备',
                  icon: const Icon(Icons.logout),
                  color: cs.error,
                  onPressed: () => _revoke(device),
                ),
              ],
            ),
      onTap: null,
    );
  }

  /// 设备类别图标:电脑 / 手机 / 浏览器;旧记录无类型时按电脑显示。
  static IconData _deviceIcon(DeviceType? type) {
    return switch (type) {
      DeviceType.mobile => Icons.smartphone_outlined,
      DeviceType.web => Icons.language_outlined,
      _ => Icons.desktop_windows_outlined,
    };
  }

  /// 显示设备 ID 的短标识:保留前 8 位,便于区分又不过长。
  static String _shortDeviceId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}…';
  }

  Widget _errorView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.cloud_off, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(child: Text('加载失败:${_error ?? '(未知错误)'}')),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: _load, child: const Text('重试'))),
      ],
    );
  }

  Widget _emptyView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.devices_outlined, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '暂无已登录设备',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  /// DateTime → 本地时间 "yyyy-MM-dd HH:mm";null 显示未知。
  static String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '未知';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}