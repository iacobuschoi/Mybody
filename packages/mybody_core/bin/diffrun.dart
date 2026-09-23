/* diffrun.dart — tools/difftest.js 가 부르는 Dart 쪽 실행기.
   사례 파일을 읽어 모듈을 돌리고 결과를 JSON 으로 찍습니다.
   형식은 JS 쪽과 같아야 합니다: {ok, v} 또는 {ok:false, v:"오류문구"}. */
import 'dart:convert';
import 'dart:io';

import 'package:mybody_core/crosscheck.dart' as crosscheck;
import 'package:mybody_core/engine.dart' as engine;
import 'package:mybody_core/js_num.dart';
import 'package:mybody_core/fooddb.dart' as fooddb;
import 'package:mybody_core/modes.dart' as modes;
import 'package:mybody_core/schedule.dart' as sched;
import 'package:mybody_core/store.dart' as store;
import 'package:mybody_core/suggest.dart' as suggest;

/// JSON.stringify 는 NaN·Infinity 를 **null** 로 씁니다. Dart 의 jsonEncode 는
/// 던집니다. 옮긴 코드에서 NaN 은 정상적으로 나옵니다(자바스크립트가 없는
/// 값으로 산수하면 NaN 이 되고, 우리는 그 길을 그대로 흉내 냅니다).
/// 그러니 여기서 같은 모양으로 맞춰 줘야 비교가 성립합니다.
Object? _clean(Object? v) {
  if (v is double && (v.isNaN || v.isInfinite)) return null;
  if (v is Map) {
    final out = <String, Object?>{};
    v.forEach((k, x) => out['$k'] = _clean(x));
    return out;
  }
  if (v is List) return v.map(_clean).toList();
  return v;
}

Map<String, Object?>? _m(Object? x) =>
    x == null ? null : (x as Map).cast<String, Object?>();

/* store·schedule 은 상태 전체가 입력입니다. 시계를 사례가 정한 순간으로
   세워 두고(원본 쪽도 같은 순간을 봅니다) 한 벌씩 새로 만듭니다. */
Object? _storeCase(String module, Map<String, Object?> c) {
  final fixed = DateTime.parse('${c['todayISO']}');
  final st = store.Store(now: () => fixed);
  st.replaceState((c['state'] as Map).cast<String, Object?>());
  final sc = sched.Schedule(st);
  final fn = module.substring(module.indexOf('.') + 1);
  switch (module.substring(0, module.indexOf('.'))) {
    case 'sched':
      if (fn == 'week') return sc.week();
      if (fn == 'weekSummary') return sc.weekSummary();
      if (fn == 'workoutStreak') return sc.workoutStreak();
      if (fn == 'foodStreak') return sc.foodStreak();
      break;
    case 'store':
      if (fn == 'dayTotals') return st.dayTotals(c['date']);
      if (fn == 'weekStartOf') return st.weekStartOf(c['date']);
      if (fn == 'dayKey') return st.dayKey(c['date']);
      if (fn == 'loggedDates') return st.loggedDates();
      if (fn == 'recentFoods') return st.recentFoods(c.containsKey('limit') ? c['limit'] : null);
      if (fn == 'sortedScans') return st.sortedScans();
      if (fn == 'weeklySnapshot') {
        st.weekSummaryOf = (ws) => sc.weekSummary(ws);
        st.streaksOf = () => {
          'workoutDays': sc.workoutStreak()['days'],
          'foodDays': sc.foodStreak()['days'],
        };
        return st.weeklySnapshot();
      }
      if (fn == 'lastMealLike') return st.lastMealLike('점심', c['date']);
      if (fn == 'yesterdayLogs') return st.yesterdayLogs(c['date']);
      if (fn == 'scheduleDay') return st.scheduleDay(c['date']);
      break;
  }
  throw StateError('모르는 모듈: $module');
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: diffrun <module> <cases.json>');
    exit(2);
  }
  final module = args[0];
  final cases = jsonDecode(File(args[1]).readAsStringSync()) as List;

  /* 측정 노이즈 바닥은 modes.js 가 정합니다. 사례마다 실어 보내면 (근거
     문장이 10KB 라) 파일이 수십 MB 가 되므로 따로 한 번만 받습니다.
     안 주면 engine.js 의 대체값과 같은 기본값을 씁니다. */
  if (args.length > 2 && args[2].isNotEmpty) {
    engine.engineNoise =
        (jsonDecode(File(args[2]).readAsStringSync()) as Map).cast<String, Object?>();
  }

  final out = <Map<String, Object?>>[];
  for (final c0 in cases) {
    final c = c0 as Map<String, Object?>;
    try {
      Object? v;
      switch (module) {
        case 'crosscheck':
          v = crosscheck.run(_m(c['scan']), _m(c['profile']), _m(c['prev']));
          break;
        case 'engine.validateScan':
          v = engine.validateScan(_m(c['scan']), _m(c['prev']));
          break;
        case 'engine.derive':
          v = engine.derive(_m(c['scan'])!, _m(c['profile'])!);
          break;
        case 'engine.classifyGoal':
          v = engine.classifyGoal(_m(c['cur'])!, _m(c['goal'])!);
          break;
        case 'engine.paramsAt':
          v = engine.paramsAt(c['a'], c['mode'], _m(c['con']));
          break;
        case 'engine.resolveTraining':
          v = engine.resolveTraining(
              _m(c['profile'])!, _m(c['params'])!, _m(c['goalInfo']));
          break;
        case 'engine.baseSmmRatePerWeek':
          /* ffmKg 는 JS 에서 `ffmKg != null` 로 갈립니다 — null 이면
             체중의 80% 를 앵커로 쓰고 FFMI 천장도 적용하지 않습니다.
             그래서 여기서도 null 을 살려서 넘깁니다. */
          v = engine.baseSmmRatePerWeek(
              jsToNumber(c['weightKg']), _m(c['profile'])!,
              jsToNumber(c['smmToFfm']),
              c['ffmKg'] == null ? null : jsToNumber(c['ffmKg']),
              c.containsKey('weekIndex') ? c['weekIndex'] : null);
          break;
        case 'engine.stepWeek':
          v = engine.stepWeek(_m(c['st'])!, '${c['phase']}', _m(c['params'])!,
              _m(c['profile'])!, jsToNumber(c['k']), c['weekIndex']);
          break;
        case 'engine.simulateSimultaneous':
          v = engine.simulateSimultaneous(_m(c['cur'])!, _m(c['goal'])!,
              _m(c['profile'])!, c['a'],
              engine.classifyGoal(_m(c['cur'])!, _m(c['goal'])!), _m(c['con']));
          break;
        case 'engine.simulateSplit':
          v = engine.simulateSplit(_m(c['cur'])!, _m(c['goal'])!,
              _m(c['profile'])!, c['a'],
              engine.classifyGoal(_m(c['cur'])!, _m(c['goal'])!), _m(c['con']));
          break;
        case 'engine.bestAt':
          v = engine.bestAt(_m(c['cur'])!, _m(c['goal'])!, _m(c['profile'])!,
              c['a'], engine.classifyGoal(_m(c['cur'])!, _m(c['goal'])!),
              _m(c['con']));
          break;
        case 'engine.compareLevels':
          v = engine.compareLevels(_m(c['scan'])!, _m(c['profile'])!, _m(c['goal'])!,
              c['startDateISO'], c['deadlineWeeks'], _m(c['modeDef']));
          break;
        case 'engine.macrosFor':
          v = engine.macrosFor(_m(c['sim'])!, _m(c['cur'])!, _m(c['profile'])!);
          break;
        case 'engine.workoutFor':
          v = engine.workoutFor(_m(c['sim'])!, _m(c['cur'])!, _m(c['profile'])!,
              _m(c['scan']), _m(c['goalInfo']));
          break;
        case 'engine.dietFor':
          v = engine.dietFor(_m(c['macros'])!, _m(c['profile'])!);
          break;
        case 'engine.milestonesFrom':
          v = engine.milestonesFrom(
              (c['traj'] as List).map((x) => _m(x)!).toList(), c['startISO']);
          break;
        case 'engine.dietAdherence':
          v = engine.dietAdherence(
              (c['days'] as List).map((x) => _m(x)!).toList(), _m(c['target']));
          break;
        case 'engine.dietNudge':
          /* 시계를 고정해서 받습니다 — JS 쪽도 같은 순간을 봅니다. */
          v = engine.dietNudge(_m(c['today'])!, _m(c['target']),
              now: DateTime.parse('${c['nowISO']}'));
          break;
        case 'engine.checkinAdvice':
          v = engine.checkinAdvice(
              _m(c['plan']), _m(c['expected'])!, _m(c['actual'])!, _m(c['adherence']));
          break;
        case 'engine.planDrift':
          /* 원본 engine.js 는 `global.MB_MODES` 가 있으면 byId 를 씁니다.
             옮긴 쪽은 그 연결을 함수로 꽂습니다 (앱에서도 시작할 때 꽂습니다). */
          engine.modeLookup = modes.byId;
          v = engine.planDrift(_m(c['plan']),
              (c['scans'] as List?)?.map((x) => _m(x)!).toList(), _m(c['profile'])!);
          break;
        case 'engine.buildPlan':
          v = engine.buildPlan(
              _m(c['comparison'])!, c['level'], _m(c['scan']), _m(c['profile'])!);
          break;
        case 'store.dayKey':
        case 'store.weekStartOf':
        case 'store.dayTotals':
        case 'store.loggedDates':
        case 'store.recentFoods':
        case 'store.sortedScans':
        case 'store.lastMealLike':
        case 'store.yesterdayLogs':
        case 'store.scheduleDay':
        case 'store.weeklySnapshot':
        case 'sched.week':
        case 'sched.weekSummary':
        case 'sched.workoutStreak':
        case 'sched.foodStreak':
          v = _storeCase(module, c);
          break;
        case 'fooddb.search':
          v = fooddb.search(c['q'], c.containsKey('limit') ? c['limit'] : null);
          break;
        case 'fooddb.similar':
          v = fooddb.similar(c['q'], c.containsKey('limit') ? c['limit'] : null);
          break;
        case 'fooddb.scaled':
          v = fooddb.scaled(fooddb.byName(c['name'])!, c['mult']);
          break;
        case 'suggest.suggestSnack':
          v = suggest.suggestSnack(_m(c['opts'])!);
          break;
        case 'suggest.suggestEatOut':
          v = suggest.suggestEatOut(_m(c['opts'])!);
          break;
        case 'suggest.suggestMeal':
          v = suggest.suggestMeal(_m(c['opts'])!);
          break;
        case 'suggest.summaryText':
          v = suggest.summaryText(suggest.suggestMeal(_m(c['opts'])!));
          break;
        case 'modes.select':
          v = modes.select(_m(c['input'])!);
          break;
        case 'engine.scanCurve':
          v = engine.scanCurve(_m(c['cur'])!, _m(c['goal'])!, _m(c['profile'])!,
              engine.classifyGoal(_m(c['cur'])!, _m(c['goal'])!), _m(c['con']));
          break;
        default:
          stderr.writeln('모르는 모듈: $module');
          exit(2);
      }
      out.add({'ok': true, 'v': _clean(v)});
    } catch (e) {
      out.add({'ok': false, 'v': e.toString()});
    }
  }
  stdout.write(jsonEncode(out));
}
