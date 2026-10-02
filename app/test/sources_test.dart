/* =============================================================================
 * sources_test.dart — 권장값마다 출처가 **쉽게 찾아지는가** (애플 심사 1.4.1)
 *
 * 0.2.20 (347) 이 "건강 · 의료 권장값에 출처(링크)가 없다" 로 거절됐습니다.
 * 여기서 지키는 것:
 *
 *   1. 목록(citations.dart) — 모든 출처가 https 링크 · 서지 정보 · 한국어 제목을 갖고,
 *      모든 주제가 출처 하나 이상으로 이어집니다.
 *   2. 화면의 「출처」 링크가 묻는 주제는 전부 목록에 있습니다(코드를 훑어서 + 그려서).
 *   3. 설정 → 도움말에 「근거 · 출처」 가 있고, 누르면 목록 화면(의료 안내 포함)이 열립니다.
 *   4. 플랜 · 홈 · 목표 · 키·체중 추정 · 헬스 · 식단 화면의 숫자 옆에 「출처」 가 있습니다.
 *   5. 링크를 누르면 시트에 그 주제의 출처, 출처를 누르면 그 주소를 앱 밖에서 엽니다.
 *   6. 좁은 폰(320px) · 큰 글자(1.3배)에서도 넘치지 않습니다 — 아이패드 호환 모드도
 *      폰 크기로 그립니다.
 * ========================================================================== */
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/app_state.dart';
import 'package:mybody/src/briefing.dart';
import 'package:mybody/src/citations.dart';
import 'package:mybody/src/scope.dart';
import 'package:mybody/src/screens/checkin.dart';
import 'package:mybody/src/screens/duration.dart';
import 'package:mybody/src/screens/estimate_sheet.dart';
import 'package:mybody/src/screens/exercise_picker.dart';
import 'package:mybody/src/screens/feedback.dart' show feedbackLockedRemoveSay, feedbackLockedSubtitle;
import 'package:mybody/src/screens/food.dart';
import 'package:mybody/src/screens/goal.dart';
import 'package:mybody/src/screens/home.dart';
import 'package:mybody/src/screens/intensity.dart';
import 'package:mybody/src/screens/onboarding.dart';
import 'package:mybody/src/screens/plan.dart';
import 'package:mybody/src/screens/progress.dart';
import 'package:mybody/src/screens/review.dart';
import 'package:mybody/src/screens/scandetail.dart';
import 'package:mybody/src/screens/settings.dart';
import 'package:mybody/src/screens/sources.dart';
import 'package:mybody/src/screens/tester_welcome.dart';
import 'package:mybody/src/screens/workout_session.dart';
import 'package:mybody/src/screens/workout_tutorial.dart';
import 'package:mybody/src/theme.dart';
import 'package:mybody/src/ui/source_link.dart' show kSourceLinkMinHeight, kSourceLinkMinWidth;
import 'package:mybody/src/ui/widgets.dart';
import 'package:mybody_core/mybody_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

const _scan = {
  'id': 's1', 'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0,
  'pbfPct': 23.1, 'ffmKg': 66.7, 'bmi': 24.8, 'bmrKcal': 1810, 'inbodyScore': 78,
  'measuredAt': '2026-03-01T00:00:00.000Z',
};
const _profile = {
  'sex': 'male', 'age': 22, 'heightCm': 187, 'activityLevel': 'moderate',
  'trainingAge': 'novice', 'daysPerWeek': 4, 'mealsPerDay': 3,
};
const _goal = {'weightKg': 80.5, 'smmKg': 39.0, 'bfmKg': 12.0};

final _today = DateTime(2026, 9, 27, 18, 0);
const _todayKey = '2026-09-27';

/// 주제 문자열 — 코드의 「출처」 링크 자리에서 뽑습니다.
final _quoted = RegExp(r"'([^']*)'");

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* --- 1. 목록 --------------------------------------------------------------- */

  group('출처 목록', () {
    test('모든 출처에 https 링크 · 서지 정보 · 한국어 제목이 있고, 묶음과 주제가 알려진 것', () {
      final ids = <String>{};
      for (final c in kCitations) {
        expect(ids.add(c.id), isTrue, reason: '같은 id 가 둘: ${c.id}');
        final u = Uri.parse(c.url);
        expect(u.scheme, 'https', reason: '${c.id}: ${c.url}');
        expect(u.host, isNotEmpty, reason: c.id);
        expect(c.reference.trim(), isNotEmpty, reason: c.id);
        expect(c.title.trim(), isNotEmpty, reason: c.id);
        expect(kCitationGroups, contains(c.group), reason: c.id);
        expect(c.topics, isNotEmpty, reason: c.id);
        for (final t in c.topics) {
          expect(kSourceTopics.keys, contains(t), reason: '${c.id} 의 주제 $t 가 목록에 없습니다');
        }
      }
      /* 네 묶음 모두 무언가 있습니다. */
      for (final g in kCitationGroups) {
        expect(kCitations.where((c) => c.group == g), isNotEmpty, reason: g);
      }
    });

    test('모든 주제가 출처 하나 이상으로 이어진다', () {
      for (final t in kSourceTopics.keys) {
        expect(citationsFor([t]), isNotEmpty, reason: '주제 $t 에 출처가 없습니다');
      }
    });

    test('가까운 근거(kTopicRelated)는 직접 출처가 있는 주제만 가리킨다', () {
      for (final e in kTopicRelated.entries) {
        expect(kSourceTopics.keys, contains(e.key));
        for (final r in e.value) {
          expect(kCitations.any((c) => c.topics.contains(r)), isTrue,
              reason: '${e.key} → $r 에 직접 출처가 없습니다');
        }
      }
    });

    test('citationsFor 는 묶음 순서대로, 겹치지 않게', () {
      final list = citationsFor(['bmr', 'tdee_activity', 'scan_crosscheck']);
      expect(list.map((c) => c.id).toSet().length, list.length);
      expect(list.map((c) => c.id), contains('cunningham_1991'));
      final groups = list.map((c) => kCitationGroups.indexOf(c.group)).toList();
      expect(groups, orderedEquals([...groups]..sort()));
    });

    /* 코드에 박힌 「출처」 자리를 훑습니다 — 주제 이름의 오타는 링크를 눌러야 드러나는데,
       심사관이 먼저 누릅니다. */
    test('lib/ 의 모든 「출처」 링크가 묻는 주제가 목록에 있다', () {
      final sites = <String, List<String>>{};
      final patterns = [
        RegExp(r'SourceLink\(\s*(?:const\s*)?\[([^\]]*)\]'),
        RegExp(r'sources:\s*[^,\[\]]*?\[([^\]]*)\]'),
        RegExp(r'const List<String> k\w*Sources\s*=\s*\[([^\]]*)\]'),
      ];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        for (final p in patterns) {
          for (final m in p.allMatches(src)) {
            final topics = [for (final q in _quoted.allMatches(m.group(1)!)) q.group(1)!];
            if (topics.isEmpty) continue;
            sites['${f.path}@${m.start}'] = topics;
          }
        }
      }
      /* 훑기가 실제로 잡는지 — 플랜 · 홈 · 목표 · 식단 · 헬스 · 체크인 … 마흔 곳 남짓. */
      expect(sites.length, greaterThanOrEqualTo(40), reason: '찾은 자리: ${sites.length}');
      for (final e in sites.entries) {
        for (final t in e.value) {
          expect(kSourceTopics.keys, contains(t), reason: '${e.key} 의 주제 "$t" 가 목록에 없습니다');
        }
      }
    });

    test('계산해서 고르는 「출처」 주제(브리핑 줄 · 강도 카드)도 목록에 있다', () {
      for (final icon in ['gym', 'cardio', 'food', 'checkin', 'rest', 'done', 'scan']) {
        for (final text in ['헬스 완료 · 45분 · 약 300kcal', '오늘은 쉬는 날']) {
          final s = briefLineSources(BriefLine(icon: icon, text: text), hasPlan: true);
          for (final t in s ?? const <String>[]) {
            expect(kSourceTopics.keys, contains(t), reason: '$icon: $t');
          }
        }
        expect(briefLineSources(BriefLine(icon: icon, text: 'x'), hasPlan: false), isNull);
      }
      final r = {
        'capWarning': 'x', 'leanLossWarning': 'y',
        'feasibility': {'verdict': 'blocked', 'message': '목표 골격근량이 상한을 넘습니다'},
      };
      final topics = levelCardSources(r);
      expect(topics, containsAll(['continuous_cut_limit', 'lean_mass_loss_warning', 'ffmi_muscle_ceiling']));
      for (final t in topics) {
        expect(kSourceTopics.keys, contains(t));
      }
    });

    test('브리핑의 헬스 줄에 유산소 분이 붙으면 그 출처(유산소 시간)도', () {
      final s = briefLineSources(const BriefLine(icon: 'gym', text: '오늘은 상체 A 하는 날 · 60분 · 유산소 40분'),
          hasPlan: true)!;
      expect(s, containsAll(['resistance_volume_split', 'sets_reps_rest', 'cardio_minutes']));
      expect(briefLineSources(const BriefLine(icon: 'gym', text: '오늘은 상체 A 하는 날 · 60분'), hasPlan: true),
          isNot(contains('cardio_minutes')));
    });

    /* 직접 출처가 없는(앱이 정한) 기준이면 시트 · 목록 머리에 그렇다고 — 관련 논문을 그 숫자의
       출처로 읽지 않게(심사 지적: 청소년 감량 거절 문구에 성인 선수 논문이 「출처」 로 떴습니다). */
    test('앱이 정한 기준은 「관련 근거」 라고 밝힌다 — 직접 출처가 있는 주제는 아무 말 없이', () {
      for (final t in [...kTopicRelated.keys, ...kAppSetTopics]) {
        expect(appSetNote([t]), contains('앱이 정한 값'), reason: t);
        expect(appSetNote([t]), contains(kSourceTopics[t]!), reason: t);
      }
      for (final t in ['bmr', 'protein_target', 'kcal_floor', 'exercise_kcal', 'body_fat_estimate']) {
        expect(appSetNote([t]), isNull, reason: t);
      }
      expect(appSetNote(['bmr', 'goal_refusals_safety']), contains('계획을 만들지 않는 경우'));
      expect(appSetNote(['bmr', 'goal_refusals_safety']), isNot(contains('기초대사량')));
    });

    test('BMI 18.5 미만(저체중) 기준에는 직접 출처(대한비만학회)가 붙는다', () {
      final direct = kCitations.where((c) => c.topics.contains('goal_refusals_safety')).toList();
      expect(direct.map((c) => c.id), contains('ksso_2022_guideline'));
      expect(direct.firstWhere((c) => c.id == 'ksso_2022_guideline').title, contains('BMI 18.5'));
    });

    /* 숫자 옆 출처가 그 숫자와 반대면 안 됩니다 — 출처 하나만 눌러 봐도 드러납니다. */
    test('출처 제목이 앱의 숫자와 다르면 그 차이를 그대로 적는다', () {
      String title(String id) => kCitations.firstWhere((c) => c.id == id).title;
      expect(title('bull_2020_who'), contains('150~300분'));
      expect(title('bull_2020_who'), contains('일상 활동'));
      expect(title('kdri_2025_carb'), contains('앱의 하한 50g'));
      expect(title('kdri_2025'), contains('이보다 높게'));
      expect(title('hall_2008_energy_deficit'), contains('9,400kcal'));
      expect(title('fao_who_unu_2004'), contains('1.40~1.69'));
      expect(title('kouri_1995_ffmi'), contains('여성 상한 22 는 이 연구에 없는'));
      expect(title('areta_2013_distribution'), contains('20g씩'));
      expect(title('acsm_2009_progression'), contains('2~10%'));
      expect(title('ainsworth_2011_compendium'), contains('3.5'));
      /* 기초대사량 식(Cunningham 1991)은 활동계수의 출처가 아닙니다. */
      expect(kCitations.firstWhere((c) => c.id == 'cunningham_1991').topics, isNot(contains('tdee_activity')));
      /* DOI · PubMed 처럼 오래 가는 주소로 — 출판사 경로 · PMC 번호보다. */
      for (final id in ['kouri_1995_ffmi', 'looney_2024_inbody770']) {
        expect(Uri.parse(kCitations.firstWhere((c) => c.id == id).url).host, 'doi.org', reason: id);
      }
    });

    test('엔진의 출처 없는 의학 · 안전 주장은 화면에 그릴 때 바꾼다', () {
      final refusals = [for (final r in core.kRefusals) reworded('${(r as Map)['message']}')].join('\n');
      expect(refusals, isNot(contains('성장 지연')));
      expect(refusals, isNot(contains('안전하게 가능한 상한')));
      expect(refusals, contains('이 앱이 계획을 만드는 상한(주 1.5%)'));
      expect(refusals, contains('소아청소년과 의사'));
      expect(reworded('8주 — 대사 회복에 보통 권하는 길이'), '8주 — 표준 유지 기간');
      expect(reworded('감량 중에는 볼륨을 유지하는 것이 근손실을 막는 가장 강력한 수단입니다'),
          isNot(contains('가장 강력한')));
      /* 바꿀 말이 엔진에 실제로 있습니다 — 엔진 글이 바뀌어 대응이 끊기면 여기서 걸립니다. */
      final cmp = core.compareLevels({..._scan}, _profile, _goal, '2026-03-01', null, null);
      final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile)!;
      final notes = [for (final n in ((plan['diet'] as Map)['notes'] as List)) '$n'];
      expect(notes.any((n) => kClaimReword.containsKey(n)), isTrue);
      expect(notes.map(reworded).join(), isNot(contains('30~40g')));
    });

    test('의료 안내는 모두에게 — 의사와 상의하라는 말에 조건이 먼저 붙지 않는다', () {
      final i = kMedicalDisclaimer.indexOf('의사와 상의하세요');
      expect(i, greaterThan(0));
      expect(kMedicalDisclaimer.substring(0, i), isNot(contains('있다면')));
      expect(kMedicalDisclaimer, contains('임신·수유 중이거나 약을 먹고 있다면'));
    });

    test('아이폰에서는 말풍선 잠김 문구에 「테스트」 가 없다(지침 2.2)', () {
      expect(feedbackLockedSubtitle(TargetPlatform.iOS), isNot(contains('테스트')));
      expect(feedbackLockedRemoveSay(TargetPlatform.iOS), isNot(contains('테스트')));
      expect(feedbackLockedSubtitle(TargetPlatform.android), '테스트 기간에는 켜 둡니다');
      expect(feedbackLockedRemoveSay(TargetPlatform.android), '테스트 기간에는 없앨 수 없어요');
    });

    test('기초대사량 계산값은 출처의 이름(Cunningham)으로 보인다', () {
      expect(bmrSourceLabel('Katch-McArdle 계산값'), 'Cunningham 식 계산값');
      expect(bmrSourceLabel('InBody 인쇄값'), 'InBody 인쇄값');
    });
  });

  /* --- 화면 시험의 바탕 -------------------------------------------------------- */

  Future<AppState> seeded({bool withPlan = true, bool withScan = true}) async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.boot();
    app.store.now = () => _today;
    app.store.set({
      'profile': _profile,
      'onboarded': true,
      'settings': {kGymTutorialSeenKey: true, kGymSwipeHintSeenKey: true},
    });
    markTesterWelcomeSeen(app);
    if (withScan) app.store.addScan({..._scan});
    if (withScan && withPlan) {
      final cmp = core.compareLevels({..._scan}, _profile, _goal, '2026-03-01', null, null);
      final plan = core.buildPlan(cmp, 'mid', {..._scan}, _profile);
      app.store.setGoal(_goal);
      if (plan != null) app.store.setPlan(plan);
    }
    return app;
  }

  Api api() {
    final a = Api(baseUrl: '', client: MockClient((_) async => http.Response('{"ok":false}', 404)));
    a.setToken('tok');
    return a;
  }

  Widget host(AppState app, Widget child, {double textScale = 1.0}) => Scope(
        state: app,
        api: api(),
        onServerChange: (_) async {},
        child: MaterialApp(
          theme: mbLight(),
          builder: (context, w) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: w!,
          ),
          home: child,
        ),
      );

  void size(WidgetTester t, Size s) {
    t.view.physicalSize = s;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  Future<void> show(WidgetTester t, AppState app, Widget screen,
      {Size at = const Size(1000, 5000), double textScale = 1.0}) async {
    size(t, at);
    await t.pumpWidget(host(app, screen, textScale: textScale));
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);
    expect(t.takeException(), isNull);
  }

  /// 그려진 「출처」 링크가 다 목록의 주제를 묻고, 시트에 출처가 하나 이상 뜰 것.
  void linksAreValid(WidgetTester t) {
    final links = t.widgetList<SourceLink>(find.byType(SourceLink)).toList();
    expect(links, isNotEmpty);
    for (final l in links) {
      expect(l.topics, isNotEmpty);
      for (final topic in l.topics) {
        expect(kSourceTopics.keys, contains(topic), reason: '화면의 링크가 모르는 주제 $topic');
      }
      expect(citationsFor(l.topics), isNotEmpty, reason: '${l.topics}');
    }
  }

  /// [title] 제목 줄(SectionTitle)에 「출처」 가 붙어 있는가.
  Finder titledLink(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(SectionTitle)),
      matching: find.byType(SourceLink));

  void noop(String route, [Object? arg]) {}

  late List<Uri> opened;
  late bool openOk;
  setUp(() {
    opened = [];
    openOk = true;
    openSourceUrl = (u) async {
      opened.add(u);
      return openOk;
    };
    WorkoutSessionScreen.clock = () => _today;
  });
  tearDown(() => WorkoutSessionScreen.clock = DateTime.now);

  /* --- 3. 설정 → 근거 · 출처 -------------------------------------------------- */

  group('설정의 「근거 · 출처」', () {
    testWidgets('도움말에 있고, 누르면 목록 화면(소개 · 의료 안내 · 네 묶음)이 열린다', (t) async {
      final app = await seeded();
      await show(t, app, const SettingsScreen());
      final entry = find.byKey(const Key('settings-sources'));
      expect(entry, findsOneWidget);
      expect(find.descendant(of: entry, matching: find.text(kSourcesTitle)), findsOneWidget);

      await t.ensureVisible(entry);
      await t.tap(entry);
      await t.pumpAndSettle();
      expect(find.byType(SourcesScreen), findsOneWidget);
      /* 영어로 보는 심사자도 알아보게 제목에 「(Sources)」. */
      expect(find.widgetWithText(AppBar, kSourcesScreenTitle), findsOneWidget);
      expect(find.text(kSourcesIntro), findsOneWidget);
      expect(find.byKey(const Key('sources-disclaimer')), findsOneWidget);
      expect(find.textContaining('의료기기가 아니며 진단·치료를 대신하지 않습니다'), findsOneWidget);
      expect(find.textContaining('임신·수유 중이거나 약을 먹고 있다면'), findsOneWidget);
      for (final g in kCitationGroups) {
        await t.scrollUntilVisible(find.text(g), 300, scrollable: find.byType(Scrollable).last);
        expect(find.text(g), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('모든 출처가 목록에 한 번씩 나온다', (t) async {
      size(t, const Size(1000, 30000));
      await t.pumpWidget(MaterialApp(theme: mbLight(), home: const SourcesScreen()));
      await t.pumpAndSettle();
      for (final c in kCitations) {
        expect(find.byKey(ValueKey('citation-${c.id}')), findsOneWidget, reason: c.id);
      }
      expect(find.byType(CitationTile), findsNWidgets(kCitations.length));
    });
  });

  /* --- 목록 화면: 주제로 열기 · 누르기 ------------------------------------------- */

  group('근거 · 출처 화면', () {
    testWidgets('주제를 주면 그 출처만, 「모든 출처 보기」 로 전체', (t) async {
      size(t, const Size(1000, 30000));
      await t.pumpWidget(MaterialApp(theme: mbLight(), home: const SourcesScreen(topics: ['bmr'])));
      await t.pumpAndSettle();
      final want = citationsFor(['bmr']);
      expect(find.byType(CitationTile), findsNWidgets(want.length));
      expect(find.byKey(const ValueKey('citation-cunningham_1991')), findsOneWidget);
      expect(find.byKey(const ValueKey('citation-kouri_1995_ffmi')), findsNothing);
      expect(find.byKey(const Key('sources-disclaimer')), findsOneWidget);

      await t.tap(find.byKey(const Key('sources-toggle')));
      await t.pumpAndSettle();
      expect(find.byType(CitationTile), findsNWidgets(kCitations.length));
      expect(find.byKey(const ValueKey('citation-kouri_1995_ffmi')), findsOneWidget);
    });

    testWidgets('출처를 누르면 그 주소를 앱 밖에서 열고, 못 열면 주소를 알려 준다', (t) async {
      size(t, const Size(1000, 4000));
      await t.pumpWidget(MaterialApp(
          theme: mbLight(), home: const Scaffold(body: SourcesScreen(topics: ['bmr']))));
      await t.pumpAndSettle();
      final c = kCitations.firstWhere((c) => c.id == 'cunningham_1991');
      await t.tap(find.byKey(const ValueKey('citation-cunningham_1991')));
      await t.pump();
      expect(opened, [Uri.parse(c.url)]);

      openOk = false;
      await t.tap(find.byKey(const ValueKey('citation-cunningham_1991')));
      await t.pump();
      expect(find.textContaining('링크를 열지 못했습니다'), findsOneWidget);
      expect(find.textContaining(c.url), findsWidgets);
    });
  });

  /* --- 4 · 5. 숫자 옆의 「출처」 ------------------------------------------------ */

  group('화면의 「출처」 링크', () {
    testWidgets('설명 상자(Note)의 문장 끝 「출처」 도 눌린다', (t) async {
      size(t, const Size(400, 900));
      await t.pumpWidget(MaterialApp(
          theme: mbLight(),
          home: const Scaffold(
              body: Note(tone: Tone.warn, text: '목표 체지방률이 하한보다 낮습니다.', sources: ['body_fat_lower_limit']))));
      await t.tap(find.byType(SourceLink));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sources-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('citation-gallagher_2000_pbf')), findsOneWidget);
    });

    /* 시트 안 토스트가 바깥 Scaffold 로 가면 시트 밑에 깔려 안 보입니다 — 시트가 출처의 주된 길. */
    testWidgets('시트에서 출처를 못 열면 주소를 알리는 토스트가 시트 위에 보이고, 꾹 누르면 「복사했습니다」 도', (t) async {
      size(t, const Size(390, 844));
      await t.pumpWidget(MaterialApp(
          theme: mbLight(),
          home: const Scaffold(body: Center(child: SourceLink(['bmr'])))));
      await t.tap(find.byType(SourceLink));
      await t.pumpAndSettle();
      openOk = false;
      final tile = find.byKey(const ValueKey('citation-cunningham_1991'));
      await t.tap(tile);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('링크를 열지 못했습니다').hitTestable(), findsOneWidget);

      await t.longPress(tile);
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));
      await t.pump(const Duration(milliseconds: 800));
      expect(find.text('주소를 복사했습니다').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('앱이 정한 기준의 시트 · 목록에는 「관련 근거」 한 줄, 직접 출처면 없음', (t) async {
      size(t, const Size(390, 844));
      await t.pumpWidget(MaterialApp(
          theme: mbLight(),
          home: const Scaffold(
              body: Column(children: [
            SourceLink(['goal_refusals_safety'], key: Key('a')),
            SourceLink(['bmr'], key: Key('b')),
          ]))));
      await t.tap(find.byKey(const Key('a')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sources-app-set')), findsOneWidget);
      expect(find.text(appSetNote(['goal_refusals_safety'])!), findsOneWidget);
      Navigator.of(t.element(find.byKey(const Key('sources-sheet')))).pop();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('b')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sources-sheet')), findsOneWidget);
      expect(find.byKey(const Key('sources-app-set')), findsNothing);

      size(t, const Size(1000, 4000));
      await t.pumpWidget(MaterialApp(
          key: const Key('list'), theme: mbLight(), home: const SourcesScreen(topics: ['muscle_gain_rate'])));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sources-app-set')), findsOneWidget);
      await t.tap(find.byKey(const Key('sources-toggle')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sources-app-set')), findsNothing, reason: '전체 목록에는 없음');
    });

    testWidgets('「출처」 의 누르는 자리는 44 × 32 이상(문장 속 링크는 글줄 높이)', (t) async {
      size(t, const Size(400, 900));
      await t.pumpWidget(MaterialApp(
          theme: mbLight(),
          home: const Scaffold(
              body: Column(children: [
            SourceLink(['bmr'], key: Key('plain')),
            Note(text: '설명', sources: ['bmr']),
          ]))));
      final plain = t.getSize(find.byKey(const Key('plain')));
      expect(plain.height, greaterThanOrEqualTo(kSourceLinkMinHeight));
      expect(plain.width, greaterThanOrEqualTo(kSourceLinkMinWidth));
      final inline = t.getSize(find.descendant(of: find.byType(Note), matching: find.byType(SourceLink)));
      expect(inline.height, lessThan(kSourceLinkMinHeight));
    });

    testWidgets('종목 고르기에도 「출처」(운동 요령 · 세트 × 반복)', (t) async {
      size(t, const Size(400, 900));
      await t.pumpWidget(MaterialApp(
          theme: mbLight(), home: Scaffold(body: ExercisePicker(onPick: (_) {}))));
      await t.pumpAndSettle();
      final link = find.byKey(const ValueKey('pick-sources'));
      expect(link, findsOneWidget);
      expect(t.widget<SourceLink>(link).topics, kExercisePickerSources);
      linksAreValid(t);
    });

    testWidgets('플랜 — 하루 식단 목표 · 기간 · 궤적 · 운동 · 끼니 예시', (t) async {
      final app = await seeded();
      await show(t, app, Scaffold(body: PlanScreen(go: noop, today: _today)));
      expect(titledLink('하루 식단 목표'), findsOneWidget);
      expect(titledLink('주차별 궤적'), findsOneWidget);
      final plan = (app.state['plan'] as Map);
      expect(titledLink('${plan['label']} · ${plan['title']}'), findsOneWidget);
      expect(titledLink('${(plan['workout'] as Map)['splitName']}'), findsOneWidget);
      expect(titledLink('하루 ${(plan['diet'] as Map)['mealsPerDay']}끼 예시'), findsOneWidget);
      /* 「왜 이렇게 짰나요?」 — 펼치면 출처, 그리고 출처(Roth 2023)와 어긋나던 말은 고쳐서. */
      await t.tap(find.byKey(const Key('workout-why')));
      await t.pumpAndSettle();
      expect(find.textContaining('가장 강력한 수단'), findsNothing);
      expect(
          find.descendant(of: find.byKey(const Key('workout-why')), matching: find.byType(SourceLink)),
          findsOneWidget);
      /* 유산소가 WHO 기준(주 150분)보다 적으면 숫자 밑에 그 관계를, 짧은 의료 안내도. */
      final w = (plan['workout'] as Map).cast<String, Object?>();
      expect(find.byKey(const Key('cardio-who')), cardioBelowWho(w) ? findsOneWidget : findsNothing);
      expect(find.byKey(const Key('diet-medical')), findsOneWidget);
      final carb = core.jsToNumber((plan['macros'] as Map)['carbG']);
      expect(find.byKey(const Key('carb-below-kdri')), carb < 130 ? findsOneWidget : findsNothing);
      /* 끼니 메모 — 출처(Areta · Jäger)와 어긋나던 「끼니당 30~40g」 은 고쳐서. */
      await t.tap(find.byKey(const Key('diet-notes')));
      await t.pumpAndSettle();
      expect(find.textContaining('30~40g'), findsNothing);
      expect(find.textContaining('한 끼 20~40g'), findsOneWidget);
      /* 「반복을 다 채우면 …」 줄 옆에도. */
      expect(
          find.descendant(
              of: find.ancestor(of: find.text(kProgressionHint), matching: find.byType(Row)).first,
              matching: find.byType(SourceLink)),
          findsOneWidget);
      linksAreValid(t);
    });

    testWidgets('플랜의 「출처」 를 누르면 그 주제의 출처 시트 → 출처를 누르면 열림 → 모든 출처 보기', (t) async {
      final app = await seeded();
      await show(t, app, Scaffold(body: PlanScreen(go: noop, today: _today)));
      await t.tap(titledLink('하루 식단 목표'));
      await t.pumpAndSettle();
      final sheet = find.byKey(const Key('sources-sheet'));
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text(topicLabels(kDietTargetSources))),
          findsOneWidget);
      final want = citationsFor(kDietTargetSources);
      expect(find.descendant(of: sheet, matching: find.byType(CitationTile)),
          findsNWidgets(want.length));
      /* 시트에도 의료 안내가 한 줄. */
      expect(find.descendant(of: sheet, matching: find.text(kMedicalDisclaimer)), findsOneWidget);

      await t.tap(find.byKey(ValueKey('citation-${want.first.id}')));
      await t.pump();
      expect(opened, [Uri.parse(want.first.url)]);

      final all = find.byKey(const Key('sources-all'));
      await t.ensureVisible(all);
      await t.pumpAndSettle();
      await t.tap(all);
      await t.pumpAndSettle();
      expect(find.byType(SourcesScreen), findsOneWidget);
      expect(find.byKey(const Key('sources-sheet')), findsNothing);
    });

    testWidgets('홈 — 목표까지 · 기초대사량 · 브리핑의 식단 줄', (t) async {
      final app = await seeded();
      await show(t, app, Scaffold(body: HomeScreen(go: noop, )));
      expect(titledLink('목표까지'), findsOneWidget);
      /* 인바디 점수가 있으면 보이는 기초대사량 줄. */
      expect(
          find.descendant(
              of: find.ancestor(of: find.text('기초대사량'), matching: find.byType(Row)).first,
              matching: find.byType(SourceLink)),
          findsOneWidget);
      expect(
          find.descendant(of: find.byType(BriefingCard), matching: find.byType(SourceLink)),
          findsWidgets);
      linksAreValid(t);
    });

    testWidgets('목표 — 목표 칸 · 모드 카드', (t) async {
      final app = await seeded(withPlan: false);
      await show(t, app, const GoalScreen());
      expect(titledLink('목표'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, '목표 체중'), '80.5');
      await t.enterText(find.widgetWithText(TextField, '목표 골격근량'), '39');
      await t.pumpAndSettle();
      expect(
          find.descendant(
              of: find.ancestor(
                  of: find.textContaining('모드 — '), matching: find.byType(SectionTitle)),
              matching: find.byType(SourceLink)),
          findsOneWidget);
      linksAreValid(t);
    });

    testWidgets('키·체중 추정 시트 — 제목 옆에 출처', (t) async {
      final app = await seeded(withScan: false);
      await show(t, app, Scaffold(body: HomeScreen(go: noop)), at: const Size(400, 1400));
      await t.tap(find.widgetWithText(FilledButton, '인바디 없이 시작'));
      await t.pumpAndSettle();
      expect(find.byType(EstimateSheet), findsOneWidget);
      final links = find.descendant(of: find.byType(EstimateSheet), matching: find.byType(SourceLink));
      expect(links, findsWidgets);
      expect(t.widget<SourceLink>(links.first).topics, contains('body_fat_estimate'));
      /* 시트 위의 시트 — 추정 식의 출처가 뜹니다. */
      await t.tap(links.first);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('citation-gallagher_2000_pbf')), findsOneWidget);
      expect(find.byKey(const ValueKey('citation-lee_2000_smm')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('헬스 — 머리글에 세트 × 반복 · 휴식 · 추천 무게의 출처', (t) async {
      final app = await seeded();
      size(t, const Size(1000, 4000));
      await t.pumpWidget(host(app, const _Launch(child: WorkoutSessionScreen(dateKey: _todayKey, type: 'gym'))));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      expect(find.byType(ErrorWidget), findsNothing);
      final link = find.byWidgetPredicate(
          (w) => w is SourceLink && w.topics.contains('sets_reps_rest') && w.topics.contains('load_recommendation'));
      expect(link, findsOneWidget);
      linksAreValid(t);
    });

    testWidgets('식단 — 오늘 카드(목표 범위 · 단백질)', (t) async {
      final app = await seeded();
      await show(t, app, Scaffold(body: FoodScreen(go: noop)));
      expect(titledLink('오늘'), findsOneWidget);
      linksAreValid(t);
    });

    testWidgets('강도 · 기간 · 체크인 · 추이 · 측정 상세 · 판독 확인 · 온보딩에도', (t) async {
      final app = await seeded();
      for (final (name, screen) in <(String, Widget)>[
        ('강도', const IntensityScreen(goal: _goal)),
        ('기간', const DurationScreen()),
        ('체크인', const CheckinScreen()),
        ('추이', Scaffold(body: ProgressScreen(go: noop))),
        ('측정 상세', const ScanDetailScreen(scanId: 's1')),
        ('판독 확인', const ReviewScreen(draft: {'weightKg': 86.7, 'smmKg': 38.0, 'bfmKg': 20.0})),
      ]) {
        await show(t, app, screen);
        expect(find.byType(SourceLink), findsWidgets, reason: name);
        linksAreValid(t);
      }
    });
  });

  /* --- 6. 좁은 폰 · 큰 글자 ------------------------------------------------------ */

  group('넘치지 않는다', () {
    /* 아이패드의 호환 모드는 아이폰 크기(375 · 390 폭)로 그립니다. 320 은 가장 좁은 폰.
       320 · 1.3배에서는 이번 일과 무관한 줄(플랜 궤적 제목 · 기간 카드 제목 · 식단 단백질
       숫자)이 원래부터 넘쳐서 뺐습니다. */
    for (final (w, h, scale) in [
      (320.0, 640.0, 1.0),
      (375.0, 667.0, 1.0),
      (375.0, 667.0, 1.3),
      (390.0, 844.0, 1.3),
    ]) {
      testWidgets('${w.toInt()}px · 글자 $scale배', (t) async {
        final app = await seeded();
        for (final screen in <Widget>[
          Scaffold(body: PlanScreen(go: noop, today: _today)),
          Scaffold(body: HomeScreen(go: noop)),
          Scaffold(body: FoodScreen(go: noop)),
          Scaffold(body: ProgressScreen(go: noop)),
          const GoalScreen(),
          const IntensityScreen(goal: _goal),
          const DurationScreen(),
          const CheckinScreen(),
          const ScanDetailScreen(scanId: 's1'),
          const SettingsScreen(),
          const SourcesScreen(),
          const SourcesScreen(topics: ['protein_target']),
        ]) {
          await show(t, app, screen, at: Size(w, h), textScale: scale);
        }
        /* 시트도 — 가장 긴 주제 묶음(플랜 머리 카드). */
        await show(t, app, Scaffold(body: PlanScreen(go: noop, today: _today)),
            at: Size(w, h), textScale: scale);
        await t.tap(find.byType(SourceLink).first);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('sources-sheet')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    /* 위 시험은 첫 화면만 그립니다(ListView 는 보이는 만큼만 그림). 아래 카드 · 링크까지 —
       키를 길게 두고 같은 폭 · 글자 배율로 한 번에 다 그립니다. */
    for (final (w, scale) in [(320.0, 1.0), (360.0, 1.3), (375.0, 1.3), (390.0, 1.3)]) {
      testWidgets('${w.toInt()}px · 글자 $scale배 — 긴 화면으로 아래 카드까지', (t) async {
        final app = await seeded();
        for (final screen in <Widget>[
          Scaffold(body: PlanScreen(go: noop, today: _today)),
          Scaffold(body: HomeScreen(go: noop)),
          Scaffold(body: FoodScreen(go: noop)),
          Scaffold(body: ProgressScreen(go: noop)),
          const IntensityScreen(goal: _goal),
          const CheckinScreen(),
          const ScanDetailScreen(scanId: 's1'),
          const SettingsScreen(),
          const SourcesScreen(),
        ]) {
          await show(t, app, screen, at: Size(w, 6000), textScale: scale);
        }
      });
    }

    testWidgets('온보딩 마지막 장에 「근거 · 출처 보기」', (t) async {
      SharedPreferences.setMockInitialValues({});
      final app = await AppState.boot();
      await show(t, app, const OnboardingScreen(), at: const Size(320, 640));
      /* 1 → 2 → 3 장(키 · 나이를 넣어야 넘어갑니다). */
      await t.enterText(find.widgetWithText(TextField, '키'), '175');
      await t.enterText(find.widgetWithText(TextField, '나이'), '30');
      await t.pumpAndSettle();
      await t.tap(find.text('다음'));
      await t.pumpAndSettle();
      await t.tap(find.text('다음'));
      await t.pumpAndSettle();
      final btn = find.byKey(const Key('onboarding-sources'));
      await t.ensureVisible(btn);
      await t.pumpAndSettle();
      /* 의료 안내 — 의사와 상의하라는 말이 조건 없이. */
      expect(
          find.descendant(
              of: find.byKey(const Key('onboarding-medical')),
              matching: find.textContaining('건강에 관한 결정을 하기 전에는', findRichText: true)),
          findsOneWidget);
      await t.tap(btn);
      await t.pumpAndSettle();
      expect(find.byType(SourcesScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}

class _Launch extends StatelessWidget {
  const _Launch({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => child)),
            child: const Text('열기'),
          ),
        ),
      );
}
