import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for TransferApi
void main() {
  final instance = EdgecubeApiClient().getTransferApi();

  group(TransferApi, () {
    // 下载已完成的导出归档
    //
    // 按导出任务 id 下载归档文件(application/octet-stream 流式返回)。 归档同时包含实例配置(config.json)与 `files` 目录内容,可用 POST /instances/import 在任意设备还原。文件在导出目录中保留 24 小时,过期或被新导出覆盖后返回 404。 
    //
    //Future<Uint8List> downloadInstanceExport(String instanceId, String exportTaskId) async
    test('test downloadInstanceExport', () async {
      // TODO
    });

    // 导入实例(从导出归档还原为新实例)
    //
    // 归档文件须先经 /fs/upload-* 上传到某实例的 cwd(sourceInstanceId 指定该实例), 导入时 daemon 校验归档结构(须含 config.json 与 files/ 目录)后创建新实例: 新实例 id 重新生成,cwd 落到新工作目录,配置中的 name 与 runtime 等 字段按需映射。返回 202 受理(JobAccepted),任务完成 (GET /tasks/{jobId} = succeeded)后新实例出现在实例列表。 
    //
    //Future<JobAccepted> importInstance(ImportRequest importRequest) async
    test('test importInstance', () async {
      // TODO
    });

  });
}
