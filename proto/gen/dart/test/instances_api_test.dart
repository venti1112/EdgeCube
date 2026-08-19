import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for InstancesApi
void main() {
  final instance = EdgecubeApiClient().getInstancesApi();

  group(InstancesApi, () {
    // 创建实例
    //
    //Future<InstanceConfig> createInstance(InstanceConfig instanceConfig) async
    test('test createInstance', () async {
      // TODO
    });

    // 删除实例
    //
    // 运行中的实例必须先停止;仅删除配置与进程,不删除工作目录。
    //
    //Future deleteInstance(String instanceId) async
    test('test deleteInstance', () async {
      // TODO
    });

    // 导出实例(打包工作目录为归档)
    //
    // 进度经 WS `download/progress` 推送,完成后返回下载地址。
    //
    //Future<JobAccepted> exportInstance(String instanceId, { ExportRequest exportRequest }) async
    test('test exportInstance', () async {
      // TODO
    });

    // 实例详情(配置 + 运行状态)
    //
    //Future<InstanceDetail> getInstance(String instanceId) async
    test('test getInstance', () async {
      // TODO
    });

    // 增量日志拉取(重连回放)
    //
    // `since` 为日志行序号(非时间戳),从 0 开始单调递增; 订阅 WS 后实时行由 `instance/stdout` 推送,本端点用于断线补拉。 
    //
    //Future<LogResponse> getInstanceLog(String instanceId, { int since, int limit }) async
    test('test getInstanceLog', () async {
      // TODO
    });

    // 持久化日志文件内容(完整回放/导出)
    //
    // 返回该实例的日志文件全文(512KB 轮换,最大保留最近两卷)。
    //
    //Future<String> getInstanceOutputLog(String instanceId) async
    test('test getInstanceOutputLog', () async {
      // TODO
    });

    // 读取实例配置文件(server.properties 等)
    //
    // 按文件名自动选择解析器:properties / yml / json / txt。 大整数以字符串返回避免精度丢失。 
    //
    //Future<BuiltMap<String, String>> getInstanceProcessConfig(String instanceId, String file) async
    test('test getInstanceProcessConfig', () async {
      // TODO
    });

    // 全部实例状态聚合(首页看板)
    //
    // 返回所有实例的概要 + 运行中实例数量,供 UI 首页一次性渲染; 实时变化经 WS `instance/state` 事件推送。 
    //
    //Future<InstanceOverview> getInstancesOverview() async
    test('test getInstancesOverview', () async {
      // TODO
    });

    // 强制结束进程(进程树)
    //
    // 启动后 6 秒内禁止强杀(防误触);跨平台进程树杀死。
    //
    //Future killInstance(String instanceId) async
    test('test killInstance', () async {
      // TODO
    });

    // 实例列表(分页)
    //
    //Future<InstancePage> listInstances({ int page, int pageSize, String keyword }) async
    test('test listInstances', () async {
      // TODO
    });

    // 重启(停止完成后自动重新启动)
    //
    //Future restartInstance(String instanceId) async
    test('test restartInstance', () async {
      // TODO
    });

    // 程序化发送一行命令(命令框通道)
    //
    // 结构化命令入口,对应终端协议中的 `input` 帧; 按实例配置可被替换为 RCON 等实现(附加层)。 
    //
    //Future sendInstanceCommand(String instanceId, CommandRequest commandRequest) async
    test('test sendInstanceCommand', () async {
      // TODO
    });

    // 启动实例
    //
    // 完整多实例并发:任意数量实例可同时运行,互不干扰。 含首次启动的目录检查、锁与失败兜底 kill。 
    //
    //Future startInstance(String instanceId) async
    test('test startInstance', () async {
      // TODO
    });

    // 优雅停止(发送 stopCommand,默认 ^C)
    //
    // stopCommand 超时(可配,默认 600s)后自动升级为强杀。
    //
    //Future stopInstance(String instanceId) async
    test('test stopInstance', () async {
      // TODO
    });

    // 更新实例配置
    //
    // 运行中实例的以下字段不可变更(需先停止):startCommand、workingDirectory、 type、terminal.pty、inputEncoding、outputEncoding。其余字段热更新。 
    //
    //Future<InstanceConfig> updateInstance(String instanceId, InstanceConfig instanceConfig) async
    test('test updateInstance', () async {
      // TODO
    });

    // 写回实例配置文件
    //
    //Future updateInstanceProcessConfig(String instanceId, String file, BuiltMap<String, String> requestBody) async
    test('test updateInstanceProcessConfig', () async {
      // TODO
    });

  });
}
