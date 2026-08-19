import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for FilesApi
void main() {
  final instance = EdgecubeApiClient().getFilesApi();

  group(FilesApi, () {
    // 分片上传:完成(校验 sha256)
    //
    //Future<UploadCompleteResponse> completeFileUpload(UploadCompleteRequest uploadCompleteRequest) async
    test('test completeFileUpload', () async {
      // TODO
    });

    // 压缩为 zip
    //
    //Future<JobAccepted> compressFile(FsCompressRequest fsCompressRequest) async
    test('test compressFile', () async {
      // TODO
    });

    // 创建目录
    //
    //Future createDirectory(FsPathRequest fsPathRequest) async
    test('test createDirectory', () async {
      // TODO
    });

    // 删除文件/目录(目录递归)
    //
    //Future deleteFile(FsPathRequest fsPathRequest) async
    test('test deleteFile', () async {
      // TODO
    });

    // 下载文件(二进制流)
    //
    //Future<Uint8List> downloadFile(String instanceId, String path) async
    test('test downloadFile', () async {
      // TODO
    });

    // 解压归档(zip/tar/tar.gz)
    //
    //Future<JobAccepted> extractFile(FsPathRequest fsPathRequest) async
    test('test extractFile', () async {
      // TODO
    });

    // 分片上传:初始化
    //
    // 分片断点续传三段式(upload-init / upload-piece / upload-complete), 对齐 MCSManager /upload-new + /upload-piece 设计。 分片大小由客户端自定(建议 1-8 MiB),服务端按 offset 写。 
    //
    //Future<UploadSession> initFileUpload(UploadInitRequest uploadInitRequest) async
    test('test initFileUpload', () async {
      // TODO
    });

    // 列出目录(沙箱,以实例 cwd 为根)
    //
    //Future<FileListResponse> listFiles(String instanceId, { String path }) async
    test('test listFiles', () async {
      // TODO
    });

    // 移动/重命名
    //
    //Future moveFile(FsMoveRequest fsMoveRequest) async
    test('test moveFile', () async {
      // TODO
    });

    // 分片上传:写入一片
    //
    //Future<UploadProgress> uploadFilePiece(String uploadId, int offset, MultipartFile body) async
    test('test uploadFilePiece', () async {
      // TODO
    });

  });
}
