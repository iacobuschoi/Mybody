/* =============================================================================
 * food.dart — P18 식단 · P19 음식 검색 · P21 음식 상세
 *
 * **미기록일을 0으로 치환하지 않습니다.** 0 으로 채우면 주 평균이 폭락하고,
 * 엔진은 "이 사람 대사가 예상보다 낮다" 고 판단해 칼로리를 더 깎습니다.
 * 실제로는 목표치를 먹고 있었는데도요. 그래서 안 적은 날은 분모에서 빼고,
 * 뺐다는 사실을 화면에 씁니다.
 *
 * 그리고 오늘 상태는 **명령이 아니라 보고**로 씁니다. "그만 드세요" 는
 * 앱이 내리는 지시이고, "오늘 목표치를 다 채웠습니다" 는 정보입니다.
 * 정보는 결정권을 사람에게 남깁니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';

class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, required this.go});
  final void Function(String route, [Object? arg]) go;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  String? _date;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final date = _date ?? app.store.dayKey();
    final totals = app.store.dayTotals(date);
    final logs = app.store.logsForDate(date);
    final plan = app.state['plan'] == null
        ? null
        : (app.state['plan'] as Map).cast<String, Object?>();
    final target = plan?['macros'] == null
        ? null
        : (plan!['macros'] as Map).cast<String, Object?>();
    final t = Theme.of(context);
    final c = mb(context);

    final nudge = target == null
        ? null
        : core.dietNudge({
            'logged': totals['logged'],
            'kcal': totals['kcal'],
            'p': totals['p'],
          }, target);

    return ListView(padding: const EdgeInsets.all(16), children: [
      _DayStrip(
        date: date,
        onPick: (d) => setState(() => _date = d),
      ),
      if (target == null)
        const Note(
          text: '목표를 정하면 하루 섭취·단백질 목표가 생기고, 남은 양에 맞는 '
              '음식을 추천할 수 있습니다. 지금은 기록만 남습니다.',
        ),
      MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('오늘 먹은 것',
              trailing: Text(core.jsTruthy(totals['logged']) ? '${n0(totals['entries'])}건' : '기록 없음',
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor))),
          Row(children: [
            Expanded(child: Stat(label: '칼로리', value: n0(totals['kcal']), unit: 'kcal')),
            Expanded(child: Stat(label: '단백질', value: n1(totals['p']), unit: 'g', color: c.muscle)),
            Expanded(child: Stat(label: '탄수', value: n1(totals['c']), unit: 'g')),
            Expanded(child: Stat(label: '지방', value: n1(totals['f']), unit: 'g', color: c.fat)),
          ]),
          if (target != null) ...[
            const SizedBox(height: 12),
            _Bar(label: '칼로리', got: core.jsToNumber(totals['kcal']),
                want: core.jsToNumber(target['intakeKcal']), color: t.colorScheme.primary),
            const SizedBox(height: 8),
            _Bar(label: '단백질', got: core.jsToNumber(totals['p']),
                want: core.jsToNumber(target['proteinG']), color: c.muscle),
          ],
        ]),
      ),
      if (nudge != null)
        Note(
          tone: nudge['tone'] == 'ok' ? Tone.ok : (nudge['tone'] == 'warn' ? Tone.warn : Tone.none),
          title: '${nudge['text']}',
          text: ' ${nudge['detail']}',
        ),
      /* 기록이 없을 때 "아직 없습니다" 를 두 번 말하지 않습니다 —
         위의 한 줄(dietNudge)이 이미 그 말을 하고, 할 일까지 알려 줍니다.
         목표가 없어서 그 한 줄이 없을 때만 빈 화면을 띄웁니다. */
      if (logs.isEmpty && nudge == null)
        const EmptyState(title: '아직 적은 게 없습니다', detail: '한 끼만 적어도 주 평균이 살아납니다.')
      else
        for (final l in logs) _LogCard(log: l, onRemove: () {
          app.store.removeFoodLog(l['id']);
          setState(() {});
        }),
      FilledButton.icon(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FoodSearchScreen(date: date)));
          setState(() {});
        },
        icon: const Icon(Icons.add),
        label: const Text('음식 추가'),
      ),
      if (target != null) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _suggest(context, totals, target),
          icon: const Icon(Icons.restaurant_menu),
          label: const Text('뭘 먹지? — 남은 양으로 채우기'),
        ),
      ],
    ]);
  }

  Future<void> _suggest(BuildContext context, Map<String, Object?> totals,
      Map<String, Object?> target) async {
    final remainP = core.jsToNumber(target['proteinG']) - core.jsToNumber(totals['p']);
    final remainKcal = core.jsToNumber(target['intakeKcal']) - core.jsToNumber(totals['kcal']);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DefaultTabController(
        length: 3,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (ctx, sc) => Column(children: [
            const TabBar(tabs: [Tab(text: '한 끼'), Tab(text: '사먹기'), Tab(text: '간식')]),
            Expanded(
              child: TabBarView(children: [
                _SuggestList(res: core.suggestMeal(
                    {'remainP': remainP, 'remainKcal': remainKcal, 'mealsLeft': 1})),
                _SuggestList(res: core.suggestEatOut(
                    {'remainP': remainP, 'remainKcal': remainKcal, 'mealsLeft': 1})),
                _SuggestList(res: core.suggestSnack(
                    {'remainP': remainP, 'remainKcal': remainKcal})),
              ]),
            ),
          ]),
        ),
      ),
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

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.got, required this.want, required this.color});
  final String label;
  final double got, want;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pct = want > 0 ? (got / want).clamp(0.0, 1.0) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        Text('${n0(got)} / ${n0(want)}', style: t.textTheme.labelSmall),
      ]),
      const SizedBox(height: 3),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: pct, minHeight: 6,
          backgroundColor: t.dividerColor,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log, required this.onRemove});
  final Map<String, Object?> log;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = ((log['items'] as List?) ?? const []).cast<Map<String, Object?>>();
    final sum = core.Store.sumItems(items);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${log['meal']}', style: t.textTheme.titleSmall)),
          Text('${n0(sum['kcal'])}kcal · 단 ${n1(sum['p'])}g',
              style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ]),
        for (final i in items)
          Text('· ${i['name']} ${core.jsTruthy(i['unit']) ? '(${i['unit']})' : ''} '
              '${n0(i['kcal'])}kcal',
              style: t.textTheme.bodySmall),
      ]),
    );
  }
}

class _SuggestList extends StatelessWidget {
  const _SuggestList({required this.res});
  final Map<String, Object?> res;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final summary = core.suggestSummaryText(res);
    final options = ((res['options'] as List?) ?? const []).cast<Map<String, Object?>>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Note(
        tone: summary['tone'] == 'ok' ? Tone.ok : (summary['tone'] == 'warn' ? Tone.warn : Tone.none),
        title: '${summary['text']}',
        text: ' ${summary['detail'] ?? ''}',
      ),
      for (final o in options)
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${o['main']}', style: t.textTheme.titleSmall)),
              Text('단 ${n1(o['totalP'])}g · ${n0(o['totalKcal'])}kcal',
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ]),
            const SizedBox(height: 6),
            for (final i0 in ((o['items'] as List?) ?? const []))
              Builder(builder: (_) {
                final i = (i0 as Map).cast<String, Object?>();
                return Text('· ${i['name']} ${core.suggestPortionText(i)}',
                    style: t.textTheme.bodySmall);
              }),
          ]),
        ),
    ]);
  }
}

/* --- P19 음식 검색 ---------------------------------------------------------- */

class FoodSearchScreen extends StatefulWidget {
  const FoodSearchScreen({super.key, required this.date});
  final String date;

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final _q = TextEditingController();
  String _meal = '점심';
  final _picked = <Map<String, Object?>>[];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final hits = _q.text.trim().isEmpty
        ? app.store.recentFoods(12)
        : core.foodSearch(_q.text, 30);

    return Scaffold(
      appBar: AppBar(title: const Text('음식 추가')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '음식 이름 (닭가슴살, 김치찌개, 프로틴…)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              for (final m in ['아침', '점심', '저녁', '간식'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(m),
                    selected: _meal == m,
                    onSelected: (_) => setState(() => _meal = m),
                  ),
                ),
            ]),
          ]),
        ),
        if (_q.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              /* 최근에 먹은 것이 먼저입니다 — 같은 음식을 같은 추정치로
                 다시 쓰면 주마다 편향이 흔들리지 않습니다. */
              child: Text('최근에 먹은 것',
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: hits.length,
            itemBuilder: (ctx, i) {
              final f = hits[i];
              return ListTile(
                title: Text('${f['name']}'),
                subtitle: Text(
                    '${f['unit'] ?? ''} · ${n0(f['kcal'])}kcal · 단 ${n1(f['p'])}g',
                    style: t.textTheme.labelSmall),
                trailing: const Icon(Icons.add),
                onTap: () => _pick(f),
              );
            },
          ),
        ),
        if (_picked.isNotEmpty)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
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
                child: Text('${_picked.length}개 저장'),
              ),
            ),
          ),
      ]),
    );
  }

  Future<void> _pick(Map<String, Object?> food) async {
    final mult = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${food['name']}', style: Theme.of(ctx).textTheme.titleMedium),
              Text('${food['unit']} 기준 ${n0(food['kcal'])}kcal',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 4),
              /* 편차가 큰 음식은 그렇다고 말합니다 — 숫자를 얼마나 믿어도
                 되는지가 숫자만큼 중요합니다. */
              Text('${(core.kConfLabel['${food['conf']}'] as Map?)?['note'] ?? ''}',
                  style: Theme.of(ctx).textTheme.labelSmall
                      ?.copyWith(color: Theme.of(ctx).hintColor, height: 1.4)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, children: [
                for (final p0 in core.kPortions)
                  Builder(builder: (_) {
                    final p = (p0 as Map).cast<String, Object?>();
                    return OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, core.jsToNumber(p['mult'])),
                      child: Text('${p['label']}'),
                    );
                  }),
              ]),
            ]),
        ),
      ),
    );
    if (mult == null) return;
    setState(() => _picked.add(core.foodScaled(food, mult)));
  }
}
