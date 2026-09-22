/* =============================================================================
 * sheet_history_test.dart — 결과지 아래 「신체변화」 그래프의 지난 측정
 *
 * 서버가 열들을 보내면 앱은 내 기록과 대조해서 없는 날만 고르고, 검수
 * 화면에서 체크된 것을 이번 측정과 같이 저장합니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/review.dart';
import 'package:mybody/src/sheet_history.dart';
import 'package:mybody/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _raw = [
  {'measuredAt': '2026-06-30T12:00:00.000Z', 'weightKg': 89.0, 'smmKg': 36.2, 'pbfPct': 28.4},
  {'measuredAt': '2026-08-31T12:00:00.000Z', 'weightKg': 86.9, 'smmKg': 37.4, 'pbfPct': 24.2},
  {'measuredAt': '2026-09-19T12:00:00.000Z', 'weightKg': 86.7, 'smmKg': 37.9, 'pbfPct': 23.1},
];
const _cur = '2026-09-19T12:00:00.000Z';

void main() {
  test('이번 측정과 같은 날·이미 있는 날은 빼고, 오래된 순', () {
    final out = sheetHistory(_raw,
        currentAt: _cur, scans: [{'measuredAt': '2026-08-31T03:00:00.000Z'}]);
    expect(out.map((h) => h.weightKg), [89.0]);
    expect(out.first.measuredAt, '2026-06-30T12:00:00.000Z');
    expect(out.first.bfmKg, 25.3);

    final all = sheetHistory(_raw, currentAt: _cur, scans: const []);
    expect(all.map((h) => h.weightKg), [89.0, 86.9]);

    final scan = all.first.toScan(heightCm: 187);
    expect(scan['id'], 'scan-h${DateTime.parse('2026-06-30T12:00:00.000Z').millisecondsSinceEpoch}');
    expect(scan['source'], 'chart');
    expect(scan['bfmKg'], 25.3);
    expect(scan['ffmKg'], 63.7);
    expect(scan['bmi'], 25.5);
  });

  test('말이 안 되는 열은 조용히 빠진다', () {
    final out = sheetHistory([
      {'measuredAt': '2026-06-30T12:00:00.000Z', 'weightKg': 89.0, 'pbfPct': 28.4}, // 골격근 없음
      {'measuredAt': '2026-07-30T12:00:00.000Z', 'weightKg': 89.0, 'smmKg': 10.0, 'pbfPct': 28.4}, // 근육 비율 이상
      {'measuredAt': '2026-10-30T12:00:00.000Z', 'weightKg': 88.0, 'smmKg': 37.0, 'pbfPct': 25.0}, // 이번 측정 뒤
      {'measuredAt': '2026-08-31T12:00:00.000Z', 'weightKg': 86.9, 'smmKg': 37.4, 'pbfPct': 24.2},
      {'measuredAt': '2026-08-31T13:00:00.000Z', 'weightKg': 86.8, 'smmKg': 37.4, 'pbfPct': 24.2}, // 같은 날 둘
      'junk', null,
    ], currentAt: _cur, scans: const []);
    expect(out.map((h) => h.weightKg), [86.9]);
    expect(sheetHistory(null, currentAt: _cur, scans: const []), isEmpty);
    expect(sheetHistory('x', currentAt: _cur, scans: const []), isEmpty);
  });

  testWidgets('검수 화면 — 체크된 지난 측정만 같이 저장된다', (t) async {
    t.view.physicalSize = const Size(1000, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.set({
      'profile': {'sex': 'male', 'heightCm': 187, 'age': 22, 'activityLevel': 'moderate',
        'trainingAge': 'novice', 'daysPerWeek': 4, 'sessionMinutes': 60, 'mealsPerDay': 3},
      'onboarded': true,
    });
    final api = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    api.setToken('tok');
    final history = sheetHistory(_raw, currentAt: _cur, scans: const []);
    expect(history.length, 2);

    await t.pumpWidget(Scope(
      state: app,
      api: api,
      onServerChange: (_) async {},
      child: MaterialApp(
        theme: mbLight(),
        home: Scaffold(body: Builder(builder: (c) => TextButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(
              builder: (_) => ReviewScreen(
                    draft: const {
                      'id': 'scan-now', 'measuredAt': _cur,
                      'weightKg': 86.7, 'smmKg': 37.9, 'bfmKg': 20.0, 'pbfPct': 23.1,
                    },
                    history: history,
                  ))),
          child: const Text('go'),
        ))),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    expect(find.text('지난 측정 2개도 같이'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    // 6월 30일 것은 뺍니다.
    await t.tap(find.byKey(ValueKey('hist-${history.first.measuredAt}')));
    await t.pump();
    await t.ensureVisible(find.text('저장하기'));
    await t.tap(find.text('저장하기'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    final scans = app.store.sortedScans();
    expect(scans.length, 2, reason: '이번 측정 + 8월 31일');
    expect(scans.first['source'], 'chart');
    expect(scans.first['weightKg'], 86.9);
    expect(scans.first['bfmKg'], 21.0);
    expect(scans.last['id'], 'scan-now', reason: '최신은 이번 측정 그대로');
    expect(find.textContaining('지난 측정 1개 추가'), findsOneWidget);
  });
}
