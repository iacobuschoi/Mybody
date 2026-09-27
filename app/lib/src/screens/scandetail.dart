/* =============================================================================
 * scandetail.dart — P11 측정 한 건 자세히
 *
 * **키·체중 추정도 여기서 봅니다.** 추정(estimate.dart)은 결과지가 아니라
 * 공식이 낸 값이라, 이 화면은 세 가지를 다르게 합니다.
 *
 *  - 맨 위에 「추정치예요」 와 오차, 그리고 「인바디 올리기」 — 이 숫자를
 *    진짜로 바꾸는 길을 숫자 바로 위에 둡니다. 이 화면을 업로드 화면으로
 *    **바꿔 끼웁니다**(push 가 아니라 pushReplacement). 실측을 저장하면
 *    추정은 지워지는데, 그 위에 쌓아 올렸으면 검수 화면이 닫힌 뒤 사람은
 *    「그 측정을 찾지 못했습니다」 로 돌아옵니다 — 방금 잘 한 일이 고장처럼
 *    보입니다. 바꿔 끼우면 들어왔던 곳(홈 · 기록)으로 돌아갑니다.
 *  - 검산(crosscheck)을 안 돌립니다. 검산은 결과지 안의 값끼리 맞는지 보는
 *    것인데, 추정은 한 공식에서 나와 늘 맞습니다 — 통과했다고 믿을 일도,
 *    어긋났다고 겁낼 일도 아닙니다.
 *  - 「결과지 값」 이 아니라 「추정값」. 칸마다 「계산값」 을 달면 전부가
 *    계산값이라 말이 됩니다 — 제목의 「추정」 한 번이면 됩니다.
 *
 * 실측의 검산은 바로 앞 **실측** 과 견줍니다. 앞의 추정과 견주면 공식의
 * 골격근/제지방 비율을 기준 삼아 멀쩡한 결과지를 "이상하다" 고 합니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../estimate.dart';
import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import 'upload.dart';

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
    final est = isEstimate(scan);
    final all = app.store.sortedScans();
    final idx = all.indexWhere((s) => s['id'] == scan['id']);
    /* 견줄 앞 측정은 바로 앞 **실측** — 파일 머리. */
    final earlier = idx > 0 ? realScans(all.sublist(0, idx)) : const <Map<String, Object?>>[];
    final prev = earlier.isEmpty ? null : earlier.last;
    final broken = est
        ? const <Map<String, Object?>>[]
        : ((core.run(scan, profile, prev)['checks'] as List?) ?? const [])
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
        if (est) ...[
          const Note(
              tone: Tone.warn,
              title: '추정치예요.',
              text: ' 키·체중으로 계산했어요 — $kEstimateCaveat'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                /* 바꿔 끼웁니다 — 저장하면 이 추정은 지워지니 돌아올 자리가 없습니다(파일 머리). */
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => const UploadScreen())),
                child: const Text('인바디 올리기'),
              ),
            ),
          ),
        ],
        for (final c in broken)
          Note(tone: Tone.warn, title: '${c['label']}', text: ' ${c['why'] ?? ''}'),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            est
                ? const SectionTitle('추정값', trailing: Pill('추정', tone: Tone.warn))
                : const SectionTitle('결과지 값'),
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
                      if (!est && scan[r.$1] == null)
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
                title: Text(est ? '이 추정을 지울까요?' : '이 측정을 지울까요?'),
                content: Text(est ? '되돌릴 수 없습니다.' : '딸린 사진도 같이 지웁니다. 되돌릴 수 없습니다.'),
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
          child: Text(est ? '이 추정 지우기' : '이 측정 지우기'),
        ),
      ]),
    );
  }
}
