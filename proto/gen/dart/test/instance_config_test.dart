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

    // 命令行字符串(支持引号/转义,解析为参数数组 spawn,不经 shell);空串表示尚未配置启动命令
    // String startCommand (default value: '')
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

    // 工作目录(实例 cwd,文件沙箱根);创建/更新时缺省由 daemon 维护为实例专属目录,不随实例删除
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

    // 引用已安装运行时(runtimes 的 RuntimeInfo.id,如 java 指定 JRE 版本)。 为空表示未指定,启动命令中的可执行文件需自行可用。 
    // String runtimeId
    test('to test the property `runtimeId`', () async {
      // TODO
    });

    // 创建实例时的服务端下载链接(http/https)。仅在创建时生效: daemon 收到后自动发起下载任务(下载到实例工作目录),下载完成前实例暂不可启动。 更新实例时忽略本字段。 
    // String downloadUrl
    test('to test the property `downloadUrl`', () async {
      // TODO
    });

    // 下载目标文件名(仅与 downloadUrl 配合,创建时生效)。缺省由 daemon 从 URL 末段推导(如 https://.../paper-1.21.1-198.jar → paper-1.21.1-198.jar); 建议取 /catalog/download-info 返回的 fileName。 
    // String fileName
    test('to test the property `fileName`', () async {
      // TODO
    });

    // 下载校验值,格式 \"sha1:<hex>\" 或 \"sha256:<hex>\"(aria2 风格,不填则不做校验)。 仅与 downloadUrl 配合使用,下载完成后按算法强校验,不一致视为失败。 
    // String checksum
    test('to test the property `checksum`', () async {
      // TODO
    });

    // 创建实例触发的下载任务 id(只读)。创建后经 `GET /tasks/{jobId}` 查询下载进度;下载完成后保留,便于追溯。 
    // String downloadTaskId
    test('to test the property `downloadTaskId`', () async {
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
