/* =============================================================================
 * exercise_picker.dart — 종목 고르기 시트 (두 번 터치)
 *
 * 부위 → 종목. 그게 전부입니다. 시트를 열면 부위가 영역별(상체 · 하체 ·
 * 코어·전신)로 한 화면에 있고, 부위를 누르면(1) 그 부위 종목이 기구별로 나뉘어
 * 나오고, 종목을 누르면(2) 끝입니다. 검색은 보조 — 별칭('이너싸이' ·
 * 'Smith Squat')까지 찾습니다.
 *
 * 기구 섹션은 처음부터 전부 보입니다 — 내 기구가 덤벨뿐이라고 머신을 토글 뒤에
 * 숨겼더니 헬스장에서 머신을 못 찾았습니다(3차 피드백 32). 순서는 내 기구 섹션이
 * 먼저(그 안에서 머신 → 케이블 → 바벨 → 덤벨 → 맨몸 → 밴드 → 케틀벨), 내 기구가
 * 아닌 섹션은 그 뒤에 머리글에 「내 기구 아님」 표를 달고 살짝 흐리게 — 고를 수는
 * 있고, 「내 기구만」 을 켜면 빠집니다. 헬스장 사용자에게 머신은 여전히 첫 섹션이고,
 * 집 사용자는 흐린 머신 · 케이블 · 바벨 스무 줄을 넘기지 않아도 자기 종목이 먼저 옵니다.
 * 맨몸은 언제나 있는 것으로 칩니다(planner 와 같은 규칙). 최근 · 익숙한 종목은
 * 맨 위 한 줄에서 한 번에 고릅니다.
 *
 * 두 가지로 씁니다: pickExercise(하나 → 탭하면 닫힘), pickExercises(여러 개 →
 * 체크하고 「완료」). 위젯(ExercisePicker) 자체는 시트 밖에서도 쓸 수 있습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../ui/widgets.dart';
import '../workout/exercises.dart';

/// 부위 묶음 — 첫 화면의 줄. 순서가 곧 화면 순서입니다.
const List<(String, List<String>)> kPickerAreas = [
  ('상체', ['chest', 'back', 'shoulder', 'arms']),
  ('하체', ['quads', 'hamsGlutes']),
  ('코어·전신', ['core', 'full']),
];

/// 기구 섹션 순서 — 헬스장에서 많이 찾는 것부터.
const List<String> kPickerEquipOrder = [
  'machine', 'cable', 'barbell', 'dumbbell', 'bodyweight', 'band', 'kettlebell',
];

/// 내 기구가 아닌 섹션의 흐림 정도. 읽히되 내 것과 구별되는 선.
const double kPickerDimOpacity = 0.6;

/// 종목 하나 고르기. 탭하면 그 종목으로 닫히고, 그냥 내리면 null.
Future<Exercise?> pickExercise(
  BuildContext context, {
  Set<String>? equip,
  Set<String> exclude = const {},
  List<String> familiar = const [],
  List<String> recent = const [],
  String? title,
}) =>
    _sheet<Exercise>(
      context,
      (ctx) => ExercisePicker(
        equip: equip,
        exclude: exclude,
        familiar: familiar,
        recent: recent,
        title: title,
        onPick: (e) => Navigator.pop(ctx, e),
      ),
    );

/// 여러 개 고르기. 「완료」 를 누르면 고른 순서대로(처음 selected 가 앞), 그냥
/// 내리면 null — "아무것도 안 골랐다" 와 "취소" 를 구분합니다.
Future<List<Exercise>?> pickExercises(
  BuildContext context, {
  Set<String>? equip,
  Set<String> selected = const {},
  List<String> familiar = const [],
  List<String> recent = const [],
  String? title,
}) =>
    _sheet<List<Exercise>>(
      context,
      (ctx) => ExercisePicker(
        equip: equip,
        familiar: familiar,
        recent: recent,
        title: title,
        selected: selected,
        onDone: (xs) => Navigator.pop(ctx, xs),
      ),
    );

/// 화면 90% 높이의 시트. 자판이 올라오면 그만큼 위로 밀립니다.
Future<T?> _sheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: FractionallySizedBox(heightFactor: 0.9, child: builder(ctx)),
      ),
    );

class ExercisePicker extends StatefulWidget {
  /// [selected] 가 null 이면 하나 고르기([onPick] 필수), 아니면 여러 개
  /// 고르기([onDone] 필수).
  const ExercisePicker({
    super.key,
    this.equip,
    this.exclude = const {},
    this.familiar = const [],
    this.recent = const [],
    this.title,
    this.selected,
    this.onPick,
    this.onDone,
  }) : assert(selected == null ? onPick != null : onDone != null);

  /// 내가 가진 기구. null 이면 전부 내 것으로 칩니다(표 · 토글 없음).
  final Set<String>? equip;
  /// 목록에서 뺄 종목(이미 세션에 있는 것).
  final Set<String> exclude;
  final List<String> familiar;
  final List<String> recent;
  final String? title;
  /// 여러 개 고르기의 처음 체크 상태.
  final Set<String>? selected;
  final ValueChanged<Exercise>? onPick;
  final ValueChanged<List<Exercise>>? onDone;

  @override
  State<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<ExercisePicker> {
  final _query = TextEditingController();
  String? _group;
  /// 「내 기구만」 — 기본은 꺼짐(전부 보임). 시트 안에서 부위를 오가도 유지됩니다.
  bool _mineOnly = false;
  /// 고른 순서를 지킵니다 — 세션에 넣을 때 그 순서가 됩니다.
  late final List<String> _chosen = [...?widget.selected];

  bool get _multi => widget.selected != null;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _visible(Exercise e) => !widget.exclude.contains(e.id);

  /// 이 기구가 내 것인가. equip 을 안 주면 전부, 맨몸은 언제나.
  bool _mineEquip(String k) => widget.equip == null || k == 'bodyweight' || widget.equip!.contains(k);

  bool _mine(Exercise e) => _mineEquip(e.equip);

  List<Exercise> _lookup(List<String> ids) => [
        for (final id in ids)
          if (exerciseById(id) case final e? when _visible(e)) e,
      ];

  void _pick(Exercise e) {
    if (!_multi) {
      widget.onPick!(e);
      return;
    }
    setState(() {
      if (!_chosen.remove(e.id)) _chosen.add(e.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final q = _query.text.trim();
    final Widget body;
    if (q.isNotEmpty) {
      body = _searchList(t, q);
    } else if (_group == null) {
      body = _home(t);
    } else {
      body = _groupList(t, _group!);
    }
    return Column(children: [
      _header(t),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          key: const ValueKey('pick-search'),
          controller: _query,
          onChanged: (_) => setState(() {}),
          /* 돋보기 키 — 누르면 키보드가 내려가고 결과만 남습니다. */
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '이름 · 별칭으로 찾기',
            isDense: true,
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: '지우기',
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () => setState(_query.clear),
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      Expanded(child: body),
    ]);
  }

  Widget _header(ThemeData t) {
    final inGroup = _group != null;
    final n = _chosen.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(inGroup ? 4 : 16, 0, 16, 4),
      child: Row(children: [
        if (inGroup)
          IconButton(
            key: const ValueKey('pick-back'),
            tooltip: '부위 목록',
            icon: const Icon(LucideIcons.arrowLeft),
            /* 「내 기구만」 은 끄지 않습니다 — 부위 칩의 숫자는 전체 종목 수라 토글에 흔들리지
               않고, 켠 사람은 다음 부위에서도 내 기구만 보고 싶어 합니다(한 번 덜 누름). */
            onPressed: () => setState(() => _group = null),
          ),
        Expanded(
          child: Text(
            inGroup ? (kGroupLabel[_group] ?? _group!) : (widget.title ?? '종목 고르기'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (_multi)
          FilledButton(
            key: const ValueKey('pick-done'),
            onPressed: () => widget.onDone!(_lookup(_chosen)),
            child: Text(n == 0 ? '완료' : '완료 $n'),
          ),
      ]),
    );
  }

  TextStyle? _labelStyle(ThemeData t) => t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700);

  Widget _label(ThemeData t, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
        child: Text(text, style: _labelStyle(t)),
      );

  /* ---- 첫 화면: 최근 · 익숙한 종목 · 부위 ---------------------------------- */

  /* 세 목록(첫 화면 · 부위 · 검색)은 같은 자리의 ListView 라 키가 없으면 Flutter 가
     스크롤 위치를 물려줍니다 — 첫 화면을 내리고 부위를 누르면 부위 목록이 맨 끝부터
     열렸습니다. 키를 달리 주면 목록마다 새 위치(0)에서 섭니다.
     셋 다 끌면 키보드가 내려갑니다([_dismissOnDrag]) — 키보드가 뜬 채 90% 시트는
     목록이 몇 줄밖에 안 보이고, 끌기는 「더 보고 싶다」 는 뜻입니다. */
  static const _dismissOnDrag = ScrollViewKeyboardDismissBehavior.onDrag;

  Widget _home(ThemeData t) {
    final recent = _lookup(widget.recent);
    final familiar = _lookup(widget.familiar);
    return ListView(
      key: const ValueKey('pick-home'),
      keyboardDismissBehavior: _dismissOnDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (recent.isNotEmpty) _quickRow(t, '최근', recent),
        if (familiar.isNotEmpty) _quickRow(t, '익숙한 종목', familiar),
        for (final (area, groups) in kPickerAreas) ...[
          _label(t, area),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final g in groups) _groupTile(t, g)]),
        ],
      ],
    );
  }

  /// 한 줄 칩 — 여기서 고르면 한 번에 끝입니다.
  Widget _quickRow(ThemeData t, String title, List<Exercise> xs) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(t, title),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final e in xs)
              if (_multi)
                FilterChip(
                  key: ValueKey('pick-quick-${e.id}'),
                  label: Text(e.name),
                  selected: _chosen.contains(e.id),
                  onSelected: (_) => _pick(e),
                )
              else
                ActionChip(
                  key: ValueKey('pick-quick-${e.id}'),
                  label: Text(e.name),
                  onPressed: () => _pick(e),
                ),
          ]),
        ],
      );

  /// 부위 칩 — 이름과 종목 수. 기구를 가리지 않은 전체라 「내 기구만」 에 흔들리지 않습니다.
  Widget _groupTile(ThemeData t, String g) {
    final n = exercisesFor(g).where(_visible).length;
    return Material(
      color: mb(context).accentSub,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('pick-group-$g'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _group = g),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(kGroupLabel[g] ?? g,
                style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text('$n', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ]),
        ),
      ),
    );
  }

  /* ---- 부위 화면: 기구별 섹션 --------------------------------------------- */

  Widget _groupList(ThemeData t, String g) {
    final all = exercisesFor(g).where(_visible).toList();
    final shown = _mineOnly ? all.where(_mine).toList() : all;
    final sections = <String, List<Exercise>>{};
    for (final e in shown) {
      sections.putIfAbsent(e.equip, () => []).add(e);
    }
    /* 내 기구 먼저, 그 안에서는 기구 순서. 내 기구가 아닌 것은 뒤로 — 집 사용자가 흐린
       머신 · 케이블 · 바벨 스무 줄을 넘겨야 자기 종목이 나오면 안 됩니다. */
    final known = [
      ...kPickerEquipOrder,
      for (final k in sections.keys) if (!kPickerEquipOrder.contains(k)) k,
    ];
    final order = [
      for (final k in known) if (_mineEquip(k)) k,
      for (final k in known) if (!_mineEquip(k)) k,
    ];
    return ListView(
      key: ValueKey('pick-group-list-$g'),
      keyboardDismissBehavior: _dismissOnDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (widget.equip != null)
          Align(
            alignment: Alignment.centerRight,
            child: FilterChip(
              key: const ValueKey('pick-mine-only'),
              label: const Text('내 기구만'),
              selected: _mineOnly,
              onSelected: (v) => setState(() => _mineOnly = v),
            ),
          ),
        /* 토글이 꺼져 있는데도 비었으면 exclude(이미 세션에 다 든 부위)입니다 — 그때 「꺼 보세요」 는 헛말. */
        if (shown.isEmpty)
          EmptyState(
              title: _mineOnly ? '내 기구로 되는 종목이 없습니다' : '이 부위 종목은 이미 다 들어 있습니다',
              detail: _mineOnly ? '「내 기구만」 을 꺼 보세요.' : '다른 부위에서 골라 보세요.'),
        for (final k in order)
          if (sections[k] case final xs?) _section(t, k, xs),
      ],
    );
  }

  /// 기구 섹션 하나. 내 기구가 아니면 머리글에 「내 기구 아님」 표를 달고 전체를 살짝
  /// 흐리게 — 그래도 누르면 골라집니다(오늘만 빌려 쓰는 머신도 있습니다).
  /* 섹션 안 줄마다 기구 표를 또 달지 않습니다 — 머리글이 이미 말했습니다. */
  Widget _section(ThemeData t, String k, List<Exercise> xs) {
    final mine = _mineEquip(k);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
        child: Row(children: [
          Text(kEquipLabel[k] ?? k, key: ValueKey('pick-sec-$k'), style: _labelStyle(t)),
          if (!mine) ...[
            const SizedBox(width: 6),
            Container(
              key: ValueKey('pick-notmine-$k'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: t.dividerColor),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('내 기구 아님', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ),
          ],
        ]),
      ),
      for (final e in xs) _row(t, e, withEquip: false),
    ]);
    if (mine) return body;
    return Opacity(key: ValueKey('pick-dim-$k'), opacity: kPickerDimOpacity, child: body);
  }

  /* ---- 검색: 부위 · 기구 가리지 않고 ------------------------------------ */

  /// 이름을 알고 찾는 사람에게는 기구 필터가 방해입니다 — 전부 보여 주고
  /// 줄마다 기구 태그를 답니다.
  Widget _searchList(ThemeData t, String q) {
    final hits = searchExercises(q).where(_visible).toList();
    if (hits.isEmpty) {
      return const EmptyState(title: '맞는 종목이 없습니다', detail: '영문 · 별칭(이너싸이 · 스미스)도 됩니다.');
    }
    return ListView(
      key: const ValueKey('pick-search-list'),
      keyboardDismissBehavior: _dismissOnDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [for (final e in hits) _row(t, e, withGroup: true)],
    );
  }

  /// 종목 한 줄: 이름 · (검색이면) 기구 태그 · 한 줄 요령. 이름과 요령은 두 줄까지 —
  /// 360px 에 글자 1.3배면 '인클라인 체스트 프레스 머신' 이 한 줄에 안 들어갑니다.
  Widget _row(ThemeData t, Exercise e, {bool withGroup = false, bool withEquip = true}) {
    final note = (e.note ?? '').trim();
    final sub = [
      if (withGroup) kGroupLabel[e.group] ?? e.group,
      if (note.isNotEmpty) note,
    ].join(' · ');
    final title = Row(children: [
      Flexible(child: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
      if (widget.familiar.contains(e.id))
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(LucideIcons.star, size: 14, color: t.colorScheme.primary),
        ),
    ]);
    final subtitle = sub.isEmpty
        ? null
        : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall?.copyWith(color: t.hintColor));
    final tag = withEquip ? Pill(kEquipLabel[e.equip] ?? e.equip) : null;
    if (_multi) {
      return CheckboxListTile(
        key: ValueKey('pick-${e.id}'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _chosen.contains(e.id),
        onChanged: (_) => _pick(e),
        title: title,
        subtitle: subtitle,
        secondary: tag,
      );
    }
    return ListTile(
      key: ValueKey('pick-${e.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => _pick(e),
      title: title,
      subtitle: subtitle,
      trailing: tag,
    );
  }
}
