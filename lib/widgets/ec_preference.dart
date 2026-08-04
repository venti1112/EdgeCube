import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'miuix_dialog.dart';

/// 单选弹窗：一列单选项，点中即返回该项并关闭。
///
/// 取代原先「SimpleDialog + 一堆带单选图标的 ListTile」的重复写法
/// （日志等级、Java 环境优先级等处）。[hint] 会以脚注样式显示在列表下方。
Future<T?> showMiuixSingleChoice<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T? selected,
  required String Function(BuildContext context, T option) labelOf,
  String Function(BuildContext context, T option)? summaryOf,
  String? hint,
}) {
  return showMiuixDialog<T>(
    context: context,
    title: title,
    builder: (ctx) {
      final theme = MiuixTheme.of(ctx);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            MiuixRadioButtonPreference(
              title: labelOf(ctx, option),
              summary: summaryOf?.call(ctx, option),
              selected: option == selected,
              insideMargin: const EdgeInsets.symmetric(vertical: 10),
              onClick: () => Navigator.of(ctx).pop(option),
            ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            MiuixText(
              hint,
              style: theme.textStyles.footnote1,
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ],
        ],
      );
    },
  );
}

/// 设置项行首的图标，供 Miuix 各 Preference 组件的 `startAction` 使用。
///
/// Miuix 的 Preference 族本身不带前置图标槽的默认样式，但保留原有图标能维持
/// 用户既有的信息线索。统一在此处理尺寸与右侧留白，避免各页面各写一套。
Widget prefIcon(IconData icon, {Color? color}) {
  return Padding(
    padding: const EdgeInsets.only(right: 16),
    child: MiuixIcon(icon: icon, size: 22, tint: color),
  );
}

/// 设置页的标准脚手架：小标题栏 + 可滚动的偏好项列表。
///
/// [isTab] 用于区分两类使用场景：
/// - `false`（默认）：由 Navigator 压入的独立子页面，占满整屏，顶栏带返回按钮；
/// - `true`：HomeShell 的标签页，外层 [MiuixScaffold] 已处理底部导航栏留白，
///   故把 `contentWindowInsets` 清零，否则系统底部安全区会被重复计入。
class EcSettingsPage extends StatelessWidget {
  const EcSettingsPage({
    super.key,
    required this.title,
    required this.children,
    this.isTab = false,
    this.actions,
  });

  final String title;
  final List<Widget> children;
  final bool isTab;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      contentWindowInsets: isTab ? EdgeInsets.zero : null,
      topBar: MiuixSmallTopAppBar(
        title: title,
        navigationIcon: isTab ? null : const EcBackButton(),
        actions: actions,
      ),
      content: (padding) => ListView(
        padding: padding.copyWith(bottom: padding.bottom + 24),
        children: children,
      ),
    );
  }
}

/// 带标题头的分组卡片，替代原先「Card + 自绘标题行」的重复写法
/// （FTP / SSH / MCP 等服务页共用同一套结构）。
///
/// [trailing] 放在标题行右端，常用于状态标签。卡片内边距归零，由 [children]
/// 自行控制——Miuix 的 Preference 组件自带内边距，再套一层会过宽。
class EcSectionCard extends StatelessWidget {
  const EcSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
    this.colors,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;
  final Widget? trailing;
  final MiuixCardColors? colors;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      colors: colors,
      insideMargin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  MiuixIcon(icon: icon!, size: 20, tint: theme.colors.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: MiuixText(
                    title,
                    style: theme.textStyles.subtitle,
                    color: theme.colors.primary,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 卡片包裹的可点击行，替代「Card + ListTile + chevron_right」的旧组合。
///
/// 列表项形态在各选择页（服务端类型、版本号、模组列表等）反复出现，统一在此。
class EcCardTile extends StatelessWidget {
  const EcCardTile({
    super.key,
    required this.title,
    this.summary,
    this.leading,
    this.trailing,
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  final String title;
  final String? summary;
  final Widget? leading;
  final List<Widget>? trailing;
  final VoidCallback? onTap;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: MiuixCard(
        insideMargin: EdgeInsets.zero,
        child: MiuixArrowPreference(
          title: title,
          summary: summary,
          startAction: leading == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: leading,
                ),
          endActions: trailing,
          onClick: onTap,
        ),
      ),
    );
  }
}

/// 加载失败时的「图标 + 说明 + 重试」占位块。
class EcErrorRetry extends StatelessWidget {
  const EcErrorRetry({
    super.key,
    required this.message,
    required this.retryLabel,
    this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MiuixIcon(
              icon: Icons.error_outline,
              size: 48,
              tint: theme.colors.error,
            ),
            const SizedBox(height: 16),
            MiuixText(
              message,
              textAlign: TextAlign.center,
              color: theme.colors.error,
            ),
            const SizedBox(height: 16),
            MiuixButton(
              onPressed: onRetry,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片标题行右端的状态标签（如「运行中」）。
class EcStatusChip extends StatelessWidget {
  const EcStatusChip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colors.primary.withValues(alpha: 0.12),
        shape: const MiuixSquircleBorder(cornerRadius: 12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: MiuixText(
          text,
          style: theme.textStyles.footnote2,
          color: theme.colors.primary,
        ),
      ),
    );
  }
}

/// 分段标签 + 可滑动内容页，替代 Material 的 `TabBar` + `TabBarView`。
///
/// **Miuix 没有 TabBarView 的对应物**：[MiuixTabRow] 只是个分段控制器，不带内容
/// 联动。这里用 [PageView] 补上，并双向同步选中项（点标签 → 翻页；滑动 → 更新
/// 标签），避免每个用到标签页的地方各写一遍。
/// 受控组件：选中项由外部持有，与 [MiuixTabRow] 本身的受控风格一致，
/// 也让「创建成功后跳回第一页」这类外部驱动的切换成为可能。
class EcTabbedView extends StatefulWidget {
  const EcTabbedView({
    super.key,
    required this.tabs,
    required this.children,
    required this.index,
    required this.onTabChanged,
    this.tabPadding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  }) : assert(tabs.length == children.length, 'tabs 与 children 数量必须一致');

  final List<String> tabs;
  final List<Widget> children;
  final int index;
  final ValueChanged<int> onTabChanged;
  final EdgeInsets tabPadding;

  @override
  State<EcTabbedView> createState() => _EcTabbedViewState();
}

class _EcTabbedViewState extends State<EcTabbedView> {
  late final PageController _pageController = PageController(
    initialPage: widget.index,
  );

  @override
  void didUpdateWidget(EcTabbedView old) {
    super.didUpdateWidget(old);
    // 外部改了选中项（如创建成功后跳回列表页）：把 PageView 一并带过去。
    if (widget.index != old.index && _pageController.hasClients) {
      final current = _pageController.page?.round();
      if (current != widget.index) {
        _pageController.animateToPage(
          widget.index,
          duration: const Duration(milliseconds: 260),
          curve: MiuixMotion.standardDecelerate,
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: widget.tabPadding,
          child: MiuixTabRow(
            tabs: widget.tabs,
            selectedTabIndex: widget.index,
            onTabSelected: widget.onTabChanged,
          ),
        ),
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) {
              if (i != widget.index) widget.onTabChanged(i);
            },
            children: widget.children,
          ),
        ),
      ],
    );
  }
}

/// 顶栏返回按钮：Miuix 的 TopAppBar 不像 Material AppBar 那样自动生成返回键，
/// 需要显式传入 `navigationIcon`。
class EcBackButton extends StatelessWidget {
  const EcBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return MiuixIconButton(
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      child: const MiuixIcon(icon: Icons.arrow_back),
    );
  }
}

/// 与 [EcTextField] 观感一致的下拉选择字段，替代 `DropdownButtonFormField`。
///
/// Miuix 只提供整行的 `MiuixOverlayDropdownPreference`（自带标题+分割线，
/// 适合设置列表），不适合放进表单行里与输入框并排。这里复用 Miuix 的下拉浮层
/// （[MiuixOverlayDropdownMenu]），外观则对齐 EcTextField 的超椭圆输入框样式，
/// 使属性编辑页里「输入框 + 下拉框」混排时视觉统一。
class EcDropdownField extends StatelessWidget {
  const EcDropdownField({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.label,
    this.helperText,
    this.suffixIcon,
    this.enabled = true,
  });

  /// 候选项文案。
  final List<String> items;

  /// 当前选中下标；越界（如 -1）表示未选中，显示占位文案。
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? label;
  final String? helperText;
  final Widget? suffixIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = MiuixTextFieldDefaults.textFieldColors(context);
    final hasValue = selectedIndex >= 0 && selectedIndex < items.length;

    // 用 IconDropdownMenu 而非 DropdownMenu：后者是自带标题的整行组件，
    // 没有 child 槽，无法包裹自定义的输入框外观。
    final field = MiuixOverlayIconDropdownMenu(
      enabled: enabled,
      backgroundColor: Colors.transparent,
      cornerRadius: MiuixTextFieldDefaults.cornerRadius,
      minHeight: 0,
      minWidth: 0,
      entry: MiuixDropdownEntry(
        items: [
          for (var i = 0; i < items.length; i++)
            MiuixDropdownItem(
              text: items[i],
              selected: i == selectedIndex,
              onClick: () => onSelected(i),
            ),
        ],
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.backgroundColor,
          shape: const MiuixSquircleBorder(
            cornerRadius: MiuixTextFieldDefaults.cornerRadius,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: MiuixText(
                  hasValue ? items[selectedIndex] : (label ?? ''),
                  style: theme.textStyles.main,
                  color: hasValue
                      ? theme.colors.onBackground
                      : colors.labelColor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?suffixIcon,
              const SizedBox(width: 4),
              MiuixIcon(icon: Icons.arrow_drop_down, tint: colors.labelColor),
            ],
          ),
        ),
      ),
    );

    if (helperText == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: MiuixText(
            helperText!,
            style: theme.textStyles.footnote1,
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }
}
