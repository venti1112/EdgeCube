import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:edgecube_app/connection/client.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/files/client_files.dart';
import 'package:edgecube_app/files/code_find_panel.dart';
import 'package:edgecube_app/files/file_browser.dart';
import 'package:edgecube_app/files/providers.dart';
import 'package:edgecube_app/router.dart';
import 'package:edgecube_app/files/folder_picker.dart';
import 'package:edgecube_app/files/image_viewer.dart';
import 'package:edgecube_app/files/transfer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

// ══════════════════════════════════════════════════════════════════════════
// 假的平台层：本机文件选择器
// ══════════════════════════════════════════════════════════════════════════

/// 一个「已选中的本机文件」（`PlatformFile` 是 `abstract base class`，只能继承）。
base class FakePlatformFile extends PlatformFile {
  FakePlatformFile(this.name, List<int> content)
    : bytes = Uint8List.fromList(content);

  @override
  final String name;

  final Uint8List bytes;

  @override
  Uri get uri => Uri.file('/tmp/edgecube-fake/$name');

  /// 测试用不到 `cross_file`（默认实现要 import 那个包）。
  @override
  Never get xFile => throw UnimplementedError('测试用不到 xFile');

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

/// 假的本机文件选择器：三个入口都由测试预置结果。
class FakeFilePickerPlatform extends FilePickerPlatform {
  /// `pickFiles()` 的返回值（空列表 = 用户取消）。
  List<PlatformFile> pickFilesResult = const [];

  /// `getDirectoryPath()` 的返回值（null = 用户取消）。
  String? directoryPath;

  /// `saveFile()` 收到的内容，按调用顺序。
  final List<({String fileName, Uint8List bytes})> saved = [];

  /// true 时保存对话框当作「用户取消」返回 null。
  bool cancelSave = false;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => pickFilesResult;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => directoryPath;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saved.add((fileName: fileName, bytes: bytes));
    return cancelSave ? null : Uri.file('/tmp/edgecube-fake/$fileName');
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 夹具
// ══════════════════════════════════════════════════════════════════════════

typedef FilesFixture = ({
  ProviderContainer container,
  FakeInstanceStore store,
  FakeFileTransfer transfer,
  String id,
});

/// 连上假 daemon，并把 [seed] 铺进实例的根目录。
Future<FilesFixture> bootFiles({
  void Function(FakeFileTree tree)? seed,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = FakeInstanceStore();
  final id = store.seed(name: '生存服');
  seed?.call(store.filesFor(id));
  final transfer = FakeFileTransfer(store);
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: FakeTransportFactory(instances: store).call,
    fileTransfer: transfer,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  return (container: container, store: store, transfer: transfer, id: id);
}

Future<void> pumpBrowser(WidgetTester tester, FilesFixture fixture) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(home: Scaffold(body: FileBrowser(instanceId: fixture.id))),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> rowTitles(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
    (tile.title! as Text).data!,
];

List<String> rowSubtitles(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
    (tile.subtitle! as Text).data!,
];

/// 打开某个条目的 ⋮ 菜单，点其中的 [label]。
Future<void> tapRowAction(
  WidgetTester tester,
  String path,
  String label,
) async {
  await tester.tap(find.byKey(Key('file_menu_$path')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// 输入框弹窗（新建 / 重命名 / 压缩为）填内容并确定。
Future<void> answerPrompt(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('prompt_text_field')), text);
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();
}

Future<void> confirmYes(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
  await tester.pumpAndSettle();
}

/// 压缩对话框：保持预填名，按需换格式，点「压缩」。
Future<void> confirmArchive(WidgetTester tester, {String? format}) async {
  if (format != null) {
    await tester.tap(find.byKey(const Key('archive_format_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(format).last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('archive_confirm')));
  await tester.pumpAndSettle();
}

Future<void> dismissError(WidgetTester tester) async {
  await tester.tap(find.text('知道了'));
  await tester.pumpAndSettle();
}

/// 清掉当前提示条。
///
/// ScaffoldMessenger 是**队列**：上一条还在展示时，新的一条要排队等它 ——
/// 一个用例里连着验两次提示就得先把旧的收走（或者在断言后等它自己过期）。
Future<void> clearSnacks(WidgetTester tester) async {
  ScaffoldMessenger.of(
    tester.element(find.byType(FileBrowser)),
  ).removeCurrentSnackBar();
  await tester.pumpAndSettle();
}

String textOf(FakeFileTree tree, String path) =>
    utf8.decode(tree.node(path)!.bytes!);

/// 内置编辑器的正文 controller（`re_editor` 的 `CodeEditor`，正文不是 TextField）。
CodeLineEditingController editorController(WidgetTester tester) =>
    tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;

String editorText(WidgetTester tester) => editorController(tester).text;

/// 在编辑器里「打字」—— 直接写 controller。
///
/// re_editor 的正文是自绘的 `_CodeField`（不是 `EditableText`），
/// `tester.enterText` 发到 `updateEditingValue`，而它在 re_editor 里是空实现。
/// 从 controller 写进去触发的是同一条通知链路（脏标记、撤销记录都由它驱动），
/// 被测的应用逻辑一样，只有「按键怎么送到控件」这一层被跳过。
void typeInEditor(WidgetTester tester, String text) =>
    editorController(tester).text = text;

/// 在查找/替换面板里找输入框；[index] 0 = 查找行，1 = 替换行。
Finder findPanelField(int index) => find
    .descendant(
      of: find.byType(CodeFindPanelView),
      matching: find.byType(TextField),
    )
    .at(index);

/// 当前查找匹配所在的行号（没有结果时为 null）。
int? findMatchLine(WidgetTester tester) => tester
    .widget<CodeEditor>(find.byType(CodeEditor))
    .findController!
    .currentMatchSelection
    ?.baseIndex;

/// 等查找结果算出来（面板上出现 [count] 这样的「第几个/共几个」）。
///
/// re_editor 的查找丢给 isolate 算（web 上退化成主线程异步），widget test 的
/// 假异步里回包到不了 —— 得开 `runAsync` 放行真实事件循环，再轮询等结果。
Future<void> waitForFind(WidgetTester tester, String count) async {
  for (var i = 0; i < 200; i++) {
    if (find.text(count).evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('等不到查找结果「$count」');
}

void main() {
  late FakeFilePickerPlatform picker;
  late FilePickerPlatform previousPicker;

  setUp(() {
    previousPicker = FilePickerPlatform.instance;
    picker = FakeFilePickerPlatform();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() {
    FilePickerPlatform.instance = previousPicker;
  });

  // ══════════════════════════════════════════════════════════════════════
  // 列表与导航
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('列目录：目录在前、忽略大小写排序，副标题显示类型与大小', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('server.properties', 'level-name=world');
        tree.addFile('Server.jar', 'x' * 2048);
        tree.addDir('mods');
        tree.addDir('world');
        tree.addLink('latest.log', 'logs/latest.log');
      },
    );
    await pumpBrowser(tester, fixture);

    expect(
      rowTitles(tester),
      ['mods', 'world', 'latest.log', 'Server.jar', 'server.properties'],
      reason: '目录先出，然后按名称忽略大小写（Server.jar 排在 server.properties 前）',
    );
    expect(
      rowSubtitles(tester),
      ['文件夹', '文件夹', '符号链接 → logs/latest.log', '2.0 KB', '16 B'],
    );
    expect(find.text('根目录'), findsOneWidget);
  });

  testWidgets('进出子目录：路径标签与「上一级」按钮跟着变', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('world/level.dat', 'seed');
        tree.addFile('notes.txt', 'hi');
      },
    );
    await pumpBrowser(tester, fixture);

    expect(
      tester.widget<IconButton>(find.byKey(const Key('files_up'))).onPressed,
      isNull,
      reason: '根目录没有上一级',
    );

    await tester.tap(find.byKey(const Key('file_row_world')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('files_path')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('files_path'))).data, 'world');
    expect(rowTitles(tester), ['level.dat']);

    await tester.tap(find.byKey(const Key('files_up')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('files_path'))).data, '根目录');
    expect(rowTitles(tester), ['world', 'notes.txt']);
  });

  testWidgets('空目录显示「此文件夹为空」', (tester) async {
    final fixture = await bootFiles();
    await pumpBrowser(tester, fixture);
    expect(find.text('此文件夹为空'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 新建
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('新建文件夹：列表与后端都多了一条', (tester) async {
    final fixture = await bootFiles();
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('files_new_folder')));
    await tester.pumpAndSettle();
    await answerPrompt(tester, 'config');

    expect(rowTitles(tester), ['config']);
    expect(fixture.store.filesFor(fixture.id).node('config')!.isDir, isTrue);
  });

  testWidgets('新建文件：文本类型创建后直接进编辑器', (tester) async {
    final fixture = await bootFiles();
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('files_new_file')));
    await tester.pumpAndSettle();
    await answerPrompt(tester, 'motd.txt');

    expect(find.byType(CodeEditor), findsOneWidget, reason: '.txt 该直接打开编辑器');
    expect(editorText(tester), '');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(rowTitles(tester), ['motd.txt']);
  });

  testWidgets('新建重名：弹错误对话框，后端没被动过', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addDir('mods'));
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('files_new_folder')));
    await tester.pumpAndSettle();
    await answerPrompt(tester, 'mods');

    expect(find.text('错误'), findsOneWidget);
    expect(find.text('目标位置已存在同名条目'), findsOneWidget);
    await dismissError(tester);
    expect(rowTitles(tester), ['mods']);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 重命名与删除
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('重命名：对话框带原名，改完列表与后端都更新', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('a.txt', 'a'));
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'a.txt', '重命名');
    expect(
      tester.widget<TextField>(find.byKey(const Key('prompt_text_field'))).controller!.text,
      'a.txt',
      reason: '初始值该是原名（用户多半直接覆盖）',
    );
    await answerPrompt(tester, 'b.txt');

    expect(rowTitles(tester), ['b.txt']);
    final tree = fixture.store.filesFor(fixture.id);
    expect(tree.node('a.txt'), isNull);
    expect(textOf(tree, 'b.txt'), 'a');
  });

  testWidgets('删除文件要过确认框；取消则什么都不做', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('a.txt', 'a'));
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'a.txt', '删除');
    expect(find.text('确定删除「a.txt」吗？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(rowTitles(tester), ['a.txt'], reason: '取消了就不该删');

    await tapRowAction(tester, 'a.txt', '删除');
    await confirmYes(tester);
    expect(rowTitles(tester), isEmpty);
    expect(find.text('此文件夹为空'), findsOneWidget);
    expect(fixture.store.filesFor(fixture.id).node('a.txt'), isNull);
  });

  testWidgets('删除文件夹的确认文案会提「内容一并删除」', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('mods/a.jar', 'x'));
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'mods', '删除');
    expect(
      find.text('确定删除「mods」吗？该文件夹及其内容将被删除。'),
      findsOneWidget,
    );
    await confirmYes(tester);
    expect(fixture.store.filesFor(fixture.id).node('mods'), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 多选
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('长按进多选：已选计数、全选与退出多选', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('a.txt', 'a');
        tree.addFile('b.txt', 'b');
      },
    );
    await pumpBrowser(tester, fixture);

    await tester.longPress(find.byKey(const Key('file_row_a.txt')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.byKey(const Key('file_row_b.txt')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);

    // 再点一下取消它，剩 1 项 —— 这样后面点「全选」才是真·全选
    await tester.tap(find.byKey(const Key('file_row_b.txt')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.byKey(const Key('files_select_all')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('files_select_all'))).tooltip,
      '取消全选',
      reason: '全选之后再点就是取消全选',
    );

    await tester.tap(find.byKey(const Key('files_exit_selection')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('files_selected_count')), findsNothing);
    expect(find.byKey(const Key('files_up')), findsOneWidget, reason: '退出多选该回到普通工具栏');
  });

  testWidgets('多选删除：确认后删掉选中的，回到普通工具栏', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('a.txt', 'a');
        tree.addFile('b.txt', 'b');
      },
    );
    await pumpBrowser(tester, fixture);

    await tester.longPress(find.byKey(const Key('file_row_a.txt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_select_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_delete_selected')));
    await tester.pumpAndSettle();
    expect(find.text('确定删除选中的 2 项吗？其中的文件夹及其内容将一并删除。'), findsOneWidget);
    await confirmYes(tester);

    expect(rowTitles(tester), isEmpty);
    expect(find.text('删除完成'), findsOneWidget);
    expect(find.byKey(const Key('files_up')), findsOneWidget);
  });

  testWidgets('批量移动：一项撞名时报「N 项失败」，其余的照常搬', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('a.txt', 'a');
        tree.addFile('b.txt', 'b');
        tree.addFile('dest/a.txt', '旧的');
      },
    );
    await pumpBrowser(tester, fixture);

    await tester.longPress(find.byKey(const Key('file_row_a.txt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('file_row_b.txt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_bulk_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await tester.pumpAndSettle();

    // 文件夹选择器：进 dest 再确认
    await tester.tap(
      find.descendant(
        of: find.byType(FolderPickerDialog),
        matching: find.text('dest'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('folder_picker_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('移动完成，1 项失败：a.txt'), findsOneWidget);
    await dismissError(tester);

    final tree = fixture.store.filesFor(fixture.id);
    expect(textOf(tree, 'dest/a.txt'), '旧的', reason: '撞名的那项不该被覆盖');
    expect(textOf(tree, 'dest/b.txt'), 'b');
    expect(tree.node('a.txt')!.isDir, isFalse);
    expect(rowTitles(tester), ['dest', 'a.txt']);
  });

  testWidgets('复制：目标选择器的按钮写「复制到此处」', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('a.txt', 'a'));
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'a.txt', '复制');
    expect(find.text('复制到此处'), findsOneWidget);
    expect(find.text('移动到此处'), findsNothing, reason: '移动/复制共用一个选择器，别写死成移动');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('移动文件夹时，选择器里禁掉它自己', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addDir('mods'));
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'mods', '移动');
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.descendant(
          of: find.byType(FolderPickerDialog),
          matching: find.text('mods'),
        ),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.enabled, isFalse, reason: '不能把文件夹移进它自己里面');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  // ══════════════════════════════════════════════════════════════════════
  // 搜索
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('搜索：默认只看当前目录，勾「包含子目录」后才进子目录', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('notes.txt', 'n');
        tree.addFile('world/level.dat', 'seed');
      },
    );
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('files_search')));
    await tester.pumpAndSettle();
    expect(find.text('输入名称以搜索当前目录'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('files_search_field')), 'level');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的文件或目录'), findsOneWidget, reason: '默认不递归');

    await tester.tap(find.byKey(const Key('files_search_recursive')));
    await tester.pumpAndSettle();
    expect(rowTitles(tester), ['level.dat']);
    expect(rowSubtitles(tester), ['world/level.dat'], reason: '结果里显示相对当前目录的路径');

    await tester.enterText(find.byKey(const Key('files_search_field')), '');
    await tester.pumpAndSettle();
    expect(find.text('输入名称以搜索当前目录'), findsOneWidget);
  });

  testWidgets('搜索：点结果里的目录会跳过去并退出搜索', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) => tree.addFile('world/level.dat', 'seed'),
    );
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('files_search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('files_search_field')), 'wor');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('file_row_world')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('files_search_field')), findsNothing, reason: '该退出搜索');
    expect(tester.widget<Text>(find.byKey(const Key('files_path'))).data, 'world');
    expect(rowTitles(tester), ['level.dat']);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 压缩 / 解压
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('压缩单个文件：包名去掉扩展名', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) => tree.addFile('server.properties', 'level-name=world'),
    );
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'server.properties', '压缩');
    await confirmArchive(tester);
    expect(find.text('压缩完成'), findsOneWidget);

    final tree = fixture.store.filesFor(fixture.id);
    expect(rowTitles(tester), ['server.properties', 'server.zip']);
    expect(textOf(tree, 'server.zip'), 'zip:server.properties');
  });

  testWidgets('压缩文件夹：包名保留全名并补 .zip', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('world/level.dat', 's'));
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'world', '压缩');
    await confirmArchive(tester);
    final tree = fixture.store.filesFor(fixture.id);
    expect(textOf(tree, 'world.zip'), 'zip:world');
  });

  testWidgets('压缩可选 tar.gz：后缀按格式替换', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('world/level.dat', 's'));
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'world', '压缩');
    await confirmArchive(tester, format: 'tar.gz');

    final tree = fixture.store.filesFor(fixture.id);
    expect(textOf(tree, 'world.tar.gz'), 'tar.gz:world');
    expect(rowTitles(tester), ['world', 'world.tar.gz']);
  });

  testWidgets('解压：默认子目录名去掉全部扩展名，内容还原', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) => tree.addFile('world/level.dat', 'seed'),
    );
    await pumpBrowser(tester, fixture);

    // 先用「压缩」造一个真包（走的是 UI，包名规则一并验了）
    await tapRowAction(tester, 'world', '压缩');
    await confirmArchive(tester);
    // 把原目录删掉，解压出来的目录才好断言 —— 也顺手清掉上一条提示
    // （ScaffoldMessenger 排队，不收走就看不到「解压完成」）
    await tapRowAction(tester, 'world', '删除');
    await confirmYes(tester);
    await clearSnacks(tester);

    await tapRowAction(tester, 'world.zip', '解压');
    expect(find.text('解压完成'), findsOneWidget);

    final tree = fixture.store.filesFor(fixture.id);
    expect(rowTitles(tester), ['world', 'world.zip'], reason: '解出来的目录与压缩包同时存在');
    // 包里的条目名保留了顶层目录名（`world/level.dat`），解开自然就多一层 ——
    // daemon 的 `read_zip` 就是这个语义。
    expect(textOf(tree, 'world/world/level.dat'), 'seed');
  });

  testWidgets('归档后缀都出现「解压」：tar.gz 有、普通文件没有', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('backup.tar.gz', 'x');
        tree.addFile('notes.txt', 'x');
      },
    );
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('file_menu_backup.tar.gz')));
    await tester.pumpAndSettle();
    expect(find.text('压缩'), findsOneWidget);
    expect(find.text('解压'), findsOneWidget, reason: '复合后缀要整体认出来');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('file_menu_notes.txt')));
    await tester.pumpAndSettle();
    expect(find.text('解压'), findsNothing, reason: '普通文本没有解压项');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  // ══════════════════════════════════════════════════════════════════════
  // 导入 / 导出
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('导入文件：字节原样上传到当前目录', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addDir('mods'));
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('file_row_mods')));
    await tester.pumpAndSettle();

    picker.pickFilesResult = [FakePlatformFile('new.jar', utf8.encode('jar!'))];
    await tester.tap(find.byKey(const Key('files_import')));
    await tester.pumpAndSettle();

    expect(find.text('导入完成'), findsOneWidget);
    expect(fixture.transfer.uploads.single.dir, 'mods');
    expect(fixture.transfer.uploads.single.name, 'new.jar');
    expect(textOf(fixture.store.filesFor(fixture.id), 'mods/new.jar'), 'jar!');
    expect(rowTitles(tester), ['new.jar']);
  });

  testWidgets('导入重名：服务端自动加 (1)', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('a.txt', '旧'));
    await pumpBrowser(tester, fixture);

    picker.pickFilesResult = [FakePlatformFile('a.txt', utf8.encode('新'))];
    await tester.tap(find.byKey(const Key('files_import')));
    await tester.pumpAndSettle();

    final tree = fixture.store.filesFor(fixture.id);
    expect(textOf(tree, 'a.txt'), '旧');
    expect(textOf(tree, 'a (1).txt'), '新');
  });

  testWidgets('导入文件夹：整个目录结构（含空目录）一起搬过去', (tester) async {
    final root = Directory.systemTemp.createTempSync('edgecube_import_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/empty').createSync();
    Directory('${root.path}/sub/deeper').createSync(recursive: true);

    final fixture = await bootFiles();
    await pumpBrowser(tester, fixture);

    picker.directoryPath = root.path;
    await tester.tap(find.byKey(const Key('files_import_folder')));
    await tester.pumpAndSettle();

    expect(find.text('导入完成'), findsOneWidget);
    final tree = fixture.store.filesFor(fixture.id);
    final name = root.path.split('/').last;
    expect(rowTitles(tester), [name]);
    // 空目录也得建出来 —— 否则导入「只有空子目录」的模板文件夹会什么都不剩。
    //
    // 这个用例只放目录：本机文件的字节流（`File.openRead`）是在 fake async 区里
    // 建起来的，那个区里的 IO 事件没人推进，widget 测试里永远读不完（真机上没问题）。
    // 文件那条路走「批量导入」用例 + 「本机目录遍历」里的真读校验。
    for (final dir in ['empty', 'sub', 'sub/deeper']) {
      expect(tree.node('$name/$dir')?.isDir, isTrue, reason: '$dir 该被建出来');
    }
  });

  testWidgets('导出单个文件：另存为拿到原文件字节', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('a.txt', '内容'));
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'a.txt', '导出');

    expect(find.text('导出完成'), findsOneWidget);
    expect(picker.saved.single.fileName, 'a.txt');
    expect(utf8.decode(picker.saved.single.bytes), '内容');
  });

  testWidgets('导出文件夹：另存为名带 .zip，包里是它的子项', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('world/level.dat', 's'));
    await pumpBrowser(tester, fixture);

    await tapRowAction(tester, 'world', '导出');

    expect(picker.saved.single.fileName, 'world.zip');
    expect(utf8.decode(picker.saved.single.bytes), 'zip:world/level.dat');
    expect(fixture.transfer.downloads.single.path, 'world');
  });

  testWidgets('多选导出：先打 zip 再下载，临时包随后删掉', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('a.txt', 'a');
        tree.addFile('b.txt', 'b');
      },
    );
    await pumpBrowser(tester, fixture);

    await tester.longPress(find.byKey(const Key('file_row_a.txt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('file_row_b.txt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_bulk_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();

    expect(picker.saved.single.fileName, '导出.zip');
    expect(utf8.decode(picker.saved.single.bytes), 'zip:a.txt+b.txt');
    expect(fixture.transfer.downloads.single.path, '导出.zip');
    expect(
      fixture.store.filesFor(fixture.id).node('导出.zip'),
      isNull,
      reason: '临时包下载完就该删掉',
    );
    expect(rowTitles(tester), ['a.txt', 'b.txt']);
    expect(find.byKey(const Key('files_up')), findsOneWidget, reason: '导出后退出多选');
  });

  testWidgets('取消保存对话框：不提示「导出完成」', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('a.txt', 'a'));
    await pumpBrowser(tester, fixture);

    picker.cancelSave = true;
    await tapRowAction(tester, 'a.txt', '导出');
    expect(find.text('导出完成'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 内置编辑器
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('非白名单的二进制文件：菜单里能编辑，非 UTF-8 走「强制打开」', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) =>
          tree.addBytes('mods/binary.jar', [0x50, 0x4B, 0xFF, 0xFE]),
    );
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('file_menu_mods')));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsNothing, reason: '目录没有编辑项');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('file_row_mods')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('file_row_mods/binary.jar')));
    await tester.pumpAndSettle();
    expect(
      find.byType(CodeEditor),
      findsNothing,
      reason: '.jar 不在白名单里，点行不该直接进编辑器',
    );

    await tapRowAction(tester, 'mods/binary.jar', '编辑');
    expect(find.text('binary.jar'), findsOneWidget, reason: '编辑本身对任何文件都开放');
    expect(
      find.textContaining('可能不是 UTF-8 文本'),
      findsOneWidget,
      reason: '非文本文件：先报编码错，再让用户决定',
    );

    await tester.tap(find.byKey(const Key('editor_force_open')));
    await tester.pumpAndSettle();
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(editorText(tester), latin1.decode([0x50, 0x4B, 0xFF, 0xFE]));

    typeInEditor(tester, '改过了');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor_save')));
    await tester.pumpAndSettle();
    expect(
      textOf(fixture.store.filesFor(fixture.id), 'mods/binary.jar'),
      '改过了',
      reason: '强制打开后照样能编辑保存（按 UTF-8 写回）',
    );
  });

  testWidgets('打开文本文件：内容进输入框，标题不带标记', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('motd.txt', '你好\n世界'));
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('file_row_motd.txt')));
    await tester.pumpAndSettle();

    expect(find.text('motd.txt'), findsOneWidget);
    expect(editorText(tester), '你好\n世界');
    expect(find.byKey(const Key('editor_force_open')), findsNothing);
  });

  testWidgets('改动后标题带 •，保存写回后端并提示「已保存」', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('motd.txt', '旧'));
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('file_row_motd.txt')));
    await tester.pumpAndSettle();
    typeInEditor(tester, '新');
    await tester.pumpAndSettle();

    expect(find.text('motd.txt •'), findsOneWidget, reason: '有未保存改动时标题带标记');
    await tester.tap(find.byKey(const Key('editor_save')));
    await tester.pumpAndSettle();

    expect(find.text('已保存'), findsOneWidget);
    expect(find.text('motd.txt'), findsOneWidget, reason: '保存后标记消失');
    expect(textOf(fixture.store.filesFor(fixture.id), 'motd.txt'), '新');
  });

  testWidgets('非 UTF-8 文件：报错后可强制按 latin1 打开', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) => tree.addBytes('gbk.txt', [0xC4, 0xE3, 0xBA, 0xC3]),
    );
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('file_row_gbk.txt')));
    await tester.pumpAndSettle();
    expect(find.textContaining('可能不是 UTF-8 文本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor_force_open')));
    await tester.pumpAndSettle();
    expect(editorText(tester), latin1.decode([0xC4, 0xE3, 0xBA, 0xC3]));
  });

  testWidgets('带着未保存改动返回：选「不保存」才退出且不写回', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('motd.txt', '旧'));
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('file_row_motd.txt')));
    await tester.pumpAndSettle();
    typeInEditor(tester, '改了但不存');
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('文件有未保存的更改。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor_discard')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('files_path')), findsOneWidget, reason: '该回到浏览器');
    expect(textOf(fixture.store.filesFor(fixture.id), 'motd.txt'), '旧');
  });

  testWidgets('查找面板：数出匹配数、能跳到下一个、能关掉', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) => tree.addFile('motd.txt', 'aaa\nbbb\naaa'),
    );
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('file_row_motd.txt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor_find')));
    await tester.pumpAndSettle();
    expect(find.byType(CodeFindPanelView), findsOneWidget, reason: '查找键该拉起面板');

    await tester.enterText(findPanelField(0), 'aaa');
    await waitForFind(tester, '1/2');
    expect(findMatchLine(tester), 0, reason: '两处 aaa，当前停在第 0 行那一处');

    await tester.tap(find.byTooltip('下一个匹配'));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    expect(findMatchLine(tester), 2);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    // 关掉后 findBuilder 仍会调一次（re_editor 照常建这个 widget），只是零尺寸
    expect(tester.getSize(find.byType(CodeFindPanelView)).height, 0);
    expect(find.text('1/2'), findsNothing);
  });

  testWidgets('替换面板：切到替换模式能全部替换', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) => tree.addFile('motd.txt', 'aaa\nbbb\naaa'),
    );
    await pumpBrowser(tester, fixture);

    await tester.tap(find.byKey(const Key('file_row_motd.txt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor_find')));
    await tester.pumpAndSettle();
    await tester.enterText(findPanelField(0), 'aaa');
    await waitForFind(tester, '1/2');

    await tester.tap(find.byTooltip('替换'));
    await tester.pumpAndSettle();
    await tester.enterText(findPanelField(1), 'ccc');
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(CodeFindPanelView),
        matching: find.byTooltip('全部替换'),
      ),
    );
    await tester.pumpAndSettle();

    expect(editorText(tester), 'ccc\nbbb\nccc');
    expect(find.text('motd.txt •'), findsOneWidget, reason: '替换也是改动，标题该带标记');
  });

  // ══════════════════════════════════════════════════════════════════════
  // HTTP 传输
  // ══════════════════════════════════════════════════════════════════════

  group('HttpFileTransfer', () {
    test('download：拼对 URL（带令牌）、回原始字节', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response.bytes(utf8.encode('世界存档'), 200);
      });
      final transfer = HttpFileTransfer(_settings, client: client);

      final bytes = await transfer.download('inst-1', 'world/level.dat');

      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/instances/inst-1/files/download');
      expect(seen.url.queryParameters, {'path': 'world/level.dat', 'token': 't'});
      expect(utf8.decode(bytes), '世界存档');
    });

    test('download：实例 id 与路径都做 URL 编码', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response.bytes(const [], 200);
      });
      final transfer = HttpFileTransfer(_settings, client: client);

      await transfer.download('inst 1', '存档/level.dat');

      expect(seen.url.queryParameters['path'], '存档/level.dat');
      expect(seen.url.toString(), contains('inst%201'));
    });

    test('download：错误信封翻成 DaemonException', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'ok': false,
              'error': {'code': 'file_not_found', 'message': '没有 `a.txt` 这个条目'},
            }),
          ),
          404,
        ),
      );
      final transfer = HttpFileTransfer(_settings, client: client);

      await expectLater(
        transfer.download('i', 'a.txt'),
        throwsA(
          isA<DaemonException>()
              .having((e) => e.code, 'code', 'file_not_found')
              .having((e) => e.message, 'message', contains('a.txt')),
        ),
      );
    });

    test('download：不是 JSON 的错误体走 HTTP 兜底', () async {
      final client = MockClient((_) async => http.Response('502 bad gateway', 502));
      final transfer = HttpFileTransfer(_settings, client: client);

      await expectLater(
        transfer.download('i', 'a.txt'),
        throwsA(
          isA<DaemonException>().having((e) => e.code, 'code', 'http_502'),
        ),
      );
    });

    test('upload：POST 到 upload、流式发字节、解析落盘后的条目', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'result': {
              'entry': {
                'name': 'a (1).txt',
                'path': 'mods/a (1).txt',
                'is_dir': false,
                'is_link': false,
                'size': 5,
              },
            },
          }),
          200,
        );
      });
      final transfer = HttpFileTransfer(_settings, client: client);

      // ⚠️ **一定要用 `Uint8List`**，别用 `Stream<List<int>>`：
      // 真实调用方（`pickFiles().readAsByteStream()` / `File.openRead()`）产出的都是
      // `Uint8List`，而 `Stream.pipe` 是按**运行期**类型参数检查的 —— 用
      // `Stream<List<int>>` 写用例恰好绕过那个检查，真实上传才会炸
      //（「_StreamSinkWrapper<List<int>> is not a subtype of StreamConsumer<Uint8List>」）。
      final entry = await transfer.upload(
        'i',
        dir: 'mods',
        name: 'a.txt',
        content: Stream.value(Uint8List.fromList(utf8.encode('hello'))),
        length: 5,
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/instances/i/files/upload');
      expect(seen.url.queryParameters, {'path': 'mods', 'name': 'a.txt', 'token': 't'});
      expect(seen.headers['content-type'], 'application/octet-stream');
      expect(utf8.decode(seen.bodyBytes), 'hello');
      expect(entry.name, 'a (1).txt');
      expect(entry.path, 'mods/a (1).txt');
      expect(entry.isDir, isFalse);
    });

    test('upload：分块的 Uint8List 流也能边读边发（真实文件就是这样）', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'result': {
              'entry': {
                'name': 'big.bin',
                'path': 'big.bin',
                'is_dir': false,
                'is_link': false,
                'size': 10,
              },
            },
          }),
          200,
        );
      });
      final transfer = HttpFileTransfer(_settings, client: client);

      // 多个 chunk（`File.openRead()` 就是分块给的），而且每块都是 Uint8List
      final controller = StreamController<Uint8List>();
      unawaited(() async {
        controller.add(Uint8List.fromList(utf8.encode('hello')));
        controller.add(Uint8List.fromList(utf8.encode('world')));
        await controller.close();
      }());

      final entry = await transfer.upload(
        'i',
        dir: '',
        name: 'big.bin',
        content: controller.stream,
        length: 10,
      );

      expect(utf8.decode(seen.bodyBytes), 'helloworld');
      expect(entry.name, 'big.bin');
    });

    test('upload：overwrite 进查询串', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'result': {
              'entry': {'name': 'a.txt', 'path': 'a.txt', 'is_dir': false, 'is_link': false},
            },
          }),
          200,
        );
      });
      final transfer = HttpFileTransfer(_settings, client: client);

      await transfer.upload(
        'i',
        dir: '',
        name: 'a.txt',
        content: Stream.value(Uint8List(0)),
        overwrite: true,
      );

      expect(seen.url.queryParameters, {'path': '', 'name': 'a.txt', 'overwrite': 'true', 'token': 't'});
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 回到文件页时自动比对
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('回到文件页：目录变了就静默刷新', (tester) async {
    final fixture = await bootFiles(seed: (tree) => tree.addFile('a.txt', 'a'));
    await pumpBrowser(tester, fixture);
    expect(rowTitles(tester), ['a.txt']);

    // 在「别处」新建了一个文件（另一个客户端，或者文件页之外的操作）
    fixture.store.filesFor(fixture.id).addFile('b.txt', 'b');

    // 切回文件页签时 HomeShell 会 bump 这条信号
    fixture.container.read(filesRefreshProvider.notifier).bump();
    await tester.pumpAndSettle();

    expect(rowTitles(tester), ['a.txt', 'b.txt'], reason: '回到页面要看到新文件');
  });

  testWidgets('回到文件页：目录没变就不重建（不转圈、列表照旧）', (tester) async {
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('a.txt', 'a');
        tree.addFile('b.txt', 'b');
      },
    );
    await pumpBrowser(tester, fixture);
    final before = fixture.store.calls['instance.files.list'] ?? 0;

    fixture.container.read(filesRefreshProvider.notifier).bump();
    await tester.pumpAndSettle();

    // 确实去比对了一次……
    expect(fixture.store.calls['instance.files.list'], before + 1);
    // ……但**没有转圈**（静默），列表也没动 —— 比对结果一模一样时连 setState
    // 都不做，滚动位置与选中态都不会被打断
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(rowTitles(tester), ['a.txt', 'b.txt']);
  });

  testWidgets('切回「文件」页签会自动比对当前目录', (tester) async {
    // 这条走**真外壳 + 真路由**：验的是「页签切换」这个触发点本身，
    // 而不是我在测试里手动 bump（手动 bump 只能证明订阅端是通的）
    final fixture = await bootFiles(seed: (tree) => tree.addFile('a.txt', 'a'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp.router(
          routerConfig: fixture.container.read(routerProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 先去一次文件页，让浏览器建起来
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(rowTitles(tester), ['a.txt']);

    // 回服务器页，然后在「别处」新建一个文件
    await tester.tap(find.text('服务器'));
    await tester.pumpAndSettle();
    fixture.store.filesFor(fixture.id).addFile('b.txt', 'b');

    // 再切回文件页 —— 自动比对就是在这时候跑的
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();

    expect(rowTitles(tester), ['a.txt', 'b.txt']);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 图片查看器（点图片文件全屏预览）
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('点图片文件打开查看器，下载正确的实例与路径', (tester) async {
    // 1×1 透明 PNG（合法图片字节；断言不依赖它真的画出来）
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    );
    final fixture = await bootFiles(seed: (tree) => tree.addBytes('photo.png', png));
    await pumpBrowser(tester, fixture);
    expect(rowTitles(tester), ['photo.png']);

    await tester.tap(find.text('photo.png'));
    await tester.pumpAndSettle();

    // 打开的是查看器，AppBar 标题 = 文件名
    expect(find.byType(ImageViewerPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'photo.png'), findsOneWidget);
    // 下载走的是「这个实例 + 相对实例根的路径」，不是别的
    expect(
      fixture.transfer.downloads,
      [(instanceId: fixture.id, path: 'photo.png')],
    );
  });

  testWidgets('点图片之外的文件不打开查看器（分派优先级：图片在文本编辑之前）', (tester) async {
    // .txt 应该照旧进文本编辑器，而不是查看器；.dat 点一下什么都不做
    final fixture = await bootFiles(
      seed: (tree) {
        tree.addFile('note.txt', 'hello');
        tree.addFile('blob.dat', 'x');
      },
    );
    await pumpBrowser(tester, fixture);

    await tester.tap(find.text('note.txt'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsNothing, reason: 'txt 不进查看器');
    // 关掉编辑器回到列表
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('blob.dat'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsNothing, reason: '未知扩展名不打开任何东西');
  });

  // ══════════════════════════════════════════════════════════════════════
  // 客户端本机目录（导入文件夹的数据源）
  // ══════════════════════════════════════════════════════════════════════

  group('本机目录遍历', () {
    test('父目录排在子项前面，符号链接跳过', () async {
      final root = Directory.systemTemp.createTempSync('edgecube_walk_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/sub/deep').createSync(recursive: true);
      File('${root.path}/sub/x.txt').writeAsStringSync('xx');
      File('${root.path}/y.txt').writeAsStringSync('yy');
      Link('${root.path}/loop').createSync(root.path);

      picker.directoryPath = root.path;
      final pick = await pickLocalFolder();

      expect(pick, isNotNull);
      expect(pick!.name, root.path.split('/').last);
      final paths = [for (final item in pick.items) item.relativePath];
      expect(paths.toSet(), {'sub', 'sub/deep', 'sub/x.txt', 'y.txt'});
      expect(
        paths.indexOf('sub'),
        lessThan(paths.indexOf('sub/x.txt')),
        reason: '父目录必须先出现，服务端才好按顺序建目录',
      );
      expect(paths, isNot(contains('loop')), reason: '符号链接不跟（免得绕圈）');

      final file = pick.items.firstWhere((i) => i.relativePath == 'sub/x.txt');
      expect(file.isDir, isFalse);
      expect(file.length, 2);
      expect(file.name, 'x.txt');
      expect(file.dir, 'sub');
      expect(utf8.decode(await _readAll(file.read())), 'xx');
      expect(
        pick.items.firstWhere((i) => i.relativePath == 'sub/deep').isDir,
        isTrue,
      );
    });

    test('选中的文件夹路径带尾斜杠时，名字也不为空（导入文件夹踩过）', () async {
      final root = Directory.systemTemp.createTempSync('edgecube_walk_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/a.txt').writeAsStringSync('a');

      // XDG 门户给文件夹的 URI 常带尾斜杠，`toFilePath()` 会原样保留它。
      // 以前 `_basename` 不剪尾斜杠，这里会得到空名 → daemon 报「名称不能为空」。
      picker.directoryPath = '${root.path}/';
      final pick = await pickLocalFolder();

      expect(pick, isNotNull);
      expect(pick!.name, isNotEmpty, reason: '带尾斜杠的路径也要能取到名字');
      expect(pick.name, root.path.split('/').last);
      expect(pick.items.single.name, 'a.txt');
    });

    test('取消选择返回 null', () async {
      picker.directoryPath = null;
      expect(await pickLocalFolder(), isNull);
    });

    test('这台平台支持导入文件夹', () {
      expect(folderImportSupported(), isTrue);
    });
  });
}

Future<List<int>> _readAll(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return bytes;
}
