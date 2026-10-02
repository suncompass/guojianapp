import 'package:duanju_app/error_boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class Boom extends StatelessWidget {
  const Boom({super.key});
  @override
  Widget build(BuildContext context) => throw StateError('测试用异常：站源数据无法解析');
}

List<RenderObject> walk(RenderObject node, bool Function(RenderObject) match) {
  final found = <RenderObject>[];
  void visit(RenderObject current) {
    if (match(current)) found.add(current);
    current.visitChildren(visit);
  }

  visit(node);
  return found;
}

void main() {
  testWidgets('列表子项出错时给出有界可读的提示，而不是整屏灰块', (tester) async {
    final original = ErrorWidget.builder;
    installErrorWidget();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ListView(children: const [Text('未完成'), Boom()])),
        ),
      );
      await tester.pump();
      tester.takeException();

      final root = tester.binding.rootElement!.renderObject!;
      expect(
        walk(root, (node) => node is RenderErrorBox),
        isEmpty,
        reason: '仍然出现框架默认错误块',
      );
      expect(find.text('这部分内容暂时无法显示'), findsOneWidget);
      expect(find.textContaining('测试用异常：站源数据无法解析'), findsOneWidget);

      final card = tester.renderObject(find.byType(AppErrorTile));
      expect(
        card.paintBounds.height,
        lessThanOrEqualTo(AppErrorTile.maxHeight),
      );
    } finally {
      ErrorWidget.builder = original;
    }
  });

  testWidgets('描述函数会压缩超长异常文本', (tester) async {
    final long = FlutterErrorDetails(exception: StateError('异常' * 500));
    expect(describeErrorForDisplay(long).length, lessThanOrEqualTo(601));
    expect(
      describeErrorForDisplay(
        FlutterErrorDetails(exception: FlutterError('直接消息')),
      ),
      '直接消息',
    );
  });
}
