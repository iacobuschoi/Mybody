/* =============================================================================
 * scandetail.dart — P11 측정 한 건 자세히
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';

const _rows = [
  ('weightKg', '체중', 'kg', 1),
  ('smmKg', '골격근량', 'kg', 1),
  ('bfmKg', '체지방량', 'kg', 1),
  ('pbfPct', '체지방률', '%', 1),
  ('ffmKg', '제지방량', 'kg', 1),
  ('bmi', 'BMI', '', 1),
  ('tbwL', '체수분', 'L', 1),
  ('proteinKg', '단백질', 'kg', 1),
  ('mineralKg', '무기질', 'kg', 2),
  ('bmrKcal', '기초대사량', 'kcal', 0),
  ('visceralFatLevel', '내장지방 레벨', '', 0),
  ('whr', '복부지방률', '', 2),
  ('inbodyScore', 'InBody 점수', '점', 0),
];

class ScanDetailScreen extends StatelessWidget {
  const ScanDetailScreen({super.key, required this.scanId});
  final Object? scanId;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final scan = app.store.scanById(scanId);
    if (scan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('측정')),
        body: const EmptyState(title: '그 측정을 찾지 못했습니다'),
      );
    }
    final profile = app.profile ?? core.kSeedProfile;
    final d = core.derive(scan, profile);
    final all = app.store.sortedScans();
    final idx = all.indexWhere((s) => s['id'] == scan['id']);
    final prev = idx > 0 ? all[idx - 1] : null;
    final check = core.run(scan, profile, prev);
    final broken = ((check['checks'] as List?) ?? const [])
        .map((x) => (x as Map).cast<String, Object?>())
        .where((c) => c['ok'] != true)
        .toList();
    final t = Theme.of(context);
    final photoId = scan['photoId'];
    final photoFile =
        photoId is String ? app.photos?.fileOf(photoId) : null;

    return Scaffold(
      appBar: AppBar(title: Text(dateK(scan['measuredAt']))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        /* 결과지 사진. 붙여 둔 게 있으면 여기서 다시 봅니다 — 숫자가
           이상할 때 원본을 볼 수 있어야 합니다. */
        if (photoFile != null)
          MbCard(
            padding: EdgeInsets.zero,
            child: GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  insetPadding: const EdgeInsets.all(12),
                  child: InteractiveViewer(
                      maxScale: 5, child: Image.file(photoFile)),
                ),
              ),
              child: Image.file(photoFile,
                  width: double.infinity, height: 220, fit: BoxFit.cover),
            ),
          ),
        for (final c in broken)
          Note(tone: Tone.warn, title: '${c['label']}', text: ' ${c['why'] ?? ''}'),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('결과지 값'),
            for (final r in _rows)
              if (scan[r.$1] != null || d[r.$1] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(r.$2, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
                    Row(children: [
                      Text(
                          core.toFixed(core.jsToNumber(scan[r.$1] ?? d[r.$1]), r.$4),
                          style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (r.$3.isNotEmpty)
                        Text(' ${r.$3}', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                      /* 인쇄값이 없어서 계산한 칸은 그렇다고 말합니다 —
                         결과지에 있는 숫자와 우리가 만든 숫자는 다릅니다. */
                      if (scan[r.$1] == null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text('계산값',
                              style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                        ),
                    ]),
                  ]),
                ),
          ]),
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('여기서 나온 값'),
            Text('기초대사량 ${n0(d['bmrKcal'])}kcal (${d['bmrSource']})',
                style: t.textTheme.bodySmall),
            Text('활동대사량 ${n0(d['tdeeKcal'])}kcal (활동계수 ${n2(d['pal'])})',
                style: t.textTheme.bodySmall),
            Text('골격근/제지방 비율 ${n2(d['smmToFfm'])}', style: t.textTheme.bodySmall),
          ]),
        ),
        OutlinedButton(
          onPressed: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('이 측정을 지울까요?'),
                content: const Text('딸린 사진도 같이 지웁니다. 되돌릴 수 없습니다.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('그대로 두기')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('지우기')),
                ],
              ),
            );
            if (yes != true || !context.mounted) return;
            app.store.removeScan(scan['id']);
            Navigator.of(context).pop();
          },
          child: const Text('이 측정 지우기'),
        ),
      ]),
    );
  }
}
