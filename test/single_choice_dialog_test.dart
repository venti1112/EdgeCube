import 'package:edgecube/widgets/ec_preference.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把页面包进最小可用的 Miuix 主题 + Navigator，供弹窗测试使用。
Widget _host(void Function(BuildContext context) onPressed) {
  return MiuixTheme(
    data: MiuixThemeData.light(),
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: MiuixButton(
              onPressed: () => onPressed(context),
              child: const MiuixText('打开'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('选项很少时全部渲染（弹窗高度自适应）', (tester) async {
    final options = List.generate(5, (i) => '选项 $i');
    await tester.pumpWidget(
      _host(
        (context) => showMiuixSingleChoice<String>(
          context: context,
          title: '选择',
          options: options,
          selected: null,
          labelOf: (ctx, option) => option,
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(MiuixRadioButtonPreference), findsNWidgets(5));
  });

  testWidgets('上千条选项时只构建可见行，且能滚动到末尾并选中', (tester) async {
    final options = List.generate(1200, (i) => '版本 $i');
    String? picked;
    await tester.pumpWidget(
      _host(
        (context) => showMiuixSingleChoice<String>(
          context: context,
          title: '选择游戏版本',
          options: options,
          selected: null,
          labelOf: (ctx, option) => option,
        ).then((value) => picked = value),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 关键断言：惰性构建，绝不该出现 1200 行一次性构建。
    final builtRows = tester.widgetList(
      find.byType(MiuixRadioButtonPreference),
    ).length;
    expect(builtRows, lessThan(40));

    // 惰性列表必须真的能滑到末尾（而不是被裁掉）。
    await tester.scrollUntilVisible(
      find.text('版本 1199'),
      400,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 200,
    );
    await tester.tap(find.text('版本 1199'));
    await tester.pumpAndSettle();

    expect(picked, '版本 1199');
    expect(find.byType(MiuixRadioButtonPreference), findsNothing);
  });
}
