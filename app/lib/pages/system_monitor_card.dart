import 'dart:async';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';

/// 系统状态监控卡(对齐 V1 server_page 的 _MonitorCard):
/// 内存 / CPU / 磁盘用量行(图标 + 标签 + 数值 + 平滑动画进度条,
/// 65% 起橙色、85% 起红色),另附网络上下行速率行。
/// 数据经 GET /monitor/snapshot 每 3 秒轮询,仅在本卡片挂载期间拉取。
class SystemMonitorCard extends ConsumerStatefulWidget {
  const SystemMonitorCard({super.key});

  @override
  ConsumerState<SystemMonitorCard> createState() => _SystemMonitorCardState();
}

class _SystemMonitorCardState extends ConsumerState<SystemMonitorCard> {
  static const _pollInterval = Duration(seconds: 3);
  /// 磁盘行展示上限(多挂载点场景折叠,避免列表过长)。
  static const _maxDiskRows = 4;

  Timer? _timer;
  MonitorSnapshot? _snapshot;
  String? _error;
  bool _loading = true;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final client = _client;
    if (client == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final snapshot =
          (await client.getMonitorApi().getMonitorSnapshot()).data!;
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // 轮询失败不弹全屏错误,仅在卡片内提示并保留上次数据
        if (!silent || _snapshot == null) _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  /// 用量配色(对齐 V1:<65 主题色 / ≥65 橙 / ≥85 红)。
  Color _colorForPercent(ColorScheme cs, double percent) {
    if (percent >= 85) return cs.error;
    if (percent >= 65) return Colors.orange;
    return cs.primary;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final snapshot = _snapshot;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: snapshot == null
            ? _header(context, loading: _loading, error: _error)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  const SizedBox(height: 12),
                  _MonitorRow(
                    icon: Icons.memory,
                    label: '内存',
                    value:
                        '${_fmtMb(snapshot.memoryUsedBytes)} / ${_fmtMb(snapshot.memoryTotalBytes)} MB',
                    percent: snapshot.memoryTotalBytes > 0
                        ? snapshot.memoryUsedBytes /
                            snapshot.memoryTotalBytes *
                            100
                        : 0,
                    colorForPercent: _colorForPercent,
                  ),
                  const SizedBox(height: 12),
                  _MonitorRow(
                    icon: Icons.speed,
                    label: 'CPU',
                    value: '${snapshot.cpuPercent.toStringAsFixed(1)}%',
                    percent: snapshot.cpuPercent,
                    colorForPercent: _colorForPercent,
                  ),
                  for (final disk in _visibleDisks(snapshot)) ...[
                    const SizedBox(height: 12),
                    _MonitorRow(
                      icon: Icons.storage_outlined,
                      label: '磁盘 ${disk.path ?? ''}',
                      value:
                          '${_fmtMb(disk.usedBytes ?? 0)} / ${_fmtMb(disk.totalBytes ?? 0)} MB',
                      percent: (disk.totalBytes ?? 0) > 0
                          ? (disk.usedBytes ?? 0) / disk.totalBytes! * 100
                          : 0,
                      colorForPercent: _colorForPercent,
                    ),
                  ],
                  if (_hiddenDiskCount(snapshot) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '另有 ${_hiddenDiskCount(snapshot)} 个挂载点未展示',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  if (snapshot.networkRxBytesPerSec != null ||
                      snapshot.networkTxBytesPerSec != null) ...[
                    const SizedBox(height: 12),
                    _NetRow(
                      rx: snapshot.networkRxBytesPerSec,
                      tx: snapshot.networkTxBytesPerSec,
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  /// 标题行;加载中/出错时占位整卡。
  Widget _header(BuildContext context, {bool loading = false, String? error}) {
    final cs = Theme.of(context).colorScheme;
    if (error != null) {
      return Row(
        children: [
          Text('系统状态', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Text(error, style: TextStyle(color: cs.error, fontSize: 12)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _load(),
            child: Icon(Icons.refresh, size: 18, color: cs.primary),
          ),
        ],
      );
    }
    return Row(
      children: [
        Text('系统状态', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (loading)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  /// 展示的磁盘行(容量降序,截断到上限;容量未知/为 0 的不展示)。
  List<MonitorSnapshotDisksInner> _visibleDisks(MonitorSnapshot snapshot) {
    final disks = snapshot.disks?.toList() ?? const <MonitorSnapshotDisksInner>[];
    final known = disks.where((d) => (d.totalBytes ?? 0) > 0).toList();
    known.sort((a, b) => b.totalBytes!.compareTo(a.totalBytes!));
    return known.take(_maxDiskRows).toList();
  }

  int _hiddenDiskCount(MonitorSnapshot snapshot) {
    final total = snapshot.disks?.length ?? 0;
    return (total - _maxDiskRows).clamp(0, total);
  }

  static String _fmtMb(int bytes) => (bytes / (1 << 20)).round().toString();
}

/// 单项监控行(对齐 V1 _MonitorRow):图标 + 标签 + 数值(按用量配色)+ 动画进度条。
class _MonitorRow extends StatelessWidget {
  const _MonitorRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.percent,
    required this.colorForPercent,
  });

  final IconData icon;
  final String label;
  final String value;
  final double percent;
  final Color Function(ColorScheme, double) colorForPercent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = colorForPercent(cs, percent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _AnimatedProgressBar(percent: percent / 100, color: color),
      ],
    );
  }
}

/// 网络速率行:无百分比语义,仅展示 ↓ 接收 / ↑ 发送速率。
class _NetRow extends StatelessWidget {
  const _NetRow({required this.rx, required this.tx});

  final int? rx;
  final int? tx;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.swap_vert, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text('网络', style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Icon(Icons.south, size: 14, color: cs.onSurfaceVariant),
        Text(
          ' ${_fmtRate(rx)}',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 10),
        Icon(Icons.north, size: 14, color: cs.onSurfaceVariant),
        Text(
          ' ${_fmtRate(tx)}',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  static String _fmtRate(int? bytesPerSec) {
    if (bytesPerSec == null) return '—';
    if (bytesPerSec < 1024) return '${bytesPerSec}B/s';
    if (bytesPerSec < 1 << 20) return '${(bytesPerSec / 1024).toStringAsFixed(1)}KB/s';
    return '${(bytesPerSec / (1 << 20)).toStringAsFixed(1)}MB/s';
  }
}

/// 带平滑过渡动画的进度条(对齐 V1 _AnimatedProgressBar:
/// TweenAnimationBuilder 在 percent 变化时 600ms easeOut 插值)。
class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = percent.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: v, end: v),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, value, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: cs.surfaceContainerHighest.withValues(alpha: .6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: SizedBox.expand(child: ColoredBox(color: color)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
