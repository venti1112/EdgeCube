import 'package:flutter_test/flutter_test.dart';

import 'package:edgecube/main.dart';

void main() {
  testWidgets('底部导航显示全部标签并可切换页面', (WidgetTester tester) async {
    await tester.pumpWidget(const EdgeCubeApp());

    // 五个导航标签均存在。
    expect(find.text('服务器'), findsWidgets);
    expect(find.text('控制台'), findsWidgets);
    expect(find.text('玩家'), findsWidgets);
    expect(find.text('文件'), findsWidgets);
    expect(find.text('设置'), findsWidgets);

    // 默认显示“服务器”页内容。
    expect(find.text('在这里管理你的 Minecraft 服务器实例：创建、启动与停止。'), findsOneWidget);

    // 点击“文件”切换页面。
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(
      find.text('浏览并编辑服务器文件，如 server.properties 与世界存档。'),
      findsOneWidget,
    );
  });
}
