import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for TaskProgress
void main() {
  final instance = TaskProgressBuilder();
  // TODO add properties to the builder and call build()

  group(TaskProgress, () {
    // int receivedBytes
    test('to test the property `receivedBytes`', () async {
      // TODO
    });

    // int totalBytes
    test('to test the property `totalBytes`', () async {
      // TODO
    });

    // 下载速度(字节/秒)
    // int speedBytesPerSec
    test('to test the property `speedBytesPerSec`', () async {
      // TODO
    });

    // 预计还需时间(秒,依据当前速度推算;无法推算时为 null)
    // int etaSeconds
    test('to test the property `etaSeconds`', () async {
      // TODO
    });

    // 0~1;未知大小(null)
    // double percent
    test('to test the property `percent`', () async {
      // TODO
    });

  });
}
