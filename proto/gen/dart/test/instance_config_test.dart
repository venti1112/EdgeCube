import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for InstanceConfig
void main() {
  final instance = InstanceConfigBuilder();
  // TODO add properties to the builder and call build()

  group(InstanceConfig, () {
    // 服务端生成
    // String id
    test('to test the property `id`', () async {
      // TODO
    });

    // String name
    test('to test the property `name`', () async {
      // TODO
    });

    // 命令行字符串(支持引号/转义,解析为参数数组 spawn,不经 shell)
    // String startCommand
    test('to test the property `startCommand`', () async {
      // TODO
    });

    // 优雅停止命令;^C 表示发送 Ctrl+C
    // String stopCommand (default value: '^C')
    test('to test the property `stopCommand`', () async {
      // TODO
    });

    // 优雅停止超时,超时升级强杀
    // int stopTimeoutSeconds (default value: 600)
    test('to test the property `stopTimeoutSeconds`', () async {
      // TODO
    });

    // 工作目录(实例 cwd,文件沙箱根)
    // String workingDirectory
    test('to test the property `workingDirectory`', () async {
      // TODO
    });

    // 额外环境变量
    // BuiltMap<String, String> environment
    test('to test the property `environment`', () async {
      // TODO
    });

    // Encoding inputEncoding
    test('to test the property `inputEncoding`', () async {
      // TODO
    });

    // Encoding outputEncoding
    test('to test the property `outputEncoding`', () async {
      // TODO
    });

    // 异常/正常退出后自动重启
    // bool autoRestart (default value: false)
    test('to test the property `autoRestart`', () async {
      // TODO
    });

    // 重启次数上限;-1 无限
    // int autoRestartMaxTimes (default value: -1)
    test('to test the property `autoRestartMaxTimes`', () async {
      // TODO
    });

    // daemon 启动时自动拉起
    // bool autoStartOnBoot (default value: false)
    test('to test the property `autoStartOnBoot`', () async {
      // TODO
    });

    // InstanceConfigTerminal terminal
    test('to test the property `terminal`', () async {
      // TODO
    });

    // InstanceType type
    test('to test the property `type`', () async {
      // TODO
    });

    // DateTime createdAt
    test('to test the property `createdAt`', () async {
      // TODO
    });

    // DateTime updatedAt
    test('to test the property `updatedAt`', () async {
      // TODO
    });

  });
}
