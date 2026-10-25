/* =============================================================================
 * workout_calendar.dart — 지난 운동 기록의 「달력」
 *
 * 홈의 「이번 주 운동」 은 이번 주 일곱 칸뿐이고 달성률은 최근 7 · 30일뿐이라,
 * 지난주 · 지난달을 다시 볼 길이 없었습니다(의견 84 — "달력 이전 기록 보게
 * 해주세요(저번주 or 저번달) 이번주 기록만 있으니까 so sad").
 *
 *   한 달 칸    홈의 요일 칸과 **같은 그림**(DayMark · 헬스/유산소 점) — 지킴 · 놓침 ·
 *               쉬는 날을 새로 배우지 않게.
 *   ‹ ›        한 달씩. 왼쪽 끝은 처음 기록이 있는 달, 오른쪽 끝은 이번 달.
 *               옆으로 밀어도 넘어갑니다. 멀리 왔으면 「처음 기록으로」 · 「이번 달로」.
 *   날 누르기   그 날 무엇을 했는지 — 기록(종목 · 세트 · 유산소)이 있으면 날짜별 카드
 *               그대로, 체크만 했으면 체크한 것만. 이 화면은 읽기만 합니다 — 지난 날을
 *               고치는 길은 홈의 요일 칸입니다.
 *
 * 일정은 날짜마다 따로 적혀 있어서(state['schedule']['YYYY-MM-DD']) 적힌 적 없는 날은
 * 쉬는 날입니다 — 앱을 쓰기 전 날들이 「놓침」 으로 칠해지지 않습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../app_state.dart';
import '../scope.dart';
import '../ui/widgets.dart';
import 'adherence.dart' show DayMark, DayMarkLegend, DayMarkState, dayMarkState;

/// 'YYYY-MM' 로 가리키는 달.
typedef CalMonth = ({int year, int month});

CalMonth calMonthOf(String key) =>
    (year: int.parse(key.substring(0, 4)), month: int.parse(key.substring(5, 7)));

CalMonth calShift(CalMonth m, int n) {
  final d = DateTime(m.year, m.month + n);
  return (year: d.year, month: d.month);
}

int calCompare(CalMonth a, CalMonth b) =>
    a.year != b.year ? a.year.compareTo(b.year) : a.month.compareTo(b.month);

String calLabel(CalMonth m) => '${m.year}년 ${m.month}월';

/// 일정에 무엇이든(계획 · 체크 · 기록) 적힌 가장 이른 날. 없으면 null.
String? firstScheduleKey(Map<String, Object?> state) {
  final sch = state['schedule'];
  if (sch is! Map) return null;
  String? first;
  for (final k in sch.keys) {
    final e = sch[k];
    if (e is! Map) continue;
    final plan = e['plan'], done = e['done'], log = e['log'];
    final any = (plan is List && plan.isNotEmpty) ||
        (done is Map && done.isNotEmpty) ||
        (log is Map && log.isNotEmpty);
    if (!any) continue;
    final key = '$k';
    if (first == null || key.compareTo(first) < 0) first = key;
  }
  return first;
}

/// 그 달의 날들 — 홈 요일 칸과 같은 모양의 맵(key · dayNum · plan · done · log?).
List<Map<String, Object?>> monthDays(AppState app, CalMonth m) {
  final n = DateTime(m.year, m.month + 1, 0).day;
  return [
    for (var d = 1; d <= n; d++)
      () {
        final key = app.store.dayKey(DateTime(m.year, m.month, d));
        return {...app.store.scheduleDay(key), 'key': key, 'dayNum': d};
      }(),
  ];
}

/// 한 달 요약 — 계획한 날 · 지킨 날 · 놓친 날.
({int planned, int kept, int missed}) monthSummary(List<Map<String, Object?>> days, String today) {
  var planned = 0, kept = 0, missed = 0;
  for (final d in days) {
    final s = dayMarkState(d, today: today);
    if (s == DayMarkState.rest) continue;
    planned++;
    if (s == DayMarkState.kept) kept++;
    if (s == DayMarkState.missed) missed++;
  }
  return (planned: planned, kept: kept, missed: missed);
}

/// 지난 운동 기록의 달력. [detail] 은 기록(log)이 있는 날을 그리는 카드 — 날짜별 목록과 같은 것.
class WorkoutCalendar extends StatefulWidget {
  const WorkoutCalendar({super.key, required this.detail});
  final Widget Function(String key) detail;

  @override
  State<WorkoutCalendar> createState() => _WorkoutCalendarState();
}

class _WorkoutCalendarState extends State<WorkoutCalendar> {
  CalMonth? _month;
  String? _selected;

  void _go(CalMonth m) => setState(() {
        _month = m;
        _selected = null;
      });

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final today = app.store.dayKey();
    final last = calMonthOf(today);
    final firstKey = firstScheduleKey(app.state);
    /* 처음 기록이 앞날뿐이면(다음 주 계획만 켜 둔 사람) 이번 달에서 시작합니다. */
    var first = firstKey == null ? last : calMonthOf(firstKey);
    if (calCompare(first, last) > 0) first = last;
    var m = _month ?? last;
    if (calCompare(m, first) < 0) m = first;
    if (calCompare(m, last) > 0) m = last;
    final canPrev = calCompare(m, first) > 0;
    final canNext = calCompare(m, last) < 0;

    final days = monthDays(app, m);
    final sum = monthSummary(days, today);
    final lead = DateTime(m.year, m.month, 1).weekday - 1;   // 월요일부터
    final cells = <Map<String, Object?>?>[...List.filled(lead, null), ...days];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor);

    return ListView(
      key: const ValueKey('history-calendar'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconButton(
                key: const ValueKey('cal-prev'),
                tooltip: '지난달',
                onPressed: canPrev ? () => _go(calShift(m, -1)) : null,
                icon: const Icon(LucideIcons.chevronLeft),
              ),
              Expanded(
                child: Text(calLabel(m),
                    key: const ValueKey('cal-month'),
                    textAlign: TextAlign.center,
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                key: const ValueKey('cal-next'),
                tooltip: '다음 달',
                onPressed: canNext ? () => _go(calShift(m, 1)) : null,
                icon: const Icon(LucideIcons.chevronRight),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              for (final d in core.kDow)
                Expanded(
                  child: Text(d, textAlign: TextAlign.center,
                      style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                ),
            ]),
            const SizedBox(height: 4),
            /* 옆으로 밀어도 한 달씩 — 오른쪽으로 밀면 지난달. */
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (e) {
                final v = e.primaryVelocity ?? 0;
                if (v > 200 && canPrev) _go(calShift(m, -1));
                if (v < -200 && canNext) _go(calShift(m, 1));
              },
              child: Column(children: [
                for (var r = 0; r < cells.length; r += 7)
                  Row(children: [
                    for (final d in cells.sublist(r, r + 7))
                      Expanded(
                        child: d == null
                            ? const SizedBox(height: 52)
                            : _CalCell(
                                day: d,
                                today: today,
                                selected: d['key'] == _selected,
                                onTap: () => setState(() =>
                                    _selected = _selected == d['key'] ? null : '${d['key']}'),
                              ),
                      ),
                  ]),
              ]),
            ),
            const SizedBox(height: 8),
            const DayMarkLegend(),
            const SizedBox(height: 8),
            Text(
                key: const ValueKey('cal-summary'),
                sum.planned == 0
                    ? '이 달은 계획한 날이 없습니다'
                    : '이 달 계획 ${sum.planned}일 중 ${sum.kept}일 지킴'
                        '${sum.missed > 0 ? ' · 놓친 날 ${sum.missed}일' : ''}',
                style: hint),
            if (canPrev || canNext)
              Wrap(spacing: 4, children: [
                if (canPrev)
                  TextButton.icon(
                    key: const ValueKey('cal-first'),
                    onPressed: () => _go(first),
                    icon: const Icon(LucideIcons.chevronsLeft, size: 16),
                    label: Text('처음 기록 (${calLabel(first)})'),
                  ),
                if (canNext)
                  TextButton.icon(
                    key: const ValueKey('cal-this-month'),
                    onPressed: () => _go(last),
                    icon: const Icon(LucideIcons.chevronsRight, size: 16),
                    label: const Text('이번 달로'),
                  ),
              ]),
          ]),
        ),
        const SizedBox(height: 10),
        if (_selected == null)
          Text('날짜를 누르면 그 날 한 것이 보입니다', textAlign: TextAlign.center, style: hint)
        else
          _dayDetail(context, app, _selected!, today),
      ],
    );
  }

  Widget _dayDetail(BuildContext context, AppState app, String key, String today) {
    final e = app.store.scheduleDay(key);
    final log = e['log'];
    if (log is Map && (log['gym'] is Map || log['cardio'] is Map)) return widget.detail(key);
    final t = Theme.of(context);
    final plan = (e['plan'] as List);
    final done = (e['done'] as Map);
    final d = DateTime.parse('${key}T00:00:00');
    final title = '${d.month}/${d.day} (${core.kDow[d.weekday - 1]})';
    final lines = [
      for (final ty in core.kSchedTypes)
        if (plan.contains(ty['id']))
          '${ty['label']} — ${core.jsTruthy(done[ty['id']]) ? '했음' : key.compareTo(today) < 0 ? '못 함' : '할 예정'}',
    ];
    return MbCard(
      key: const ValueKey('cal-day'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (lines.isEmpty)
          Text('쉬는 날 — 계획도 기록도 없습니다', style: t.textTheme.bodySmall?.copyWith(color: t.hintColor))
        else ...[
          for (final l in lines) Text(l, style: t.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text('체크만 하고 종목 · 세트는 안 적은 날입니다',
              style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        ],
      ]),
    );
  }
}

/// 한 날 칸 — 홈 「이번 주 운동」 의 요일 칸과 같은 그림(숫자 · DayMark · 헬스/유산소 점).
class _CalCell extends StatelessWidget {
  const _CalCell({required this.day, required this.today, required this.selected, required this.onTap});
  final Map<String, Object?> day;
  final String today;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final key = '${day['key']}';
    final isToday = key == today;
    final plan = (day['plan'] as List);
    final done = (day['done'] as Map);
    return InkWell(
      key: ValueKey('cal-day-$key'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 52,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isToday ? c.accentSub : null,
          border: selected ? Border.all(color: t.colorScheme.primary, width: 1.5) : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${day['dayNum']}',
              style: t.textTheme.labelSmall?.copyWith(
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
          const SizedBox(height: 2),
          DayMark(dayMarkState(day, today: today), size: 18),
          const SizedBox(height: 2),
          SizedBox(
            height: 5,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final ty in core.kSchedTypes)
                if (plan.contains(ty['id']))
                  Container(
                    width: 4, height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: core.jsTruthy(done[ty['id']])
                          ? (ty['id'] == 'gym' ? c.muscle : c.ok)
                          : t.dividerColor,
                    ),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }
}
