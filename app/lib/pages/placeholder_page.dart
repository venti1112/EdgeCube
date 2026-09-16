import 'package:material_ui/material_ui.dart';

/// 占位页:只为让底栏/侧栏各分支可导航,以便查看毛玻璃效果。
/// v2 实现真实业务页面时直接替换本文件的使用处。
///
/// 页面自身底色必须透明(并归零 surfaceTint / elevation),
/// 否则会盖住 HomeShell 内容区的 BackdropFilter。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      // 长列表 + 滚动,方便直观看到顶栏/内容区的模糊效果
      body: ListView.builder(
        itemCount: 40,
        itemBuilder: (context, index) => ListTile(
          leading: Icon(icon, color: cs.onSurfaceVariant),
          title: Text('$title 列表项 ${index + 1}'),
          subtitle: Text('滚动即可看到磨砂层实时透出背景'),
        ),
      ),
    );
  }
}
