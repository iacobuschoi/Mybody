/* =============================================================================
 * gym_settings.dart — 설정의 「운동 장소와 기구」 카드
 *
 * 플랜의 종목은 엔진이 바벨 · 머신 기준으로 뽑습니다. 그런데 머신 두 대짜리
 * 헬스장, 덤벨만 있는 집이 흔합니다. 없는 기구의 종목이 화면에 있으면 사람은
 * 그 자리에서 앱을 닫습니다. 여기서 있는 기구를 말해 두면 운동 화면이
 * (workout/planner.dart 의 tailorSession) 종목을 그에 맞춰 바꿉니다. 익숙한
 * 종목을 먼저 넣는 것도 같은 이유입니다 — 아는 동작이 앞에 있어야 시작합니다.
 *
 * 값은 settings['gym'] 한 칸에 GymPrefs.toJson() 모양으로 있습니다. 쓸 때마다
 * 지금 설정을 다시 읽습니다 — 시트를 열어 둔 채 다른 곳에서 바뀐 값을 옛
 * 값으로 덮어쓰지 않으려고요.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app_state.dart';
import '../scope.dart';
import '../ui/widgets.dart';
import '../workout/exercises.dart';
import '../workout/prefs.dart';

/// 머신 대수의 눈금. null 은 「제한 없음」 — 큰 헬스장.
const List<int?> kMachineStops = [0, 2, 4, 6, null];

/// 부위 이름 — 사전(exercises.dart)의 이름표. 모르는 부위는 id 그대로.
String groupLabel(String group) => kGroupLabel[group] ?? group;

String machineLabel(int? n) => n == null ? '제한 없음' : (n <= 0 ? '없음' : '$n대');

/// 저장된 대수가 눈금 사이(3대)면 그 아래 눈금으로 봅니다.
int machineStopIndex(int? n) {
  if (n == null) return kMachineStops.length - 1;
  var i = 0;
  for (var k = 0; k < kMachineStops.length; k++) {
    final s = kMachineStops[k];
    if (s != null && s <= n) i = k;
  }
  return i;
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
    final atGym = prefs.place != 'home';
    final stop = machineStopIndex(prefs.machineCount);

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('운동 장소와 기구'),
        Text('있는 기구에 맞춰 종목을 바꿉니다. 익숙한 종목은 먼저 넣습니다.', style: hint),
        const SizedBox(height: 12),

        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'gym', icon: Icon(LucideIcons.dumbbell, size: 16), label: Text('헬스장')),
            ButtonSegment(value: 'home', icon: Icon(LucideIcons.home, size: 16), label: Text('집')),
          ],
          selected: {atGym ? 'gym' : 'home'},
          /* 장소를 바꾸면 기구도 그 장소의 기본으로 — 헬스장 기구를 켜 둔 채 「집」을 고르면
             바벨 종목이 그대로 남았습니다. 머신 대수 제한도 집에서는 뜻이 없어 풉니다. */
          onSelectionChanged: (s) => updateGymPrefs(app, (p) => p.copyWith(
              place: s.first, equipment: GymPrefs.defaultEquipment(s.first), machineCount: null)),
        ),
        const SizedBox(height: 14),

        Text('있는 기구', style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final e in kEquipLabel.entries)
            FilterChip(
              label: Text(e.value),
              selected: prefs.equipment.contains(e.key),
              /* 맨몸은 언제나 있습니다 — 꺼도 다시 켜지는 칩은 고장처럼 보여서 잠급니다. */
              onSelected: e.key == 'bodyweight' ? null : (on) => updateGymPrefs(app, (p) {
                final eq = {...p.equipment};
                if (on) {
                  eq.add(e.key);
                } else {
                  eq.remove(e.key);
                }
                return p.copyWith(equipment: eq);
              }),
            ),
        ]),

        if (atGym) ...[
          const SizedBox(height: 12),
          Text('머신 대수', style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
          Row(children: [
            IconButton(
              tooltip: '적게',
              onPressed: stop > 0
                  ? () => updateGymPrefs(app, (p) => p.copyWith(machineCount: kMachineStops[stop - 1]))
                  : null,
              icon: const Icon(LucideIcons.minus),
            ),
            SizedBox(
              width: 88,
              child: Text(machineLabel(kMachineStops[stop]),
                  textAlign: TextAlign.center,
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: '많게',
              onPressed: stop < kMachineStops.length - 1
                  ? () => updateGymPrefs(app, (p) => p.copyWith(machineCount: kMachineStops[stop + 1]))
                  : null,
              icon: const Icon(LucideIcons.plus),
            ),
          ]),
          Text('머신이 적은 곳이면 프리웨이트 · 맨몸 종목으로 바꿉니다.', style: hint),
        ],

        const SizedBox(height: 12),
        Text('익숙한 종목', style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (prefs.familiar.isEmpty)
          Text('아직 없습니다. 아는 동작을 골라 두면 플랜에서 그 종목이 앞으로 옵니다.', style: hint)
        else
          Wrap(spacing: 6, runSpacing: 4, children: [
            /* familiar 는 종목의 고유번호(id)입니다 — 이름은 사전에서 찾아 보여 줍니다. */
            for (final id in prefs.familiar)
              InputChip(
                label: Text(exerciseById(id)?.name ?? id),
                onDeleted: () => updateGymPrefs(
                    app, (p) => p.copyWith(familiar: [for (final x in p.familiar) if (x != id) x])),
              ),
          ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _pickFamiliar(context, app),
          icon: const Icon(LucideIcons.search, size: 18),
          label: const Text('종목 고르기'),
        ),
      ]),
    );
  }

  /// 종목 목록 — 부위별로 묶고, 이름이나 부위로 찾습니다. 체크는 바로 저장됩니다.
  Future<void> _pickFamiliar(BuildContext context, AppState app) async {
    final query = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final settings = ((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>();
        final chosen = GymPrefs.fromSettings(settings).familiar.toSet();
        final q = query.text.trim().toLowerCase();
        /* 순서는 목록에 적힌 대로 — 부위가 처음 나온 자리를 지킵니다. */
        final groups = <String, List<Exercise>>{};
        for (final e in kExerciseLibrary) {
          if (q.isNotEmpty &&
              !e.name.toLowerCase().contains(q) &&
              !groupLabel(e.group).toLowerCase().contains(q)) {
            continue;
          }
          groups.putIfAbsent(e.group, () => []).add(e);
        }
        final t = Theme.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (ctx, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('익숙한 종목', style: t.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('고른 종목이 플랜에 있으면 앞으로 옵니다. 없는 종목으로 바뀌지는 않습니다.',
                  style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
              const SizedBox(height: 12),
              TextField(
                controller: query,
                onChanged: (_) => setSheet(() {}),
                decoration: const InputDecoration(
                  hintText: '종목 · 부위 찾기',
                  prefixIcon: Icon(LucideIcons.search, size: 18),
                  border: OutlineInputBorder(),
                ),
              ),
              if (groups.isEmpty)
                const EmptyState(
                    title: '맞는 종목이 없습니다',
                    detail: '다른 말로 찾아보세요 — 부위 이름(가슴 · 등)도 됩니다.'),
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 0, 2),
                  child: Text(groupLabel(g.key),
                      style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                for (final e in g.value)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: chosen.contains(e.id),
                    title: Text(e.name),
                    subtitle: Text(
                        '${kEquipLabel[e.equip] ?? e.equip}${e.note == null || e.note!.isEmpty ? '' : ' · ${e.note}'}'),
                    onChanged: (on) {
                      updateGymPrefs(app, (p) {
                        final next = [for (final x in p.familiar) if (x != e.id) x];
                        if (on == true) next.add(e.id);
                        return p.copyWith(familiar: next);
                      });
                      setSheet(() {});
                    },
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
            ],
          ),
        );
      }),
    );
  }
}
