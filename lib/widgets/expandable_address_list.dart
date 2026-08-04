import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';

/// 可展开/收起的 IP 地址列表组件。
///
/// 自动展示优先级最高的 IPv4 地址（Wi-Fi → 物理 → 虚拟），
/// 多余地址通过展开按钮展示。
class ExpandableAddressList extends StatefulWidget {
  /// 所有已检测到的 IPv4 地址（已按优先级排序）。
  final List<String> ips;

  /// 可选的 IPv6 地址。
  final String? ipv6;

  /// 为每个 IP 构建地址行。
  ///
  /// [ip] 为当前 IP 字符串，[isPrimary] 仅在首个（优先级最高）IP 上为 true。
  final List<Widget> Function(BuildContext context, String ip, bool isPrimary)
  itemBuilder;

  /// 为 IPv6 地址构建地址行（可选）。
  final List<Widget> Function(BuildContext context, String ipv6)? ipv6Builder;

  /// 展开按钮文案（默认使用 i18n）。
  final String? expandLabel;

  /// 收起按钮文案（默认使用 i18n）。
  final String? collapseLabel;

  const ExpandableAddressList({
    super.key,
    required this.ips,
    this.ipv6,
    required this.itemBuilder,
    this.ipv6Builder,
    this.expandLabel,
    this.collapseLabel,
  });

  @override
  State<ExpandableAddressList> createState() => _ExpandableAddressListState();
}

class _ExpandableAddressListState extends State<ExpandableAddressList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.ips.isEmpty) return const SizedBox.shrink();

    final theme = MiuixTheme.of(context);
    final primary = widget.ips.first;
    final extras = widget.ips.skip(1).toList();
    final expandLabel =
        widget.expandLabel ?? context.tr('expandableAddressList.expandLabel');
    final collapseLabel =
        widget.collapseLabel ??
        context.tr('expandableAddressList.collapseLabel');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主 IP 地址行。
        ...widget.itemBuilder(context, primary, true),

        // 多余地址展开按钮（用负偏移抵消 itemBuilder 自带底部间距）。
        if (extras.isNotEmpty)
          Transform.translate(
            offset: const Offset(0, -6),
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.colors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded ? collapseLabel : expandLabel,
                      style: theme.textStyles.footnote1.copyWith(
                        color: theme.colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 展开后展示其余 IP。
        if (_expanded)
          for (final ip in extras) ...widget.itemBuilder(context, ip, false),

        // IPv6 地址行。
        if (widget.ipv6 != null && widget.ipv6Builder != null)
          ...widget.ipv6Builder!(context, widget.ipv6!),
      ],
    );
  }
}
