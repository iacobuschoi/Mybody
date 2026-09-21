/* =============================================================================
 * upload.dart — P03 인바디 넣기 + P04 판독 검수
 *
 * 판독은 3층입니다. 이 화면은 0층과 2층의 입구입니다.
 *
 *   0층  숫자 세 개를 손으로 넣는다              ← 바닥. **항상 됩니다.**
 *   1층  넣은 값을 결과지 안의 다른 값과 검산한다 ← crosscheck
 *   2층  서버에 사진을 보내 초안을 받는다         ← 켜야만 돕니다
 *
 * 왜 0층이 기본인가: 플래너가 실제로 쓰는 숫자는 세 개뿐입니다 — 체중,
 * 골격근량, 체지방량. 사진을 보며 세 칸을 채우는 데 15초쯤 걸립니다.
 * 그리고 2층이 아무리 좋아져도 0층은 남습니다. 서버가 죽어도, 비행기
 * 안이어도, 결과지가 처음 보는 양식이어도 숫자는 들어가야 하니까요.
 * ========================================================================== */
import 'package:flutter/material.dart';



import '../ui/fmt.dart';
import '../ui/widgets.dart';
import 'review.dart';

/* 0층이 묻는 세 칸. 결과지에서 순서대로 붙어 있는 칸들이라 눈이 위에서
   아래로 한 번만 내려가면 됩니다. */
const _quick = [
  (key: 'weightKg', label: '체중', unit: 'kg', hint: '골격근·지방분석 맨 윗줄'),
  (key: 'smmKg', label: '골격근량', unit: 'kg', hint: '그 아래, SMM'),
  (key: 'bfmKg', label: '체지방량', unit: 'kg', hint: '그 아래, BFM — %가 아니라 kg'),
];

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _ctrl = <String, TextEditingController>{
    for (final q in _quick) q.key: TextEditingController(),
  };
  late DateTime _measuredAt = DateTime.now();

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready => _quick.every((q) {
        final v = double.tryParse(_ctrl[q.key]!.text.trim());
        return v != null && v > 0;
      });

  void _next() {
    final scan = <String, Object?>{
      'id': 'scan-${DateTime.now().millisecondsSinceEpoch}',
      'measuredAt': DateTime(_measuredAt.year, _measuredAt.month, _measuredAt.day, 9)
          .toUtc()
          .toIso8601String(),
      for (final q in _quick) q.key: double.tryParse(_ctrl[q.key]!.text.trim()),
    };
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReviewScreen(draft: scan)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('인바디 올리기')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Note(
          text: '결과지를 보면서 숫자 세 개만 넣으면 됩니다. 나머지는 다음 화면에서 '
              '채우거나, 비워 두면 이 셋에서 계산합니다.',
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('측정일'),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _measuredAt,
                  firstDate: DateTime(2015),
                  lastDate: DateTime.now(),
                  helpText: '결과지에 찍힌 날짜',
                );
                if (picked != null) setState(() => _measuredAt = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(dateK(_measuredAt.toIso8601String())),
                  const Icon(Icons.calendar_today_outlined, size: 18),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            for (final q in _quick) ...[
              TextField(
                controller: _ctrl[q.key],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: q.label,
                  suffixText: q.unit,
                  helperText: q.hint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ]),
        ),
        FilledButton(
          onPressed: _ready ? _next : null,
          child: const Text('다음 — 검산하기'),
        ),
        const SizedBox(height: 8),
        Text(
          '사진은 이 기기에만 남습니다. 자동 판독(서버로 사진을 보내는 것)은 '
          '설정에서 직접 켤 때만 돕니다.',
          style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5),
        ),
      ]),
    );
  }
}
