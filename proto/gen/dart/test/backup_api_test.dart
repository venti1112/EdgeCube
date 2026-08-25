import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for BackupApi
void main() {
  final instance = EdgecubeApiClient().getBackupApi();

  group(BackupApi, () {
    // 创建备份任务
    //
    //Future<BackupJob> createBackupJob(BackupJob backupJob) async
    test('test createBackupJob', () async {
      // TODO
    });

    // 创建备份目标
    //
    //Future<BackupTarget> createBackupTarget(BackupTarget backupTarget) async
    test('test createBackupTarget', () async {
      // TODO
    });

    // 删除备份任务
    //
    //Future deleteBackupJob(String jobId) async
    test('test deleteBackupJob', () async {
      // TODO
    });

    // 删除备份目标
    //
    //Future deleteBackupTarget(String targetId) async
    test('test deleteBackupTarget', () async {
      // TODO
    });

    // 备份任务列表
    //
    //Future<BuiltList<BackupJob>> listBackupJobs() async
    test('test listBackupJobs', () async {
      // TODO
    });

    // 备份目标列表(local/FTP/SFTP)
    //
    //Future<BuiltList<BackupTarget>> listBackupTargets() async
    test('test listBackupTargets', () async {
      // TODO
    });

    // 立即执行备份(进度走 WS backup/progress)
    //
    //Future<JobAccepted> triggerBackupJob(String jobId) async
    test('test triggerBackupJob', () async {
      // TODO
    });

    // 更新备份任务
    //
    //Future<ErrorResponse> updateBackupJob(String jobId, BackupJob backupJob) async
    test('test updateBackupJob', () async {
      // TODO
    });

    // 更新备份目标
    //
    //Future<BackupTarget> updateBackupTarget(String targetId, BackupTarget backupTarget) async
    test('test updateBackupTarget', () async {
      // TODO
    });

  });
}
