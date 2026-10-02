import 'package:duanju_app/app_build.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real startup initializes the packaged native core', (
    tester,
  ) async {
    expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    await app.main([]);
    final deadline = Stopwatch()..start();
    while (find.byType(HomeScreen).evaluate().isEmpty) {
      if (deadline.elapsed > const Duration(seconds: 40)) {
        fail('启动未能进入首页');
      }
      await tester.pump(const Duration(milliseconds: 100));
      final application = find.byType(app.DuanjuApp);
      if (application.evaluate().isNotEmpty) {
        expect(
          tester.widget<app.DuanjuApp>(application).bootstrapError,
          isNull,
        );
      }
    }
    expect(
      tester.widget<app.DuanjuApp>(find.byType(app.DuanjuApp)).store,
      isNotNull,
    );
    debugPrint('STARTUP_READY allSources=$allSourcesEnabled');
    debugPrint('ENTRY_CAPTURE startup');
    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(HomeScreen), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
