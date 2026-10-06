import 'package:duanju_app/catalog_prefetch.dart';
import 'package:flutter_test/flutter_test.dart';

// 源项目用 package:fake_async 推进假时钟，本仓库没有把它声明为依赖，
// 而 CI 是 flutter pub get --enforce-lockfile 加 dart analyze 全绿才过，
// 所以这里改用 testWidgets 自带的假时钟：tester.pump(时长) 等价于 fakeAsync.elapse。
void main() {
  testWidgets('滚动期间不触发，停止滚动后才补齐提前量', (tester) async {
    final scheduler = CatalogPrefetchScheduler(
      bufferScreens: 2,
      idleDelay: const Duration(milliseconds: 320),
    );
    addTearDown(scheduler.dispose);
    var calls = 0;
    scheduler.onIdle = () => calls++;

    for (var i = 0; i < 12; i++) {
      scheduler.scrolled(extentAfter: 400, viewport: 800);
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(calls, 0, reason: '快速滚动时不应插入取页请求');

    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, greaterThan(0));
    scheduler.dispose();
  });

  testWidgets('提前量充足时不请求下一页', (tester) async {
    final scheduler = CatalogPrefetchScheduler();
    addTearDown(scheduler.dispose);
    var calls = 0;
    scheduler.onIdle = () => calls++;

    scheduler.scrolled(extentAfter: 4000, viewport: 800);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    scheduler.dispose();
  });

  testWidgets('单次空闲最多补齐到上限轮数', (tester) async {
    final scheduler = CatalogPrefetchScheduler(
      maxRounds: 3,
      idleDelay: const Duration(milliseconds: 10),
    );
    addTearDown(scheduler.dispose);
    var calls = 0;
    scheduler.onIdle = () {
      calls++;
      scheduler.settled(extentAfter: 100, viewport: 800);
    };

    scheduler.scrolled(extentAfter: 100, viewport: 800);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 3);
    scheduler.dispose();
  });

  testWidgets('切换页签会重置轮数并暂停', (tester) async {
    final scheduler = CatalogPrefetchScheduler(
      maxRounds: 3,
      idleDelay: const Duration(milliseconds: 10),
    );
    addTearDown(scheduler.dispose);
    var calls = 0;
    scheduler.onIdle = () => calls++;

    scheduler.scrolled(extentAfter: 100, viewport: 800);
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 1);

    scheduler.hold();
    scheduler.settled(extentAfter: 100, viewport: 800);
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 1, reason: '聚合期间不允许继续取页');
    scheduler.dispose();
  });

  testWidgets('重新进入首页后解除暂停并继续补齐', (tester) async {
    final scheduler = CatalogPrefetchScheduler(
      idleDelay: const Duration(milliseconds: 10),
    );
    addTearDown(scheduler.dispose);
    var calls = 0;
    scheduler.onIdle = () => calls++;

    scheduler.scrolled(extentAfter: 100, viewport: 800);
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 1);

    scheduler.hold();
    expect(scheduler.paused, isTrue);
    scheduler.resume();
    expect(scheduler.paused, isFalse);
    scheduler.settled(extentAfter: 100, viewport: 800);
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 2);
    scheduler.dispose();
  });

  testWidgets('首屏加载完成后按现有内容判断是否需要预加载', (tester) async {
    final scheduler = CatalogPrefetchScheduler(
      idleDelay: const Duration(milliseconds: 10),
    );
    addTearDown(scheduler.dispose);
    var calls = 0;
    scheduler.onIdle = () => calls++;

    scheduler.settled(extentAfter: 100, viewport: 800);
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 1, reason: '内容不足一屏时应在首次布局后继续取页');

    scheduler.settled(extentAfter: 5000, viewport: 800);
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 1, reason: '提前量充足时不再取页');
    scheduler.dispose();
  });

  test('视口不可用时不做提前量判断', () {
    final scheduler = CatalogPrefetchScheduler();
    addTearDown(scheduler.dispose);
    expect(scheduler.wantsMore, isFalse);
  });

  testWidgets('释放后不再回调', (tester) async {
    final scheduler = CatalogPrefetchScheduler(
      idleDelay: const Duration(milliseconds: 10),
    );
    var calls = 0;
    scheduler.onIdle = () => calls++;
    scheduler.scrolled(extentAfter: 100, viewport: 800);
    scheduler.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
  });
}
