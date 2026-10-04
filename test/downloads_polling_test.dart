import 'package:duanju_app/downloads_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// 只统计轮询次数，用来验证静止页面不再按时重建。
class PollingRepository extends FixtureRepository {
  final calls = <int>[];
  List<DownloadJob> jobs = [];

  @override
  bool get supportsDownloads => true;

  @override
  Future<List<DownloadJob>> downloads() async {
    calls.add(jobs.length);
    return List.of(jobs);
  }
}

DownloadJob _job(String state) => DownloadJob(
  id: '1',
  drama: FixtureRepository.free,
  episode: Episode(const <String, dynamic>{'id': '1', 'currentEpisode': 1}, 1),
  state: state,
  bytes: 512,
  total: 2048,
  progress: .25,
  actualQuality: 1080,
);

void main() {
  late SharedPreferences preferences;
  late LocalStore store;
  late PollingRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    store = LocalStore(preferences);
    repository = PollingRepository();
  });

  tearDown(() => store.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadsScreen(repository: repository, store: store),
      ),
    );
    await tester.pump();
  }

  testWidgets('没有任务时不再定时轮询', (tester) async {
    await open(tester);
    expect(repository.calls, hasLength(1));
    await tester.pump(const Duration(seconds: 30));
    expect(repository.calls, hasLength(1), reason: '空列表不该继续每 2 秒读一次');
  });

  testWidgets('有活动任务时保留 2 秒刷新节奏', (tester) async {
    repository.jobs = [_job('downloading')];
    await open(tester);
    expect(repository.calls, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(repository.calls.length, greaterThan(1));
  });

  testWidgets('只剩已完成任务时降速到 8 秒', (tester) async {
    repository.jobs = [_job('completed')];
    await open(tester);
    expect(repository.calls, hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    expect(repository.calls, hasLength(1), reason: '没有活动任务时不该按 2 秒轮询');
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(repository.calls.length, greaterThan(1));
  });

  testWidgets('任务数据没变时列表内容保持一致', (tester) async {
    repository.jobs = [_job('completed')];
    await open(tester);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(repository.calls.length, greaterThan(1));
    expect(find.text('测试短剧'), findsWidgets);
  });
}
