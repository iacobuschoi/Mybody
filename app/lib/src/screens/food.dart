/* =============================================================================
 * food.dart — 식단 (P18 식단 기록 · P19 음식 고르기)
 *
 * 달성률(P21)은 플랜 탭으로 갔습니다 — screens/adherence.dart.
 *
 * 원본 웹 화면을 카드 단위로 그대로 따릅니다. 이 화면은 **먹기 직전에**
 * 보는 화면이라, 퍼센트가 아니라 "남은 양" 으로 말합니다 — "단백질 40g
 * 남음" 은 닭가슴살 한 팩으로 바로 이어지지만 "60% 달성" 은 목표를
 * 기억해 곱셈을 해야 행동이 됩니다.
 * ========================================================================== */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../briefing.dart' show mealNow;
import '../scope.dart';
import '../nudge.dart' show mealFromReminder;
import '../ui/fmt.dart';
import '../ui/widgets.dart';

const _meals = ['아침', '점심', '저녁', '간식'];

/// 지금 시각으로 다음 끼니를 짐작합니다 (원본 guessMeal).
///
/// 끼니 알림을 누르고 들어왔으면 3시간 동안은 그 끼니입니다([mealFromReminder]).
/// 그 밖에는 홈 브리핑의 [mealNow] 와 **같은 경계**(11시 전 아침 · 15시 전 점심 ·
/// 17시 전 간식 · 그 뒤는 저녁)입니다. 경계가 따로 있으면 브리핑이 밤 9시 반에
/// 「저녁 기록」 을 누르라 하고 식단 탭은 간식으로 열려서, 적은 저녁이 간식으로
/// 저장됐습니다. 아침이 11시까지인 이유도 같습니다 — 10시 「아침 메뉴를
/// 기록해주세요!」 를 보고 적은 것이 점심이 되고 13시 점심 알림까지 빠졌습니다.
String guessMeal([DateTime? now]) {
  final fromReminder = mealFromReminder(now);
  if (fromReminder != null) return fromReminder;
  return mealNow((now ?? DateTime.now()).hour);
}

Map<String, Object?>? _targetOf(BuildContext context) {
  final plan = Scope.of(context).state['plan'];
  if (plan is! Map) return null;
  final m = plan['macros'];
  return m is Map ? m.cast<String, Object?>() : null;
}

/* --- P18 식단 기록 (일간) ------------------------------------------------- */
class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  String? _date;

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final store = app.store;
    final date = _date ?? store.dayKey();
    final totals = store.dayTotals(date);
    final logs = store.logsForDate(date);
    final target = _targetOf(context);
    final t = Theme.of(context);
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);

    final remainP = target == null
        ? 0.0
        : math.max(0.0, core.jsToNumber(target['proteinG']) - core.jsToNumber(totals['p']));
    final remainK = target == null
        ? 0.0
        : core.jsToNumber(target['intakeKcal']) - core.jsToNumber(totals['kcal']);
    final remainC = target == null
        ? 0.0
        : core.jsToNumber(target['carbG']) - core.jsToNumber(totals['c']);
    final remainF = target == null
        ? 0.0
        : core.jsToNumber(target['fatG']) - core.jsToNumber(totals['f']);

    return ListView(padding: const EdgeInsets.all(16), children: [
      _DayStrip(date: date, onPick: (d) => setState(() => _date = d)),

      if (target == null) ...[
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('아직 하루 목표가 없습니다'),
            Text('플랜이 하루 칼로리·단백질 목표를 정합니다', style: hint),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => widget.go('goal'), child: const Text('플랜 만들기')),
          ]),
        ),
        _TotalsCard(totals: totals),
      ] else ...[
        _TodayCard(totals: totals, target: target),
        /* 남은 양을 알려주는 것과 그걸 음식으로 번역해 주는 것은 다른 일입니다.
           "단백질 40g 남음" 을 보고 닭가슴살 한 팩 반을 떠올리려면 매번 계산이
           필요하고, 하루 세 번 그 계산을 하다가 사람들이 포기합니다.
           작은 버튼 하나 — 누르면 추천이 튀어나옵니다. 화면에 늘 펼쳐 두면
           끼니 카드가 아래로 밀립니다. */
        if (remainP > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => _openSuggest(context, date, remainP, remainK, remainC, remainF),
                icon: const Icon(LucideIcons.wand2, size: 18),
                label: Text('뭘 먹을까 · 단백질 ${n0(remainP)}g 남음'),
              ),
            ),
          ),
      ],

      /* 주로 먹는 것이 위에 — 식단은 대개 같은 것의 반복이라, 늘 먹는 것
         여덟 개면 하루의 대부분이 한 번 누르기로 끝납니다. */
      _FrequentChips(date: date, onAdded: _refresh),
      if (logs.isEmpty) _YesterdayCard(date: date, onCopied: _refresh),

      for (final meal in _meals)
        _MealCard(meal: meal, date: date, logs: logs, onChanged: _refresh),

      if (logs.isEmpty)
        const Note(text: '한 끼만 적어도 됩니다 — 안 적은 날은 평균에서 뺍니다'),
    ]);
  }

  Future<void> _openSuggest(BuildContext context, String date, double remainP, double remainK,
      double remainC, double remainF) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _SuggestCard(
              date: date, remainP: remainP, remainK: remainK, remainC: remainC, remainF: remainF,
              onAdded: () {
                Navigator.of(ctx).pop();
                _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* 목표가 없을 때: 먹은 것 합계만. */
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});
  final Map<String, Object?> totals;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('오늘 먹은 것',
            trailing: Text(
                core.jsTruthy(totals['logged']) ? '${n0(totals['entries'])}건' : '기록 없음',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        Row(children: [
          Expanded(child: Stat(label: '칼로리', value: n0(totals['kcal']), unit: 'kcal')),
          Expanded(child: Stat(label: '단백질', value: n1(totals['p']), unit: 'g', color: c.muscle)),
          Expanded(child: Stat(label: '탄수', value: n1(totals['c']), unit: 'g')),
          Expanded(child: Stat(label: '지방', value: n1(totals['f']), unit: 'g', color: c.fat)),
        ]),
      ]),
    );
  }
}

/* --- C02 오늘 남은 양 (핵심) --------------------------------------------- */
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.totals, required this.target});
  final Map<String, Object?> totals, target;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final p = core.jsToNumber(totals['p']);
    final kcal = core.jsToNumber(totals['kcal']);
    final tp = core.jsToNumber(target['proteinG']);
    final tk = core.jsToNumber(target['intakeKcal']);
    final remainP = math.max(0.0, tp - p);
    final lo = core.jsRound(tk * 0.9).toDouble(), hi = core.jsRound(tk * 1.1).toDouble();
    final logged = core.jsTruthy(totals['logged']);
    final inBand = kcal >= lo && kcal <= hi;
    final nudge = core.dietNudge(
        {'logged': totals['logged'], 'kcal': totals['kcal'], 'p': totals['p']}, target);
    final small = t.textTheme.labelSmall?.copyWith(color: t.hintColor);
    final big = t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.1);

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('오늘',
            trailing: Pill(logged ? '${n0(totals['entries'])}건 기록' : '기록 없음',
                tone: logged && inBand ? Tone.ok : Tone.none)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('단백질 남음', style: small),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(remainP > 0 ? n0(remainP) : '완료',
                    style: big?.copyWith(color: remainP > 0 ? c.muscle : c.ok)),
                if (remainP > 0) Text(' g', style: small),
              ]),
              Text('${n0(p)} / ${n0(tp)}g', style: small),
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('칼로리', style: small),
              Text(n0(kcal),
                  style: big?.copyWith(color: inBand ? c.ok : (kcal > hi ? c.warn : null))),
              Text('목표 범위 ${n0(lo)}~${n0(hi)}', style: small),
            ]),
          ),
        ]),
        _BandBar(value: kcal, target: tk, lo: lo, hi: hi),
        _MacroRow(label: '단백질', got: p, want: tp, color: c.muscle),
        _MacroRow(label: '탄수화물', got: core.jsToNumber(totals['c']),
            want: core.jsToNumber(target['carbG']), color: t.colorScheme.primary),
        _MacroRow(label: '지방', got: core.jsToNumber(totals['f']),
            want: core.jsToNumber(target['fatG']), color: c.fat),
        if (nudge != null) ...[
          const SizedBox(height: 6),
          Note(
            tone: nudge['tone'] == 'ok' ? Tone.ok : (nudge['tone'] == 'warn' ? Tone.warn : Tone.none),
            title: '${nudge['text']}',
            text: ' ${nudge['detail'] ?? ''}',
          ),
        ],
      ]),
    );
  }
}

/// 칼로리 막대 — 목표 범위(90~110%)를 띠로 깔고 그 위에 먹은 양.
class _BandBar extends StatelessWidget {
  const _BandBar({required this.value, required this.target, required this.lo, required this.hi});
  final double value, target, lo, hi;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final max = [hi * 1.15, value * 1.05, target * 1.2].reduce(math.max);
    double pct(double v) => max > 0 ? (v / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (_, box) {
          final w = box.maxWidth;
          return SizedBox(
            height: 10,
            child: Stack(children: [
              Container(
                  decoration: BoxDecoration(
                      color: t.dividerColor, borderRadius: BorderRadius.circular(999))),
              Positioned(
                left: w * pct(lo), width: w * (pct(hi) - pct(lo)), top: 0, bottom: 0,
                child: Container(color: c.ok.withValues(alpha: 0.22)),
              ),
              Container(
                width: w * pct(value),
                decoration: BoxDecoration(
                    color: t.colorScheme.primary.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(999)),
              ),
            ]),
          );
        }),
        const SizedBox(height: 3),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, fontSize: 10.5)),
          Text('목표 범위 ${n0(lo)}~${n0(hi)} kcal',
              style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, fontSize: 10.5)),
          Text(n0(max), style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, fontSize: 10.5)),
        ]),
      ]),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.label, required this.got, required this.want, required this.color});
  final String label;
  final double got, want;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pct = want > 0 ? (got / want).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: t.hintColor)),
          Text('${n0(got)} / ${n0(want)}g', style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
              value: pct, minHeight: 6, backgroundColor: t.dividerColor,
              valueColor: AlwaysStoppedAnimation(color)),
        ),
      ]),
    );
  }
}

/* --- C10 뭘 먹을까 — 남은 단백질을 실제 음식으로 번역 -------------------- */
class _SuggestCard extends StatefulWidget {
  const _SuggestCard({required this.date, required this.remainP, required this.remainK,
      required this.remainC, required this.remainF, required this.onAdded});
  final String date;
  final double remainP, remainK, remainC, remainF;
  final VoidCallback onAdded;

  @override
  State<_SuggestCard> createState() => _SuggestCardState();
}

class _SuggestCardState extends State<_SuggestCard> {
  static const _modes = [('out', '사먹기'), ('home', '집밥'), ('snack', '간식')];
  late String _mode;
  late final String _nextMeal = guessMeal();

  @override
  void initState() {
    super.initState();
    // 점심·저녁은 대개 밖에서 사먹습니다. 그 시간대면 사먹기를 먼저 보여줍니다.
    _mode = (_nextMeal == '점심' || _nextMeal == '저녁') ? 'out' : (_nextMeal == '간식' ? 'snack' : 'home');
  }

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final logs = app.store.logsForDate(widget.date);
    // 오늘 이미 먹은 건 또 권하지 않습니다 — 같은 걸 세 번 권하면 추천이 아닙니다.
    final eaten = <String>{
      for (final l in logs) for (final it in ((l['items'] as List?) ?? const [])) '${(it as Map)['name']}',
    };
    // 오늘 아직 안 먹은 끼니 수. 아침에 하루치를 한 끼에 몰지 않기 위해서입니다.
    final loggedMeals = {for (final l in logs) '${l['meal']}'};
    final mealsLeft = ['아침', '점심', '저녁'].where((m) => !loggedMeals.contains(m)).length;
    /* 오늘 먹은 것과 먹어야 하는 탄단지에 맞춥니다 — 남은 탄수·지방을
       넘기는 조합은 뒤로 갑니다. 날짜가 씨앗이라 같은 날은 같은 답,
       다음 날은 다른 메뉴가 첫 줄에 섭니다(안 질리게). */
    final opts = <String, Object?>{
      'remainP': widget.remainP, 'remainKcal': widget.remainK,
      'remainC': widget.remainC, 'remainF': widget.remainF,
      'avoid': eaten.toList(),
      'mealsLeft': math.max(1, mealsLeft), 'limit': 3,
      'seed': widget.date,
    };
    final res = switch (_mode) {
      'out' => core.suggestEatOut(opts),
      'snack' => core.suggestSnack(opts),
      _ => core.suggestMeal(opts),
    };
    final sum = core.suggestSummaryText(res);
    final options = ((res['options'] as List?) ?? const [])
        .map((o) => (o as Map).cast<String, Object?>())
        .take(3)
        .toList();
    final tone = sum['tone'] == 'ok' ? Tone.ok : (sum['tone'] == 'warn' ? Tone.warn : Tone.none);
    /* 끼니는 깔끔한 한 상으로, 모자란 단백질은 간식으로 — 코어가 그 몫을 한 줄로
       줍니다. 누르면 간식 추천으로 넘어갑니다(간식 모드에서는 코어가 안 줍니다). */
    final snackHint = _mode == 'snack' ? '' : '${res['snackHint'] ?? ''}';
    final hintStyle = t.textTheme.labelSmall?.copyWith(color: t.hintColor);

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 남은 kcal 를 같이 보여야 "658kcal" 이 많은지 적은지 읽힙니다. 글자를 키우면(1.3배)
        // 360px 에서 제목을 밀어내니 한 줄 · 줄임표로 — 제목이 두 줄로 접히면 안 됩니다.
        SectionTitle('뭘 먹을까',
            trailing: Flexible(
              child: Text(
                  '남은 ${n0(math.max(0.0, widget.remainK))}kcal · 단백질 ${n0(widget.remainP)}g',
                  key: const Key('suggest-remain'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: hintStyle),
            )),
        Wrap(spacing: 6, children: [
          for (final m in _modes)
            ChoiceChip(
              label: Text(m.$2),
              selected: _mode == m.$1,
              onSelected: (_) => setState(() => _mode = m.$1),
            ),
        ]),
        const SizedBox(height: 10),
        if (options.isEmpty)
          Note(tone: tone, title: '${sum['text']}', text: ' ${sum['detail'] ?? ''}')
        else ...[
          if (core.jsTruthy(sum['tone']))
            Note(tone: tone, title: '${sum['text']}', text: ' ${sum['detail'] ?? ''}'),
          for (var i = 0; i < options.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  border: i == 0 ? null : Border(top: BorderSide(color: t.dividerColor))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  ((options[i]['items'] as List?) ?? const [])
                      .map((x) => core.suggestItemText((x as Map).cast<String, Object?>()))
                      .join(' + '),
                  style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${n0(options[i]['totalKcal'])}kcal · 단백질 ${n0(options[i]['totalP'])}g'
                  '${core.jsTruthy(options[i]['shape']) ? ' · ${options[i]['shape']}' : ''}',
                  style: hintStyle,
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () {
                    final meal = _mode == 'snack' ? '간식' : _nextMeal;
                    app.store.addFoodLog({
                      'date': widget.date, 'meal': meal, 'source': 'suggest',
                      'items': [
                        for (final x in ((options[i]['items'] as List?) ?? const []))
                          {
                            'name': (x as Map)['name'], 'g': x['g'], 'kcal': x['kcal'],
                            'p': x['p'], 'c': x['c'], 'f': x['f'],
                          },
                      ],
                    });
                    toast(context, '$meal에 담았습니다');
                    widget.onAdded();
                  },
                  child: const Text('기록에 담기'),
                ),
              ]),
            ),
        ],
        if (snackHint.isNotEmpty)
          InkWell(
            key: const Key('suggest-snack-hint'),
            onTap: () => setState(() => _mode = 'snack'),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(LucideIcons.cookie, size: 14, color: t.hintColor),
                const SizedBox(width: 6),
                Expanded(child: Text(snackHint, style: hintStyle)),
                Icon(LucideIcons.chevronRight, size: 14, color: t.hintColor),
              ]),
            ),
          ),
      ]),
    );
  }
}

/* --- C04 끼니별 ------------------------------------------------------------ */
class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.date, required this.logs, required this.onChanged});
  final String meal, date;
  final List<Map<String, Object?>> logs;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final mine = logs.where((l) => l['meal'] == meal).toList();
    final rows = <({Map<String, Object?> log, int index, Map<String, Object?> it})>[];
    for (final l in mine) {
      final items = (l['items'] as List?) ?? const [];
      for (var i = 0; i < items.length; i++) {
        rows.add((log: l, index: i, it: (items[i] as Map).cast<String, Object?>()));
      }
    }
    final sum = core.Store.sumItems([for (final r in rows) r.it]);
    final last = app.store.lastMealLike(meal, date);

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(meal,
            trailing: Text(
                rows.isEmpty ? '비어 있음' : '${n0(sum['kcal'])}kcal · 단백질 ${n0(sum['p'])}g',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        for (final r in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.dividerColor))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${r.it['name']}'
                    '${core.jsToNumber(r.it['mult'] ?? 1) != 1 ? ' × ${core.jsNumToString(core.jsToNumber(r.it['mult']))}' : ''}',
                    style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${n0(r.it['g'])}g · ${n0(r.it['kcal'])}kcal · 단백질 ${n1(r.it['p'])}g · '
                    '탄수 ${n1(r.it['c'])}g · 지방 ${n1(r.it['f'])}g'
                    '${r.it['conf'] == 'low' ? ' · 편차 큼' : ''}',
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor),
                  ),
                ]),
              ),
              IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                tooltip: '항목 삭제',
                onPressed: () {
                  final items = (r.log['items'] as List);
                  if (r.index < items.length) items.removeAt(r.index);
                  if (items.isEmpty) {
                    app.store.removeFoodLog(r.log['id']);
                  } else {
                    app.store.save();
                  }
                  onChanged();
                },
                icon: const Icon(LucideIcons.x),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FoodSearchScreen(date: date, meal: meal)));
              onChanged();
            },
            child: const Text('+ 추가'),
          ),
          if (last != null)
            TextButton(
              onPressed: () {
                app.store.copyMeal(last, date, meal);
                toast(context, '${dateK(last['date'])} $meal을 그대로 가져왔습니다');
                onChanged();
              },
              child: const Text('지난번과 같이'),
            ),
        ]),
      ]),
    );
  }
}

/// 자주 먹은 순서 — 횟수, 같으면 최근 것. 이름이 같으면 한 번만.
List<Map<String, Object?>> frequentFoods(List<Object?> logs, [int limit = 8]) {
  final count = <String, int>{};
  final last = <String, int>{};
  final item = <String, Map<String, Object?>>{};
  var i = 0;
  for (final l in logs) {
    for (final it in (((l as Map)['items'] as List?) ?? const [])) {
      final m = (it as Map).cast<String, Object?>();
      final name = '${m['name']}';
      count[name] = (count[name] ?? 0) + 1;
      last[name] = i++;
      item[name] = m;
    }
  }
  final names = count.keys.toList()
    ..sort((a, b) {
      final c = count[b]! - count[a]!;
      return c != 0 ? c : last[b]! - last[a]!;
    });
  return [for (final n in names.take(limit)) item[n]!];
}

/* --- 주로 먹는 것 — 누르면 바로 추가 --------------------------------------- */
class _FrequentChips extends StatelessWidget {
  const _FrequentChips({required this.date, required this.onAdded});
  final String date;
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final recents = frequentFoods((app.state['foodLogs'] as List?) ?? const []);
    if (recents.isEmpty) return const SizedBox.shrink();
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('주로 먹는 것',
            trailing: Text('누르면 지금 끼니에 바로 추가', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final it in recents)
            ActionChip(
              label: Text('${it['name']}'),
              onPressed: () {
                app.store.addFoodLog({
                  'date': date, 'meal': guessMeal(),
                  'items': [Map<String, Object?>.of(it)], 'source': 'recent',
                });
                toast(context, '${it['name']} 추가');
                onAdded();
              },
            ),
        ]),
      ]),
    );
  }
}

/* --- C09 어제와 동일 ------------------------------------------------------- */
class _YesterdayCard extends StatelessWidget {
  const _YesterdayCard({required this.date, required this.onCopied});
  final String date;
  final VoidCallback onCopied;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final yest = app.store.yesterdayLogs(date);
    if (yest.isEmpty) return const SizedBox.shrink();
    final tot = core.Store.sumItems([for (final l in yest) ...((l['items'] as List?) ?? const [])]);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('어제와 같이 드셨나요?',
            trailing: Text('${n0(tot['kcal'])}kcal · 단백질 ${n0(tot['p'])}g',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
        /* "같은 값으로 재사용하면 기록 편향이…" 설명은 뺐습니다 — 제목과 버튼이 이미
           할 일을 다 말합니다. */
        OutlinedButton(
          onPressed: () {
            for (final l in yest) {
              app.store.copyMeal(l, date, l['meal']);
            }
            toast(context, '어제 기록 ${yest.length}건을 가져왔습니다');
            onCopied();
          },
          child: const Text('어제 것 그대로 가져오기'),
        ),
      ]),
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.date, required this.onPick});
  final String date;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final today = app.store.dayKey();
    final d = DateTime.tryParse('${today}T00:00:00') ?? DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) app.store.dayKey(DateTime(d.year, d.month, d.day - i))];
    final t = Theme.of(context);
    final c = mb(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        for (final k in days)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onPick(k),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: k == date ? c.accentSub : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(children: [
                  Text(_dowOf(k),
                      style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                  Text(k.substring(8), style: t.textTheme.bodySmall?.copyWith(
                      fontWeight: k == date ? FontWeight.w800 : FontWeight.w400)),
                  const SizedBox(height: 3),
                  Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: app.store.logsForDate(k).isNotEmpty
                          ? t.colorScheme.primary
                          : Colors.transparent,
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 'YYYY-MM-DD' → '월'. 못 읽으면 빈 칸 — 없는 요일을 지어내지 않습니다.
String _dowOf(String key) {
  final d = DateTime.tryParse('${key}T00:00:00');
  return d == null ? '' : core.kDow[(d.weekday - 1) % 7];
}

/* --- P19 음식 고르기 ------------------------------------------------------- */
class FoodSearchScreen extends StatefulWidget {
  const FoodSearchScreen({super.key, required this.date, this.meal});
  final String date;
  final String? meal;

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final _q = TextEditingController();
  late String _meal = widget.meal ?? guessMeal();
  String? _cat;
  final _picked = <Map<String, Object?>>[];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Map<String, Object?>> _hits() {
    final q = _q.text.trim();
    var list = q.isNotEmpty
        ? core.foodSearch(q, 40)
        : (_cat != null
            ? core.foodByCat(_cat)
            : core.kFoodDb.take(24).map((f) => (f as Map).cast<String, Object?>()).toList());
    if (_cat != null && q.isNotEmpty) list = list.where((x) => x['cat'] == _cat).toList();
    return list;
  }

  /* 정확히 겹치는 게 없을 때의 대안 — 오타·초성·한/영 자판까지 봐서 최대 8개.
     코어는 이름과 사유만 주므로 표의 행으로 되돌립니다. 분류 필터는 검색
     결과와 똑같이 겁니다 — 필터를 골라 놓고 다른 분류가 튀어나오면 필터가
     거짓말이 됩니다. */
  List<({Map<String, Object?> food, String why})> _similar(String q) {
    final out = <({Map<String, Object?> food, String why})>[];
    for (final r in core.foodSimilar(q, 8)) {
      final f = core.foodByName(r['name']);
      if (f == null) continue;
      if (_cat != null && f['cat'] != _cat) continue;
      out.add((food: f, why: '${r['why']}'));
    }
    return out;
  }

  /// 왜 이 행이 나왔는지 — 짧게. 부분 일치는 표시 없음(검색 결과처럼 보이는
  /// 게 맞고, 굳이 이유를 달면 오히려 의심스러워 보입니다).
  static String? _whyLabel(String why) => switch (why) {
        'typo' => '비슷한 이름',
        'chosung' => '초성',
        'qwerty' => '한/영 자판',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final q = _q.text.trim();
    final hits = _hits();
    /* 검색어가 있는데 결과가 0개일 때만. 검색어는 절대 고치지 않습니다 —
       "당신이 친 것과 다르다" 는 제목이 말하고, 고르는 건 사람이 합니다. */
    final similar = q.isNotEmpty && hits.isEmpty
        ? _similar(q)
        : const <({Map<String, Object?> food, String why})>[];
    final favs = ((app.state['foodFavorites'] as List?) ?? const []).map((x) => '$x').toList();
    final recents = q.isEmpty && _cat == null ? app.store.recentFoods(6) : const <Map<String, Object?>>[];
    final pickedSum = core.Store.sumItems(_picked);

    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(s,
              style: t.textTheme.labelSmall?.copyWith(
                  color: t.hintColor, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text('$_meal에 추가'),
        /* 목록이 400개를 넘으면서 맨 아래의 「직접 입력」 은 멀어졌습니다.
           위에도 둡니다 — 없는 음식을 적으려는 사람이 스크롤부터 하면 안 됩니다. */
        actions: [
          TextButton(onPressed: _custom, child: const Text('직접 입력')),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        /* 위: 검색 → 끼니 → 분류. 한 줄씩, 칩은 가로로 흘려서 세로 공간을 안 먹습니다. */
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '음식 이름 — 닭가슴살, 찌개, 김밥…',
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () => setState(_q.clear),
                      ),
                filled: true,
                fillColor: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final m in _meals) ButtonSegment(value: m, label: Text(m))],
              selected: {_meal},
              onSelectionChanged: (s) => setState(() => _meal = s.first),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final c in [null, ...core.kFoodCats])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(c ?? '전체'),
                      selected: _cat == c,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _cat = c),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
            if (favs.isNotEmpty && q.isEmpty) ...[
              label('즐겨찾기'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final n in favs)
                  ActionChip(
                    avatar: Icon(Icons.star, size: 16, color: t.colorScheme.primary),
                    label: Text(n),
                    onPressed: () {
                      final f = core.foodByName(n);
                      if (f != null) _pick(f);
                    },
                  ),
              ]),
            ],
            if (recents.isNotEmpty) ...[
              /* 최근에 먹은 것이 먼저입니다 — 같은 음식을 같은 추정치로
                 다시 쓰면 주마다 편향이 흔들리지 않습니다. */
              label('최근에 먹은 것'),
              for (final f in recents) _FoodRow(food: f, onTap: () => _pick(f)),
            ],
            /* 제목에 검색어를 그대로 인용합니다 — 「'김치찌게' 와 비슷한 이름」.
               행은 검색 결과와 같은 모양이라 그대로 눌러 담습니다. */
            label(q.isNotEmpty
                ? (similar.isNotEmpty ? "'$q' 와 비슷한 이름" : '검색 결과')
                : (_cat ?? '목록')),
            if (similar.isNotEmpty) ...[
              for (final s in similar)
                _FoodRow(food: s.food, hint: _whyLabel(s.why), onTap: () => _pick(s.food)),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _custom,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('찾는 게 아니면 · 직접 입력'),
                ),
              ),
            ] else if (hits.isEmpty)
              EmptyState(
                title: '찾는 음식이 없습니다',
                detail: '비슷한 걸 고르고 양을 조절하세요',
                action: OutlinedButton(onPressed: _custom, child: const Text('직접 입력')),
              )
            else
              for (final f in hits) _FoodRow(food: f, onTap: () => _pick(f)),
            if (hits.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _custom,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('목록에 없어요 · 직접 입력'),
                ),
              ),
            ],
          ]),
        ),
        /* 담은 것 — 보이게. 개수만 보이면 뭘 담았는지 모릅니다. */
        if (_picked.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: t.colorScheme.surface,
              border: Border(top: BorderSide(color: t.dividerColor)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (var i = 0; i < _picked.length; i++)
                      InputChip(
                        label: Text('${_picked[i]['name']} · ${n0(_picked[i]['kcal'])}kcal'),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => setState(() => _picked.removeAt(i)),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () {
                      app.store.addFoodLog({
                        'date': widget.date, 'meal': _meal, 'items': _picked, 'source': 'manual',
                      });
                      if (!app.store.saved()) {
                        toast(context, '기기에 저장하지 못했습니다');
                        return;
                      }
                      Navigator.of(context).pop();
                    },
                    child: Text('$_meal에 ${_picked.length}개 저장 · ${n0(pickedSum['kcal'])}kcal · 단백질 ${n0(pickedSum['p'])}g'),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  /* 직접 입력 — 목록에 없는 것. 원본 customFood 모달과 같은 칸. */
  Future<void> _custom() async {
    final name = TextEditingController();
    final kcal = TextEditingController();
    final p = TextEditingController();
    final c = TextEditingController();
    final f = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('직접 입력'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '이름', hintText: '예: 회사 구내식당 점심')),
            TextField(controller: kcal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '칼로리 (kcal)')),
            TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '단백질 (g)')),
            TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '탄수화물 (g)')),
            TextField(controller: f, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '지방 (g)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('추가')),
        ],
      ),
    );
    final n = name.text.trim();
    if (ok != true || n.isEmpty) return;
    double num(TextEditingController x) => double.tryParse(x.text.trim()) ?? 0;
    setState(() => _picked.add({
          'name': n, 'unit': '직접', 'mult': 1, 'g': 0,
          'kcal': core.jsRound(num(kcal)), 'p': num(p), 'c': num(c), 'f': num(f),
          'conf': 'mid', 'custom': true,
        }));
  }

  /* 양 고르기 — 시트 하나. 이름 · 기준 · 편차 안내 · 배수 버튼 · 즐겨찾기. */
  Future<void> _pick(Map<String, Object?> food) async {
    final app = Scope.of(context);
    final mult = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final t = Theme.of(ctx);
        final fav = ((app.state['foodFavorites'] as List?) ?? const []).contains(food['name']);
        final note = '${(core.kConfLabel['${food['conf']}'] as Map?)?['note'] ?? ''}';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('${food['name']}',
                        style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: fav ? '즐겨찾기 해제' : '즐겨찾기',
                    onPressed: () {
                      app.store.toggleFavorite(food['name']);
                      setSheet(() {});
                    },
                    icon: Icon(fav ? Icons.star : Icons.star_outline,
                        color: fav ? t.colorScheme.primary : t.hintColor),
                  ),
                ]),
                Text(
                    '${food['unit']} ${n0(food['g'])}g · ${n0(food['kcal'])}kcal · '
                    '단백질 ${n1(food['p'])}g · 탄수 ${n1(food['c'])}g · 지방 ${n1(food['f'])}g',
                    style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  /* 편차가 큰 음식은 그렇다고 말합니다 — 숫자를 얼마나 믿어도
                     되는지가 숫자만큼 중요합니다. */
                  Text(note, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.4)),
                ],
                const SizedBox(height: 16),
                Text('얼마나?', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p0 in core.kPortions)
                    Builder(builder: (_) {
                      final p = (p0 as Map).cast<String, Object?>();
                      final m = core.jsToNumber(p['mult']);
                      return FilledButton.tonal(
                        onPressed: () => Navigator.pop(ctx, m),
                        child: Text('${p['label']}  ·  ${n0(core.jsToNumber(food['kcal']) * m)}kcal'),
                      );
                    }),
                ]),
              ]),
          ),
        );
      }),
    );
    if (mult == null) return;
    setState(() => _picked.add(core.foodScaled(food, mult)));
  }
}

/// 목록 한 줄 — 이름과 성분은 왼쪽, 칼로리는 오른쪽에 크게. 편차가 큰 것만 표시.
/// [hint] 는 "비슷한 이름" 구간에서 왜 나왔는지(초성·한/영 자판…) — 아주 작게.
class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.food, required this.onTap, this.hint});
  final Map<String, Object?> food;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final low = '${food['conf']}' == 'low';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.dividerColor))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text('${food['name']}',
                      style: t.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                ),
                if (low) ...[const SizedBox(width: 6), const Pill('편차 큼', tone: Tone.warn)],
                if (hint != null) ...[
                  const SizedBox(width: 8),
                  Text(hint!, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                ],
              ]),
              const SizedBox(height: 2),
              /* 무게와 영양소를 말로 구분합니다. "1개 (50g) · 72kcal · P6.3" 이면
                 50g 이 단백질처럼 읽힙니다. */
              Text(
                  '${food['unit'] ?? ''} ${n0(food['g'])}g · 단백질 ${n1(food['p'])} · '
                  '탄수 ${n1(food['c'])} · 지방 ${n1(food['f'])}',
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(n0(food['kcal']),
                style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: c.weight)),
            Text('kcal', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ]),
          const SizedBox(width: 4),
          Icon(LucideIcons.plus, size: 18, color: t.hintColor),
        ]),
      ),
    );
  }
}
