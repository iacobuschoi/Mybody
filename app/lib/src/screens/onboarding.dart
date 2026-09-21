/* =============================================================================
 * onboarding.dart — P01 첫 화면
 *
 * **이 화면을 건너뛸 수 없는 이유가 있습니다.**
 *
 * 프로필이 없으면 앱은 씨앗 프로필(주인의 몸: 187cm · 22세 · 남성)로
 * 계산합니다. 웹 앱도 같은 대체값을 쓰는데, 거기서는 온보딩을 먼저
 * 통과해야 해서 실제로는 안 쓰입니다.
 *
 * 그 대체값이 실제로 쓰이면 기초대사량이 통째로 틀립니다 — 키 155cm 인
 * 사람에게 187cm 기준 TDEE 로 만든 식단이 나갑니다. 숫자는 그럴듯하고,
 * 틀렸다는 표시는 어디에도 없습니다.
 *
 * 그래서 셸이 이 화면을 먼저 세웁니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  String _sex = 'male';
  final _height = TextEditingController();
  final _age = TextEditingController();
  String _activity = 'moderate';
  String _trainingAge = 'novice';
  int _days = 4;
  int _sessionMin = 60;
  int _meals = 3;
  bool _accepted = false;

  @override
  void dispose() {
    _height.dispose();
    _age.dispose();
    super.dispose();
  }

  bool get _basicsOk {
    final h = double.tryParse(_height.text.trim());
    final a = double.tryParse(_age.text.trim());
    return h != null && h >= 100 && h <= 230 && a != null && a >= 10 && a <= 100;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const titles = [
      ('기본 정보', '칼로리 계산의 기준이 되는 값입니다'),
      ('활동 · 운동', '실제로 지킬 수 있는 선에서 고르세요'),
      ('시작하기 전에', '무엇이 어디에 저장되는지 먼저 읽어 주세요'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${_step + 1}/3 · ${titles[_step].$1}'),
        automaticallyImplyLeading: false,
        leading: _step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step--),
              ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        LinearProgressIndicator(value: (_step + 1) / 3, minHeight: 3),
        const SizedBox(height: 14),
        Text(titles[_step].$2,
            style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
        const SizedBox(height: 14),
        if (_step == 0) _basics(),
        if (_step == 1) _training(),
        if (_step == 2) _consent(),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _canGo() ? _next : null,
            child: Text(_step == 2 ? '시작하기' : '다음'),
          ),
        ),
      ),
    );
  }

  bool _canGo() => switch (_step) {
        0 => _basicsOk,
        1 => true,
        _ => _accepted,
      };

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    final app = Scope.of(context);
    app.store.set({
      'profile': {
        'sex': _sex,
        'heightCm': double.tryParse(_height.text.trim()),
        'age': double.tryParse(_age.text.trim()),
        'activityLevel': _activity,
        'trainingAge': _trainingAge,
        'daysPerWeek': _days,
        'sessionMinutes': _sessionMin,
        'mealsPerDay': _meals,
        'hadPriorPeak': false,
      },
      'onboarded': true,
      'disclaimerAccepted': true,
    });
    if (!app.store.saved()) {
      toast(context, '기기에 저장하지 못했습니다 — 넣은 값이 남지 않습니다');
    }
  }

  Widget _basics() => MbCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'male', label: Text('남성')),
              ButtonSegment(value: 'female', label: Text('여성')),
            ],
            selected: {_sex},
            onSelectionChanged: (s) => setState(() => _sex = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            /* 성별은 꾸밈이 아니라 계산에 들어갑니다 — 왜 묻는지 말합니다. */
            '성별은 기초대사량과 안전 하한(필수 체지방)에 들어갑니다.',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: Theme.of(context).hintColor, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _height,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: '키', suffixText: 'cm', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _age,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: '나이', suffixText: '세', border: OutlineInputBorder(),
                helperText: '근성장 속도가 나이에 따라 달라집니다'),
          ),
        ]),
      );

  Widget _training() => Column(children: [
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('하루 활동량'),
            RadioGroup<String>(
              groupValue: _activity,
              onChanged: (v) => setState(() => _activity = v ?? _activity),
              child: Column(children: [
                for (final e in core.kPal.entries)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: e.key,
                    title: Text(e.value.label, style: Theme.of(context).textTheme.bodySmall),
                  ),
              ]),
            ),
          ]),
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('운동 경력'),
            Text('주 2회 이상 저항운동을 이어 온 기간입니다. 모르겠으면 짧은 쪽을 고르세요 — '
                '앱이 더 보수적으로 잡습니다.',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).hintColor, height: 1.5)),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _trainingAge,
              onChanged: (v) => setState(() => _trainingAge = v ?? _trainingAge),
              child: Column(children: [
                for (final e in core.kMuscleBase.entries)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: e.key,
                    title: Text(e.value.label, style: Theme.of(context).textTheme.bodySmall),
                  ),
              ]),
            ),
          ]),
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('주당 운동'),
            Text('주 $_days일 · 회당 $_sessionMin분',
                style: Theme.of(context).textTheme.bodySmall),
            Slider(
              value: _days.toDouble(), min: 0, max: 7, divisions: 7,
              label: '$_days일',
              onChanged: (v) => setState(() => _days = v.round()),
            ),
            Wrap(spacing: 8, children: [
              for (final m in [30, 45, 60, 90])
                ChoiceChip(
                  label: Text('$m분'),
                  selected: _sessionMin == m,
                  onSelected: (_) => setState(() => _sessionMin = m),
                ),
            ]),
            const SizedBox(height: 14),
            const SectionTitle('하루 몇 끼'),
            Wrap(spacing: 8, children: [
              for (final m in [2, 3, 4])
                ChoiceChip(
                  label: Text('$m끼'),
                  selected: _meals == m,
                  onSelected: (_) => setState(() => _meals = m),
                ),
            ]),
          ]),
        ),
      ]);

  Widget _consent() => Column(children: [
        const Note(
          tone: Tone.warn,
          title: '이 앱은 의료기기가 아닙니다.',
          text: ' 진단·치료·예방을 목적으로 하지 않으며, 제공되는 운동·식단은 '
              '일반적인 정보입니다.',
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final line in const [
              '기저질환, 임신·수유 중, 섭식장애 이력이 있다면 반드시 전문가와 상의하세요.',
              '인바디(생체전기임피던스)는 수분 상태에 민감해 하루 중에도 값이 흔들립니다. '
                  '오차보다 작은 변화에는 이 앱이 달성률을 붙이지 않습니다.',
              '측정 기록·목표·계획·식단은 **이 기기에만** 저장됩니다. 서버로 올라가지 않습니다.',
              '로그인은 친구 기능에만 씁니다. 친구에게 무엇이 보일지는 친구마다 따로 켭니다 — '
                  '기본은 전부 꺼져 있고 운동 체크만 보입니다.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('· $line',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6)),
              ),
          ]),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _accepted,
          onChanged: (v) => setState(() => _accepted = v ?? false),
          title: const Text('읽었고 이해했습니다'),
        ),
      ]);
}
