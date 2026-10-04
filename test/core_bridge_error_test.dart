import 'package:duanju_app/core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 本机没有 libduanju_core，正好覆盖「编码 → 工作 isolate 调用 → 解码并分类」这条路：
  // 平台不支持或核心缺失都要落到明确原因，而不是统一提示参数错误或重装。
  test('缺少本地核心时按原因分类报错', () async {
    final repository = NativeRepository();
    await expectLater(
      repository.exportLibrary(),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          anyOf('core_unavailable', 'core_unsupported'),
        ),
      ),
    );
  });
}
