/* =============================================================================
 * briefing.dart — 홈 맨 위 「오늘 브리핑」 의 계산 (위젯 없음)
 *
 * 앱을 열면 세 가지가 한눈에 보여야 합니다 — 오늘 무엇을 하는 날인지,
 * 오늘 어떻게 먹을지, **지금 당장** 무엇을 할지. 이 파일은 상태에서 그
 * 줄들과 버튼 하나를 뽑습니다. 화면(home.dart 의 BriefingCard)은 그리기만
 * 합니다. 그래서 시험은 위젯 없이 아침 8시와 밤 9시 반을 세워 볼 수 있습니다.
 *
 * 지키는 것 셋:
 *
 *  1. **주 버튼은 하나입니다.** 지금 이 시각에 할 일 하나. 나머지는 보조
 *     버튼 둘까지. 할 일 넷을 나란히 놓으면 사람은 아무것도 안 고릅니다.
 *
 *  2. **없는 것을 있다고 하지 않습니다.** 인바디가 없으면 "올려 달라",
 *     계획이 없으면 "계획이 없다" 고 말합니다. 씨앗값으로 오늘 할 일을
 *     지어내지 않습니다. 다 했을 때만 "끝" 이라고 합니다 — 운동 · 체크인에
 *     더해, **이 시각까지 적었어야 할 끼니가 다 적혀 있어야** 끝입니다.
 *     11시부터 아침, 15시부터 점심, 20시부터 저녁을 묻습니다. 15~17시는
 *     저녁이 남았으니 끝이 아니라 「저녁까지 쉬어요」 입니다.
 *
 *  3. **시각은 밖에서 받습니다.** now 를 안 주면 저장소의 시계를 씁니다 —
 *     그 시계가 곧 "오늘"(dayKey) 의 기준이라, 브리핑과 일정이 서로 다른
 *     날을 보는 일이 없습니다. 체크인 주도 그 날짜에서 셉니다(저장소의
 *     시계가 아니라) — now 를 따로 준 시험이 같은 날을 보게 하려는 것입니다.
 *
 * 시각 규칙 (now.hour):
 *   끼니   — 11시 전 아침 · 11~15시 점심 · 15~17시 간식 · 17시부터 저녁.
 *            식단 화면의 guessMeal 이 이 경계(mealNow)를 그대로 씁니다 — 브리핑이
 *            「저녁 기록」 을 누르라 하는데 식단 탭이 간식으로 열리면 저녁이
 *            간식으로 저장됩니다. 간식은 안 적어도 "남은 할 일" 로 치지
 *            않습니다 — 간식은 의무가 아닙니다.
 *   운동   — 15시부터 「운동 시작」 이 주 버튼. 그 전엔 밥부터(끼니 기록).
 *            21시부터는 「15분 맨몸 운동」 — 밤 9시에 헬스장은 안 갑니다.
 *   체크인 — 12시 전이면 끼니 다음 순서로 주 버튼. 체중은 아침에 재야
 *            지난주와 견줄 수 있습니다. 오후에는 보조 버튼입니다.
 *
 * 문구에 기호와 이모지를 안 넣습니다(체크 표시 · 폭죽). 앱에 넣은 한글
 * 글꼴에 없는 글자라 웹에서는 구글 글꼴 요청이 나갑니다 — symbols.dart 의
 * 교훈. 완료는 화면이 아이콘(icon: 'done')과 색으로 그립니다.
 * ========================================================================== */
import 'package:mybody_core/mybody_core.dart' as core;

import 'app_state.dart';
import 'checkins.dart';
import 'ui/fmt.dart';

/// 버튼 하나. route · arg 는 셸의 go(route, arg) 에 그대로 넘깁니다.
class BriefAction {
  const BriefAction({required this.label, required this.route, this.arg, this.primary = false});
  final String label;
  final String route;
  final Object? arg;
  final bool primary;

  BriefAction asPrimary() => BriefAction(label: label, route: route, arg: arg, primary: true);
}

/// 브리핑의 한 줄. icon 은 그림의 열쇠말이지 글자가 아닙니다.
class BriefLine {
  const BriefLine({required this.icon, required this.text, this.done = false});

  /// 'gym' | 'cardio' | 'food' | 'checkin' | 'rest' | 'done' | 'scan'
  final String icon;
  final String text;
  final bool done;
}

class Briefing {
  const Briefing({
    required this.headline,
    this.sub,
    this.lines = const [],
    this.primary,
    this.secondary = const [],
    this.celebrate,
    this.allDone = false,
  });
  final String headline;
  final String? sub;
  final List<BriefLine> lines;
  final BriefAction? primary;
  final List<BriefAction> secondary;

  /// 축하 한 줄(예: '운동 3일 연속') — 오늘 운동을 마쳤을 때만. 없으면 null.
  final String? celebrate;

  /// 오늘 몫을 다 했는가 — 화면이 폭죽 아이콘을 그립니다.
  final bool allDone;
}

/// 이 시각부터 운동이 주 버튼입니다. 그 전엔 끼니 기록이 먼저입니다.
const int kWorkoutHour = 15;

/// 이 시각부터는 헬스장 대신 15분 맨몸 운동을 권합니다.
const int kLateHour = 21;

/// 체크인을 주 버튼으로 미는 아침의 끝.
const int kCheckinMorningEnd = 12;

/// 지금 적을 끼니. 식단 화면의 guessMeal 이 이 함수를 그대로 씁니다(아침 11시 전 ·
/// 점심 15시 전 · 간식 17시 전). 17시부터는 저녁이고 위쪽 경계는 없습니다 — 저녁을
/// 밤 10시에 적는 사람도 있습니다.
String mealNow(int hour) {
  if (hour < 11) return '아침';
  if (hour < 15) return '점심';
  if (hour < 17) return '간식';
  return '저녁';
}

/// 이 시각까지 적었어야 할 끼니. 아침은 점심이 되는 11시부터, 점심은 15시부터,
/// 저녁은 20시부터 묻습니다 — 저녁은 8시 넘어 먹는 사람이 많아 늦게 묻습니다.
/// 간식은 없습니다 — 의무가 아닙니다.
List<String> mealsDueBy(int hour) => [
      if (hour >= 11) '아침',
      if (hour >= 15) '점심',
      if (hour >= 20) '저녁',
    ];

/// 15시부터 이 시각 전까지는 저녁이 남았으니 「끝」 이 아니라 「저녁까지 쉬어요」.
const int kDinnerHour = 17;

Briefing buildBriefing(AppState app, {DateTime? now}) {
  final store = app.store;
  final t = now ?? (store.now ?? DateTime.now)();
  final hour = t.hour;
  final dateKey = store.dayKey(t);
  final st = app.state;
  final hasScans = store.sortedScans().isNotEmpty;

  final plan = _map(st['plan']);
  final workout = _map(plan?['workout']);
  final sessions = workout?['sessions'];
  final macros = _map(plan?['macros']);
  final dow = t.weekday - 1;                                   // 월=0
  Map<String, Object?>? sessionAt(int i) =>
      sessions is List && sessions.length == 7 ? _map(sessions[i]) : null;
  final session = sessionAt(dow);
  final tomorrow = sessionAt((dow + 1) % 7);

  /* --- 오늘 운동 ------------------------------------------------------------ */
  final day = store.scheduleDay(dateKey);
  final planned = (day['plan'] as List?) ?? const [];
  final done = (day['done'] as Map?) ?? const {};
  /* scheduleDay 는 기록(log)이 있을 때만 그 칸을 줍니다 — 없을 수 있다고 보고 읽습니다. */
  final log = _map(day['log']);

  var gymPlanned = planned.contains('gym');
  final cardioPlanned = planned.contains('cardio');
  /* 일정 칸이 비어 있으면 플랜의 분할표를 봅니다. 「플랜대로 채우기」 를 아직
     안 누른 첫 주에 매일 "쉬는 날" 이라고 하면 틀린 말입니다. 칸에 무엇이든
     적혀 있으면 칸이 이깁니다 — 사람이 고른 것이 언제나 엔진보다 먼저입니다. */
  if (planned.isEmpty && session != null && session['rest'] != true) gymPlanned = true;
  final gymDone = core.jsTruthy(done['gym']);
  final cardioDone = core.jsTruthy(done['cardio']);
  final gymPending = gymPlanned && !gymDone;
  final cardioPending = cardioPlanned && !cardioDone;

  final label = session != null && session['rest'] != true ? '${session['label']}' : '헬스';
  final minutes = session?['minutes'];
  final cardioMin = _cardioMinutes(app, workout, dateKey);
  final cardioText = cardioMin == null ? '유산소' : '유산소 ${n0(cardioMin)}분';

  final lines = <BriefLine>[];
  String? workoutHead;                                        // 운동이 남아 있을 때의 머리글

  if (gymPlanned) {
    if (gymPending) {
      var text = '오늘은 $label 하는 날';
      if (minutes != null) text += ' · ${n0(minutes)}분';
      if (cardioPending) text += ' · $cardioText';
      lines.add(BriefLine(icon: 'gym', text: text));
      workoutHead = '오늘은 $label 하는 날';
    } else {
      lines.add(BriefLine(icon: 'done', text: _gymDone(label, _map(log?['gym'])), done: true));
    }
    /* 헬스 줄에 못 접은 유산소 — 둘 중 하나라도 끝났으면 따로 한 줄. */
    if (cardioPlanned && (gymDone || cardioDone)) {
      if (cardioDone) {
        lines.add(BriefLine(icon: 'done', text: _withLog('유산소 완료', _map(log?['cardio'])), done: true));
      } else {
        lines.add(BriefLine(icon: 'cardio', text: '$cardioText 남았어요'));
        workoutHead = '유산소만 남았어요';
      }
    }
  } else if (cardioPlanned) {
    if (cardioPending) {
      lines.add(BriefLine(icon: 'cardio', text: '오늘은 유산소 하는 날${cardioMin == null ? '' : ' · ${n0(cardioMin)}분'}'));
      workoutHead = '오늘은 유산소 하는 날';
    } else {
      lines.add(BriefLine(icon: 'done', text: _withLog('유산소 완료', _map(log?['cardio'])), done: true));
    }
  } else if (plan == null) {
    if (hasScans) lines.add(const BriefLine(icon: 'gym', text: '운동 계획이 아직 없어요'));
  } else {
    final p = macros?['proteinG'];
    lines.add(BriefLine(
        icon: 'rest',
        text: p == null ? '오늘은 쉬는 날' : '오늘은 쉬는 날 — 단백질 ${n0(p)}g 챙기기'));
  }

  /* --- 오늘 식단 ------------------------------------------------------------ */
  final meal = mealNow(hour);
  final logged = {for (final l in store.logsForDate(dateKey)) '${l['meal']}'};
  final mealLogged = logged.contains(meal);
  final mealPending = !mealLogged && meal != '간식';
  /* 지나간 끼니 중 안 적은 것. 지금 끼니는 mealPending 이 맡습니다. */
  final missed = [for (final m in mealsDueBy(hour)) if (m != meal && !logged.contains(m)) m];
  String? remainLine;                                         // '남은 N kcal · 단백질 …'
  if (hasScans) {
    String food;
    if (macros == null) {
      food = '식단 목표는 계획을 세우면 나옵니다';
    } else {
      final tot = store.dayTotals(dateKey);
      final remainKcal = core.jsToNumber(macros['intakeKcal']) - core.jsToNumber(tot['kcal']);
      final remainP = core.jsToNumber(macros['proteinG']) - core.jsToNumber(tot['p']);
      if (remainKcal < 0) {
        /* 음수를 "남은 −300kcal" 로 찍지 않습니다. 넘었으면 넘었다고, 그리고
           다음 끼니를 어떻게 할지까지. */
        food = '오늘 ${n0(-remainKcal)}kcal 넘었어요 — ${logged.contains('저녁') ? '내일은' : '저녁은'} 가볍게';
      } else {
        food = '남은 ${n0(remainKcal)}kcal · 단백질 ${remainP > 0 ? '${n0(remainP)}g' : '다 채웠어요'}';
      }
      remainLine = food;
      if (mealLogged) {
        food += ' · $meal 적었어요';
      } else if (meal != '간식') {
        food += ' · $meal 기록할 시간';
      }
    }
    lines.add(BriefLine(icon: 'food', text: food));
  }

  /* --- 체크인 --------------------------------------------------------------- */
  final checkinDue = hasScans && plan != null && checkinOfDay(store, dateKey) == null;
  if (checkinDue) lines.add(const BriefLine(icon: 'checkin', text: '이번 주 체크인 아직'));

  /* --- 지금 할 일 하나 ------------------------------------------------------ */
  final late = hour >= kLateHour;
  final gymAct = BriefAction(
      label: late ? '15분 맨몸 운동' : '운동 시작',
      route: 'workout',
      arg: {'date': dateKey, 'type': late ? 'bodyweight' : 'gym'});
  final cardioAct = BriefAction(
      label: '유산소 시작', route: 'workout', arg: {'date': dateKey, 'type': 'cardio'});
  final mealAct = BriefAction(label: '$meal 기록', route: 'food');
  const checkinAct = BriefAction(label: '이번 주 체크인', route: 'checkin');
  const goalAct = BriefAction(label: '목표 정하기', route: 'goal');
  const uploadAct = BriefAction(label: '인바디 올리기', route: 'upload');

  /* 우선순위대로 쌓고 첫 것이 주 버튼, 다음 둘이 보조 버튼입니다. */
  final order = <BriefAction>[];
  if (hour >= kWorkoutHour) {
    if (gymPending) order.add(gymAct);
    if (cardioPending) order.add(cardioAct);
  }
  if (mealPending) order.add(mealAct);
  if (checkinDue && hour < kCheckinMorningEnd) order.add(checkinAct);
  if (hour < kWorkoutHour) {
    if (gymPending) order.add(gymAct);                         // 아침에 운동하는 사람도 있습니다
    if (cardioPending) order.add(cardioAct);
  }
  if (checkinDue && hour >= kCheckinMorningEnd) order.add(checkinAct);
  if (hasScans && plan == null) order.add(goalAct);

  if (!hasScans) {
    /* 인바디가 없으면 다른 무엇보다 그것부터. 일정에 적어 둔 운동은 그대로
       보여 줍니다 — 체중을 모른다고 오늘 헬스가 없어지는 건 아닙니다. */
    lines.insert(0, const BriefLine(icon: 'scan', text: '사진 한 장이면 오늘 할 일이 나옵니다'));
    return Briefing(
      headline: '인바디 결과지를 올려주세요',
      lines: lines,
      primary: uploadAct.asPrimary(),
      secondary: [for (final a in order) if (a.route == 'workout') a].take(2).toList(),
    );
  }

  var primary = order.isEmpty ? null : order.first.asPrimary();
  final secondary = order.skip(1).take(2).toList();

  /* --- 머리글 --------------------------------------------------------------- */
  String headline;
  String? sub;
  var allDone = false;
  if (workoutHead != null) {
    headline = workoutHead;
  } else if (mealPending) {
    headline = '$meal 기록할 시간';
  } else if (checkinDue) {
    headline = '이번 주 체크인 할 차례';
  } else if (plan == null) {
    headline = '목표를 정하면 오늘 할 일이 나옵니다';
  } else if (missed.isNotEmpty) {
    /* 다른 건 다 했어도 지나간 끼니가 비어 있으면 끝이 아닙니다. 식단 탭은 끼니
       카드마다 넣는 자리가 있어서 거기서 그 끼니에 적습니다. */
    headline = '${missed.join(' · ')} 아직 안 적었어요';
    primary ??= BriefAction(label: '${missed.first} 기록', route: 'food', primary: true);
  } else if (hour >= kWorkoutHour && hour < kDinnerHour) {
    /* 간식 시간 — 오늘 몫은 다 했지만 저녁이 남았습니다. "끝" 은 거짓말입니다. */
    headline = '저녁까지 쉬어요';
    sub = remainLine;
  } else {
    headline = '오늘 할 일 끝';
    allDone = true;
    if (tomorrow != null) {
      sub = tomorrow['rest'] == true ? '내일은 쉬는 날' : '내일은 ${tomorrow['label']}';
    }
  }
  if (plan == null) sub = '언제까지 어디로 갈지 정하면 주차별 궤적과 식단·운동 처방이 나옵니다.';

  /* 스트릭은 행동에만 답니다(홈의 규칙). 설정에서 껐으면 여기서도 안 보입니다. */
  String? celebrate;
  final settings = _map(st['settings']) ?? const {};
  if ((gymDone || cardioDone) && !core.jsTruthy(settings['hideStreaks'])) {
    final streak = core.jsToNumber(app.schedule.workoutStreak(dateKey)['days']);
    if (streak >= 2) celebrate = '운동 ${n0(streak)}일 연속';
  }

  return Briefing(
    headline: headline,
    sub: sub,
    lines: lines,
    primary: primary,
    secondary: secondary,
    celebrate: celebrate,
    allDone: allDone,
  );
}

/* --- 작은 도우미 ------------------------------------------------------------ */

Map<String, Object?>? _map(Object? x) => x is Map ? x.cast<String, Object?>() : null;

/// 헬스 칸의 완료 줄. 밤에 한 맨몸 운동(kind 'bodyweight')은 분할 이름('하체 A 완료')이
/// 아니라 '맨몸 운동 완료' 입니다 — 하체 A 를 한 게 아니니까요.
String _gymDone(String label, Map<String, Object?>? e) =>
    _withLog(e?['kind'] == 'bodyweight' ? '맨몸 운동 완료' : '$label 완료', e);

/// 운동 기록(분 · km · kcal)을 문구 뒤에 붙입니다. 기록은 운동 화면이 남기고
/// 여기서는 있으면 읽고 없으면 넘어갑니다.
String _withLog(String text, Map<String, Object?>? e) {
  if (e == null) return text;
  var out = text;
  if (core.jsTruthy(e['minutes'])) out += ' · ${n0(e['minutes'])}분';
  if (core.jsTruthy(e['km'])) out += ' · ${n1(e['km'])}km';
  if (core.jsTruthy(e['kcal'])) out += ' · 약 ${n0(e['kcal'])}kcal';
  return out;
}

/// 그 날(dateKey)이 든 계획 주의 체크인 — checkins.dart 의 checkinThisWeek 와 같은
/// 규칙(같은 계획 주이거나 5일 안)인데, "오늘" 을 저장소의 시계가 아니라 브리핑이
/// 받은 날짜로 잡습니다. 규칙 3 — 브리핑의 모든 줄이 같은 날을 봅니다.
Map<String, Object?>? checkinOfDay(core.Store store, String dateKey) {
  final plan = _map(store.get()['plan']);
  if (plan == null) return null;
  final start = plan['startDate'];
  final nowWeek = core.planWeekOf(start, dateKey);
  final nowDay = core.planDayOf(start, dateKey);
  Map<String, Object?>? hit;
  for (final c in checkinsInPlan(store, plan)) {
    final k = store.dayKey(c['at']);
    if (core.planWeekOf(start, k) == nowWeek ||
        nowDay - core.planDayOf(start, k) < kCheckinMergeDays) {
      hit = c;
    }
  }
  return hit;
}

/// 오늘 유산소 몇 분인가 — 플랜에는 주당 분(分)만 있고 요일이 없습니다.
/// 이번 주에 유산소로 정한 날 수로 나눕니다. 정한 날이 없으면 주당 분 전부.
double? _cardioMinutes(AppState app, Map<String, Object?>? workout, String dateKey) {
  final perWeek = core.jsToNumber(workout?['cardioMinPerWeek']);
  if (!(perWeek > 0)) return null;
  final days = (app.schedule.week(app.store.weekStartOf(dateKey))['days'] as List)
      .cast<Map<String, Object?>>();
  var n = 0;
  for (final d in days) {
    if ((d['plan'] as List).contains('cardio')) n++;
  }
  return core.jsRound(perWeek / (n < 1 ? 1 : n)).toDouble();
}
