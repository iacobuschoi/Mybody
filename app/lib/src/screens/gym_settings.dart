/* =============================================================================
 * gym_settings.dart — 설정의 「운동 장소와 기구」 카드
 *
 * 플랜의 종목은 엔진이 바벨 · 머신 기준으로 뽑습니다. 그런데 머신 두 대짜리
 * 헬스장, 덤벨만 있는 집이 흔합니다. 없는 기구의 종목이 화면에 있으면 사람은
 * 그 자리에서 앱을 닫습니다. 여기서 있는 기구를 말해 두면 운동 화면이
 * (workout/planner.dart 의 tailorSession) 종목을 그에 맞춰 바꿉니다. 익숙한
 * 종목을 먼저 넣는 것도 같은 이유입니다 — 아는 동작이 앞에 있어야 시작합니다.
 *
 * 2차 피드백(13 · 15 · 28)으로 다시 그렸습니다. 글 대신 모양으로 말합니다:
 *   · 장소는 큰 카드 둘(헬스장 · 집) — 하나를 고르면 그 자리의 프리셋이 됩니다.
 *   · 기구는 아이콘 타일 3열 — 켜진 것은 채워지고, 맨몸은 잠겨 있습니다.
 *   · 「하루에 쓸 머신 수」 — 헬스장에 있는 머신 수가 아니라 한 번 운동에 돌
 *     머신 수입니다(13). 세그먼트 2 · 4 · 6 · 제한 없음.
 *   · 익숙한 종목은 부위별로 묶인 칩, 「추가」 는 종목 고르기 시트(두 번 터치).
 *   · 맨 위 한 줄 요약. 설정을 안 만진 사람은 초보 프리셋(머신 4개 + 덤벨,
 *     15)이고 「초보 기본」 표가 붙습니다. 바꾼 뒤에는 「초보 기본으로」 로 돌아옵니다.
 *
 * 값은 settings['gym'] 한 칸에 GymPrefs.toJson() 모양으로 있습니다. 쓸 때마다
 * 지금 설정을 다시 읽습니다 — 시트를 열어 둔 채 다른 곳에서 바뀐 값을 옛
 * 값으로 덮어쓰지 않으려고요.
 * ========================================================================== */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app_state.dart';
import '../scope.dart';
import '../ui/widgets.dart';
import '../workout/exercises.dart';
import '../workout/prefs.dart';
import 'exercise_picker.dart';

/// 「하루에 쓸 머신 수」 의 눈금. null 은 「제한 없음」 — 한산한 헬스장.
/// 0 · 1 은 눈금에 없습니다: 머신을 안 쓰는 사람은 머신 · 케이블 타일을 끕니다.
/// 옛 저장값(0 · 1)은 GymPrefs.fromSettings 가 첫 눈금으로 올려 읽어, 켜 보이는
/// 칸과 실제 규칙이 언제나 같습니다.
const List<int?> kMachineStops = [kMachineCountMin, 4, 6, null];

/// 부위 이름 — 사전(exercises.dart)의 이름표. 모르는 부위는 id 그대로.
String groupLabel(String group) => kGroupLabel[group] ?? group;

/// 「무제한」 — '제한 없음' 은 360px 세그먼트 한 칸(65px)에 두 줄로 접혔습니다.
String machineLabel(int? n) => n == null ? '무제한' : (n <= 0 ? '없음' : '$n대');

/// 요약에 쓰는 말 — 「하루 머신 4대」. '머신 4대' 만 쓰면 헬스장에 있는 머신 수로
/// 읽힙니다(피드백 13). 요약에서는 '제한 없음' 이 '무제한' 보다 읽힙니다.
String machineSummary(int? n) => n == null ? '머신 제한 없음' : '하루 머신 ${machineLabel(n)}';

/// 저장된 수가 눈금 사이(3)면 그 아래 눈금, 눈금보다 작으면(0 · 1) 첫 눈금.
int machineStopIndex(int? n) {
  if (n == null) return kMachineStops.length - 1;
  var i = 0;
  for (var k = 0; k < kMachineStops.length; k++) {
    final s = kMachineStops[k];
    if (s != null && s <= n) i = k;
  }
  return i;
}

/// 설정 한 줄 요약 — 카드 맨 위와 플랜 탭의 종목 목록 위에 섭니다.
/// 예: '헬스장 · 기구 3종 · 하루 머신 4대 · 익숙한 종목 2개'.
String gymPrefsSummary(GymPrefs p) {
  /* 맨몸은 기구가 아닙니다 — 세면 "기구 1종" 인 집이 생깁니다. */
  final gear = p.equipment.where((e) => e != 'bodyweight').length;
  final parts = <String>[
    p.isHome ? '집' : '헬스장',
    '기구 $gear종',
    if (!p.isHome) machineSummary(p.machineCount),
    p.familiar.isEmpty ? '익숙한 종목 없음' : '익숙한 종목 ${p.familiar.length}개',
  ];
  return parts.join(' · ');
}

/// 기구 타일의 순서와 아이콘. 맨몸은 맨 뒤 — 언제나 켜져 있어 고를 일이 없습니다.
const List<String> kEquipTileOrder = [
  'barbell', 'dumbbell', 'machine', 'cable', 'band', 'kettlebell', 'bodyweight',
];

/// 카드 하나짜리 화면 — 플랜 탭의 「기구 설정」 이 여기로 옵니다. 설정 탭에도 같은
/// 카드가 있습니다(같은 저장소, 같은 값).
class GymSettingsScreen extends StatelessWidget {
  const GymSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('운동 장소와 기구')),
      body: ListView(padding: const EdgeInsets.all(16), children: const [GymSettingsCard()]),
    );
  }
}

/// 지금 설정을 읽고 → 고치고 → 씁니다.
void updateGymPrefs(AppState app, GymPrefs Function(GymPrefs) change) {
  final settings = ((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>();
  final next = change(GymPrefs.fromSettings(settings));
  app.store.set({'settings': {...settings, 'gym': next.toJson()}});
}

class GymSettingsCard extends StatelessWidget {
  const GymSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final settings = ((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>();
    final prefs = GymPrefs.fromSettings(settings);
    final t = Theme.of(context);
    final hint = t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5);
    final label = t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700);
    final atGym = !prefs.isHome;
    /* 머신도 케이블도 껐으면 「하루에 쓸 머신 수」 는 셀 것이 없습니다 — 숨깁니다. */
    final hasMachines = prefs.equipment.contains('machine') || prefs.equipment.contains('cable');

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(
          '운동 장소와 기구',
          trailing: prefs.isBeginnerPreset
              ? const Pill('초보 기본', tone: Tone.ok)
              : TextButton(
                  key: const Key('gym-reset'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: () => _resetToBeginner(context, app),
                  child: const Text('초보 기본으로'),
                ),
        ),
        /* 요약은 360px 에서 한 줄(294px)을 넘어 두 줄로 접힙니다 — 잘라 내면 뒤의
           「익숙한 종목 n개」 가 사라지는데, 그게 이 줄에서 제일 자주 바뀌는 숫자입니다. */
        Text(gymPrefsSummary(prefs),
            key: const Key('gym-summary'), maxLines: 2, overflow: TextOverflow.ellipsis, style: hint),
        const SizedBox(height: 12),

        /* 장소 — 카드를 고르면 그 자리의 프리셋(기구 · 머신 수)이 됩니다. 헬스장 기구를
           켜 둔 채 「집」을 고르면 바벨 종목이 그대로 남았습니다. 익숙한 종목은 지킵니다. */
        Row(children: [
          Expanded(
            child: _PlaceCard(
              key: const Key('gym-place-gym'),
              icon: LucideIcons.dumbbell,
              title: '헬스장',
              detail: '머신·프리웨이트',
              selected: atGym,
              onTap: () => _setPlace(app, 'gym'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PlaceCard(
              key: const Key('gym-place-home'),
              icon: LucideIcons.home,
              title: '집',
              detail: '맨몸·소도구',
              selected: !atGym,
              onTap: () => _setPlace(app, 'home'),
            ),
          ),
        ]),
        const SizedBox(height: 14),

        Text('기구', style: label),
        const SizedBox(height: 6),
        _EquipGrid(
          on: prefs.equipment,
          onToggle: (key, on) => updateGymPrefs(app, (p) {
            final eq = {...p.equipment};
            if (on) {
              eq.add(key);
            } else {
              eq.remove(key);
            }
            return p.copyWith(equipment: eq);
          }),
        ),

        if (atGym && hasMachines) ...[
          const SizedBox(height: 14),
          Text('하루에 쓸 머신 수', style: label),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            key: const Key('gym-machines'),
            segments: [
              for (var i = 0; i < kMachineStops.length; i++)
                ButtonSegment(
                  value: i,
                  /* 숫자만 — 「2대」 의 '대' 는 머리글이 이미 말했습니다. */
                  label: Text(kMachineStops[i] == null ? machineLabel(null) : '${kMachineStops[i]}'),
                ),
            ],
            selected: {machineStopIndex(prefs.machineCount)},
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            /* 「무제한」 이 360px 에서 네 칸에 들어가려면 칸 안 여백을 줄여야 합니다. */
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
              visualDensity: VisualDensity.compact,
            ),
            onSelectionChanged: (s) =>
                updateGymPrefs(app, (p) => p.copyWith(machineCount: kMachineStops[s.first])),
          ),
          const SizedBox(height: 4),
          Text('머신은 이만큼만, 나머지는 프리웨이트·맨몸',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: hint),
        ],

        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('익숙한 종목', style: label)),
          TextButton.icon(
            key: const Key('gym-fam-add'),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => _addFamiliar(context, app),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('추가'),
          ),
        ]),
        if (prefs.familiar.isEmpty)
          Text('없음', style: hint)
        else
          _FamiliarChips(
            ids: prefs.familiar,
            onRemove: (id) => updateGymPrefs(
                app, (p) => p.copyWith(familiar: [for (final x in p.familiar) if (x != id) x])),
          ),
      ]),
    );
  }

  /// 이미 고른 자리를 다시 누르면 아무 일도 없습니다 — 확인 삼아 누른 한 번에
  /// 바벨이 꺼지고 머신 수가 초보 프리셋으로 돌아가면 안 됩니다.
  void _setPlace(AppState app, String place) {
    final now = GymPrefs.fromSettings(((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>());
    if (now.place == place) return;
    final preset = GymPrefs.presetFor(place);
    updateGymPrefs(app, (p) => p.copyWith(
        place: place, equipment: preset.equipment, machineCount: preset.machineCount));
  }

  /// 「초보 기본으로」 — 익숙한 종목까지 지워지므로 한 번 묻습니다.
  Future<void> _resetToBeginner(BuildContext context, AppState app) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('초보 기본으로'),
        content: const Text('헬스장 · 머신 4개 + 덤벨 · 케이블. 익숙한 종목은 지워집니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
              key: const Key('gym-reset-ok'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인')),
        ],
      ),
    );
    if (yes == true) updateGymPrefs(app, (_) => const GymPrefs.beginner());
  }

  /// 종목 고르기 시트(여러 개). 지금 목록이 체크된 채 열리고, 「완료」 가 곧 저장입니다 —
  /// 시트에서 뺀 것도 같이 반영됩니다. 그냥 내리면(null) 아무것도 안 바뀝니다.
  /// 사전에 없는 번호(다른 기기의 더 새 사전 · 옛 번호)는 시트가 모르므로 그대로
  /// 이어 둡니다 — 종목 하나 넣었다고 「기타」 가 통째로 사라지면 안 됩니다.
  Future<void> _addFamiliar(BuildContext context, AppState app) async {
    final now = GymPrefs.fromSettings(((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>());
    final picked = await pickExercises(
      context,
      equip: now.equipment,
      selected: now.familiar.toSet(),
      familiar: now.familiar,
      title: '익숙한 종목',
    );
    if (picked == null) return;
    final unknown = [for (final id in now.familiar) if (exerciseById(id) == null) id];
    updateGymPrefs(app, (p) => p.copyWith(familiar: [for (final e in picked) e.id, ...unknown]));
  }
}

/// 장소 카드 — 아이콘 · 이름 · 한 줄. 고른 것은 테두리와 바탕이 진합니다.
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final primary = t.colorScheme.primary;
    return Material(
      color: selected ? c.accentSub : t.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? primary : t.dividerColor, width: selected ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 26, color: selected ? primary : t.hintColor),
            const SizedBox(height: 8),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800, color: selected ? primary : null)),
            Text(detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ]),
        ),
      ),
    );
  }
}

/// 기구 타일 3열. 켜진 타일은 채워지고, 맨몸은 잠겨 있습니다(언제나 켜짐).
class _EquipGrid extends StatelessWidget {
  const _EquipGrid({required this.on, required this.onToggle});

  final Set<String> on;
  final void Function(String key, bool on) onToggle;

  static IconData _icon(String key) => switch (key) {
        'barbell' => LucideIcons.dumbbell,
        'dumbbell' => LucideIcons.dumbbell,
        'machine' => LucideIcons.cog,
        'cable' => LucideIcons.link,
        'band' => LucideIcons.infinity,
        'kettlebell' => LucideIcons.bell,
        _ => LucideIcons.personStanding,
      };

  @override
  Widget build(BuildContext context) {
    const cols = 3;
    const gap = 8.0;
    final keys = [for (final k in kEquipTileOrder) if (kEquipLabel.containsKey(k)) k];
    final rows = <Widget>[];
    for (var i = 0; i < keys.length; i += cols) {
      final slice = keys.sublist(i, math.min(i + cols, keys.length));
      rows.add(Row(children: [
        for (var j = 0; j < cols; j++) ...[
          if (j > 0) const SizedBox(width: gap),
          Expanded(
            child: j < slice.length
                ? _EquipTile(
                    key: Key('gym-equip-${slice[j]}'),
                    icon: _icon(slice[j]),
                    /* 바벨과 덤벨은 같은 아이콘뿐이라 덤벨은 기울여 구분합니다. */
                    tilt: slice[j] == 'dumbbell',
                    label: kEquipLabel[slice[j]]!,
                    on: on.contains(slice[j]),
                    locked: slice[j] == 'bodyweight',
                    onTap: () => onToggle(slice[j], !on.contains(slice[j])),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ]));
      if (i + cols < keys.length) rows.add(const SizedBox(height: gap));
    }
    return Column(children: rows);
  }
}

class _EquipTile extends StatelessWidget {
  const _EquipTile({
    super.key,
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.locked = false,
    this.tilt = false,
  });

  final IconData icon;
  final String label;
  final bool on;
  final bool locked;
  final bool tilt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final primary = t.colorScheme.primary;
    final fg = on ? t.colorScheme.onPrimary : t.colorScheme.onSurface;
    final bg = on ? (locked ? primary.withValues(alpha: 0.55) : primary) : t.colorScheme.surface;
    Widget glyph = Icon(icon, size: 22, color: fg);
    if (tilt) glyph = Transform.rotate(angle: -math.pi / 4, child: glyph);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        /* 잠긴 타일은 눌러도 아무 일도 없습니다 — 꺼도 다시 켜지는 것보다 고장처럼 안 보입니다. */
        onTap: locked ? null : onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? Colors.transparent : t.dividerColor),
          ),
          child: Stack(children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                glyph,
                const SizedBox(height: 4),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
              ]),
            ),
            if (locked)
              Positioned(
                  top: 6, right: 6, child: Icon(LucideIcons.lock, size: 12, color: fg.withValues(alpha: 0.8))),
          ]),
        ),
      ),
    );
  }
}

/// 익숙한 종목 — 부위별 작은 머리글 아래 칩. familiar 는 종목의 고유번호(id)라
/// 이름은 사전에서 찾고, 사전에 없는 번호는 「기타」 에 번호 그대로 둡니다.
class _FamiliarChips extends StatelessWidget {
  const _FamiliarChips({required this.ids, required this.onRemove});

  final List<String> ids;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final byGroup = <String, List<(String, String)>>{};
    for (final id in ids) {
      final e = exerciseById(id);
      byGroup.putIfAbsent(e?.group ?? '', () => []).add((id, e?.name ?? id));
    }
    final order = [...kGroupLabel.keys, ''];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final g in order)
        if (byGroup[g] case final xs?) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(g.isEmpty ? '기타' : groupLabel(g),
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final (id, name) in xs)
              InputChip(
                key: Key('gym-fam-$id'),
                /* 사전에 없는 긴 번호는 칩이 조용히 흐려(fade) 끝을 감춥니다 — 줄임표로. */
                label: Text(name, overflow: TextOverflow.ellipsis),
                visualDensity: VisualDensity.compact,
                onDeleted: () => onRemove(id),
              ),
          ]),
        ],
    ]);
  }
}
