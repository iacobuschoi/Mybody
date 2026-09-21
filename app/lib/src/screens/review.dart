/* =============================================================================
 * review.dart — P04 판독 검수
 *
 * **이 화면의 핵심은 검산입니다.** 결과지의 숫자들은 서로 묶여 있어서
 * (체중 = 제지방 + 체지방, BMR = 370 + 21.6×FFM …) 한 칸을 잘못 읽으면
 * 다른 칸과 안 맞습니다. crosscheck 가 그걸 찾아 줍니다.
 *
 * 저장을 **막지는 않습니다.** 결과지가 우리 모형과 다를 수도 있고,
 * 그때 사용자를 가두면 앱이 쓸모없어집니다. 대신 무엇이 안 맞는지
 * 말하고, 고칠지 그대로 둘지는 사람이 정합니다.
 *
 * 지난 기록을 나중에 넣는 경우(backfill)에는 **계획을 다시 세우지
 * 않습니다.** 추이를 채우려고 옛날 결과지를 넣었는데 계획이 통째로
 * 바뀌면, 사용자는 자기가 뭘 망가뜨렸는지 모릅니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';

import '../ui/widgets.dart';

class _F {
  const _F(this.key, this.label, this.unit, {this.dec = 1, this.range, this.hint, this.derivable = false});
  final String key, label, unit;
  final int dec;
  final List<double>? range;
  final String? hint;
  final bool derivable;
}

const _core = [
  _F('weightKg', '체중', 'kg', range: [20, 300], hint: '결과지 상단 "체중" 값'),
  _F('smmKg', '골격근량 (SMM)', 'kg', range: [5, 70], hint: '근력이 아니라 근육의 무게입니다'),
  _F('bfmKg', '체지방량 (BFM)', 'kg', range: [1, 120], hint: '체지방률(%)이 아니라 kg 값'),
];

const _derived = [
  _F('pbfPct', '체지방률 (PBF)', '%', range: [3, 60], derivable: true,
      hint: '비워두면 체지방량 ÷ 체중으로 채웁니다'),
  _F('bmi', 'BMI', '', range: [10, 50], derivable: true, hint: '비워두면 체중 ÷ 키²로 채웁니다'),
  _F('ffmKg', '제지방량 (FFM)', 'kg', range: [15, 130], derivable: true,
      hint: '비워두면 체중 − 체지방량으로 채웁니다'),
  _F('visceralFatLevel', '내장지방 레벨', '레벨', dec: 0, range: [1, 30]),
  _F('bmrKcal', '기초대사량 (BMR)', 'kcal', dec: 0, range: [800, 4000]),
  _F('whr', '복부지방률 (WHR)', '', dec: 2, range: [0.6, 1.3],
      hint: '보통 0.7 ~ 1.1 사이입니다. 소수점 위치를 특히 잘 보세요.'),
  _F('inbodyScore', 'InBody 점수', '점', dec: 0, range: [20, 110]),
];

const _composition = [
  _F('tbwL', '체수분 (TBW)', 'L', range: [10, 80]),
  _F('proteinKg', '단백질', 'kg', range: [3, 25]),
  _F('mineralKg', '무기질', 'kg', dec: 2, range: [1, 10]),
];

const _labels = {
  'measuredAt': '측정일시', 'weightKg': '체중', 'smmKg': '골격근량', 'bfmKg': '체지방량',
  'pbfPct': '체지방률', 'bmi': 'BMI', 'ffmKg': '제지방량', 'bmrKcal': '기초대사량',
  'visceralFatLevel': '내장지방 레벨', 'whr': '복부지방률', 'inbodyScore': 'InBody 점수',
  'tbwL': '체수분', 'proteinKg': '단백질', 'mineralKg': '무기질', 'idealWeightKg': '적정체중',
};

String _labelOf(Object? key) => _labels['$key'] ?? '$key';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.draft});
  final Map<String, Object?> draft;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final Map<String, TextEditingController> _ctrl;
  bool _showMore = false;

  List<_F> get _all => [..._core, ..._derived, ..._composition];

  @override
  void initState() {
    super.initState();
    _ctrl = {
      for (final f in _all)
        f.key: TextEditingController(
            text: widget.draft[f.key] == null ? '' : core.toFixed(core.jsToNumber(widget.draft[f.key]), f.dec)),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _scan() {
    final out = <String, Object?>{
      'id': widget.draft['id'],
      'measuredAt': widget.draft['measuredAt'],
    };
    for (final f in _all) {
      final v = double.tryParse(_ctrl[f.key]!.text.trim());
      if (v != null) out[f.key] = v;
    }
    return out;
  }

  /// 비워 둔 파생값은 핵심 3종에서 채웁니다 — 비어 있는 것보다 계산값이 낫습니다.
  Map<String, Object?> _filled(Map<String, Object?> profile) {
    final s = _scan();
    final w = core.jsToNumber(s['weightKg']);
    final b = core.jsToNumber(s['bfmKg']);
    final h = core.jsToNumber(profile['heightCm']) / 100;
    s['pbfPct'] ??= core.r1(b / w * 100);
    s['ffmKg'] ??= core.r1(w - b);
    if (h > 0) s['bmi'] ??= core.r1(w / (h * h));
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final profile = app.profile ?? core.kSeedProfile;
    final scans = app.store.sortedScans();
    final prev = scans.isEmpty ? null : scans.last;
    final s = _filled(profile);

    final invalid = core.validateScan(s, prev);
    final check = core.run(s, profile, prev);
    /* 검산 결과는 세 갈래입니다:
         checks       결과지 안 등식이 맞는가 (체중 = 제지방 + 체지방 …)
         rangeIssues  값 하나가 사람의 범위를 벗어났는가
         deltaIssues  지난 측정에서 너무 많이 움직였는가
       셋을 합쳐서 보여 주되, 깨진 등식은 **무엇과 무엇이 안 맞는지**
       식으로 말합니다 — "확인해 주세요" 만 있으면 뭘 확인할지 모릅니다. */
    final checks = ((check['checks'] as List?) ?? const [])
        .map((x) => (x as Map).cast<String, Object?>())
        .where((c) => c['ok'] != true)
        .toList();
    final rangeIssues = ((check['rangeIssues'] as List?) ?? const [])
        .map((x) => (x as Map).cast<String, Object?>())
        .toList();
    final deltaIssues = ((check['deltaIssues'] as List?) ?? const [])
        .map((x) => (x as Map).cast<String, Object?>())
        .toList();
    final involved = (check['involved'] as List?);

    return Scaffold(
      appBar: AppBar(title: const Text('판독 결과 확인')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (invalid != null)
          Note(
            tone: Tone.bad,
            title: '물리적으로 맞지 않는 값이 있습니다.',
            text: (invalid['reasons'] as List).join(' '),
          ),
        for (final c in checks)
          Note(tone: Tone.bad, title: '${c['label']}', text: ' ${c['why'] ?? ''}'),
        if (involved != null && involved.length > 1)
          Note(
            tone: Tone.warn,
            title: '어느 칸이 틀렸는지는 결과지만으로 알 수 없습니다.',
            /* 용의자를 못 고르면 **못 고른다고 말합니다.** 하나를 찍어서
               고치라고 하면, 그게 틀렸을 때 두 칸이 틀립니다. */
            text: ' ${involved.map(_labelOf).join(' · ')} 중 하나입니다. 결과지를 다시 보세요.',
          ),
        /* 범위·변화량 경고는 문장 자체가 이미 칸 이름을 품고 있습니다 —
           앞에 라벨을 또 붙이면 "체중 체중 86.7kg 은…" 이 됩니다. */
        for (final i in [...rangeIssues, ...deltaIssues])
          Note(
            tone: i['level'] == 'bad' ? Tone.bad : Tone.warn,
            text: '${i['why'] ?? ''}',
          ),
        if (invalid == null && checks.isEmpty && rangeIssues.isEmpty && deltaIssues.isEmpty)
          const Note(tone: Tone.ok, title: '검산을 통과했습니다.', text: ' 값들이 서로 맞습니다.'),

        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('핵심 세 칸'),
            for (final f in _core) _field(f),
          ]),
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('나머지 칸',
                trailing: TextButton(
                  onPressed: () => setState(() => _showMore = !_showMore),
                  child: Text(_showMore ? '접기' : '펼치기'),
                )),
            Text('비워 두면 핵심 세 칸에서 계산해 채웁니다.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor)),
            if (_showMore) ...[
              const SizedBox(height: 12),
              for (final f in [..._derived, ..._composition]) _field(f),
            ],
          ]),
        ),
        FilledButton(onPressed: () => _save(app, profile), child: const Text('저장하기')),
      ]),
    );
  }

  Widget _field(_F f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _ctrl[f.key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: f.label,
          suffixText: f.unit.isEmpty ? null : f.unit,
          helperText: f.hint,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _save(app, Map<String, Object?> profile) {
    final s = _filled(profile);
    final before = app.store.sortedScans();
    final prevLatest = before.isEmpty ? null : before.last;

    app.store.addScan(s);
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 설정에서 사진을 지우고 다시 해 보세요');
      return;
    }

    /* **지난 기록을 채운 것이면 계획을 건드리지 않습니다.**
       추이를 채우려고 옛날 결과지를 넣었는데 계획이 통째로 바뀌면,
       사용자는 자기가 뭘 망가뜨렸는지 모릅니다. */
    final backfill = prevLatest != null &&
        core.jsTruthy(s['measuredAt']) &&
        '${s['measuredAt']}'.compareTo('${prevLatest['measuredAt']}') < 0;

    Navigator.of(context).pop();
    toast(context, backfill ? '지난 기록으로 저장했습니다 — 계획은 그대로입니다' : '저장했습니다');
  }
}
