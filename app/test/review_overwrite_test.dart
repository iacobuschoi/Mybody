/* =============================================================================
 * review_overwrite_test.dart — 같은 결과지를 두 번 넣어도 두 줄이 안 된다
 *
 * 같은 시각 · 같은 값이면 그 기록을 갱신합니다. 시각만 같고 값이 다르면
 * 사람이 정합니다 — 스위치를 켜야 덮어씁니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/review.dart';
import 'package:mybody/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _at = '2026-09-19T02:09:00.000Z';
const _old = {
  'id': 'scan-old', 'measuredAt': _at,
  'weightKg': 86.7, 'smmKg': 37.9, 'bfmKg': 20.0, 'pbfPct': 23.1, 'photoId': 'p1',
};

Future<AppState> _seeded() async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.boot();
  app.store.set({
    'profile': {'sex': 'male', 'heightCm': 187, 'age': 22, 'activityLevel': 'moderate',
      'trainingAge': 'novice', 'daysPerWeek': 4, 'sessionMinutes': 60, 'mealsPerDay': 3},
    'onboarded': true,
  });
  app.store.addScan(Map<String, Object?>.of(_old));
  return app;
}

Future<void> _open(WidgetTester t, AppState app, Map<String, Object?> draft) async {
  t.view.physicalSize = const Size(1000, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final api = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
  api.setToken('tok');
  await t.pumpWidget(Scope(
    state: app,
    api: api,
    onServerChange: (_) async {},
    child: MaterialApp(
      theme: mbLight(),
      home: Scaffold(body: Builder(builder: (c) => TextButton(
        onPressed: () => Navigator.of(c).push(
            MaterialPageRoute(builder: (_) => ReviewScreen(draft: draft))),
        child: const Text('go'),
      ))),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
}

Future<void> _save(WidgetTester t) async {
  await t.ensureVisible(find.text('저장하기'));
  await t.tap(find.text('저장하기'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('같은 시각 · 같은 값 → 갱신, 두 줄 아님', (t) async {
    final app = await _seeded();
    await _open(t, app, const {
      'id': 'scan-new', 'measuredAt': _at,
      'weightKg': 86.7, 'smmKg': 37.9, 'bfmKg': 20.0, 'pbfPct': 23.1,
    });
    expect(find.textContaining('이미 있는 기록과 같습니다', findRichText: true), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    await _save(t);
    final scans = app.store.sortedScans();
    expect(scans.length, 1);
    expect(scans.first['id'], 'scan-old');
    expect(scans.first['photoId'], 'p1', reason: '사진이 새로 없으면 옛 사진을 둔다');
    expect(find.textContaining('갱신했습니다', findRichText: true), findsOneWidget);
  });

  testWidgets('같은 시각 · 다른 값 → 기본은 새 줄', (t) async {
    final app = await _seeded();
    await _open(t, app, const {
      'id': 'scan-new', 'measuredAt': _at,
      'weightKg': 88.0, 'smmKg': 37.9, 'bfmKg': 20.0, 'pbfPct': 22.7,
    });
    expect(find.textContaining('같은 시각의 측정이 이미 있습니다', findRichText: true), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    await _save(t);
    expect(app.store.sortedScans().length, 2);
  });

  testWidgets('같은 시각 · 다른 값 → 덮어쓰기를 켜면 한 줄', (t) async {
    final app = await _seeded();
    await _open(t, app, const {
      'id': 'scan-new', 'measuredAt': _at,
      'weightKg': 88.0, 'smmKg': 37.9, 'bfmKg': 20.0, 'pbfPct': 22.7,
    });
    await t.tap(find.byType(SwitchListTile));
    await t.pump();
    await _save(t);
    final scans = app.store.sortedScans();
    expect(scans.length, 1);
    expect(scans.first['id'], 'scan-old');
    expect(scans.first['weightKg'], 88.0);
  });

  testWidgets('다른 시각이면 아무 말 없이 새 줄', (t) async {
    final app = await _seeded();
    await _open(t, app, const {
      'id': 'scan-new', 'measuredAt': '2026-09-20T02:09:00.000Z',
      'weightKg': 86.7, 'smmKg': 37.9, 'bfmKg': 20.0, 'pbfPct': 23.1,
    });
    expect(find.textContaining('이미 있는 기록과 같습니다', findRichText: true), findsNothing);
    expect(find.textContaining('같은 시각의 측정이 이미 있습니다', findRichText: true), findsNothing);
    await _save(t);
    expect(app.store.sortedScans().length, 2);
  });
}
