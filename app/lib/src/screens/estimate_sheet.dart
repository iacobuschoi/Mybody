/* =============================================================================
 * estimate_sheet.dart — 「인바디 없이 시작」 시트 (키·체중으로 추정)
 *
 * 주인: "인바디 사진 없으면 샘플 데이터로 시작해보기 만들어서 키/체중만으로
 * 추정하고 나중에 제대로된 사진 넣으면 업데이트되는거로 하자".
 *
 * 인바디가 없는 사람에게 이 앱은 지금까지 빈 화면이었습니다 — "결과지를
 * 올려 주세요" 뒤에 아무것도 없었습니다. 체육관에 인바디가 없거나 아직 잴
 * 날이 안 된 사람은 거기서 앱을 닫습니다. 이 시트가 그 사람의 첫 걸음입니다.
 *
 * **왜 체중 한 칸인가.** 성별 · 나이 · 키는 온보딩에서 이미 받았습니다.
 * 같은 것을 또 물으면 탭만 늘고, 사람은 "아까 넣었는데?" 하고 앱을 의심합니다.
 * 그래서 셋은 한 줄(「남성 · 22세 · 187cm」)로 보여 주고 「바꾸기」 를 둡니다.
 * 프로필에 빈 칸이 있을 때만(예전 판에서 온 사람 · 백업만 가져온 사람) 그
 * 칸들을 펼쳐 둔 채로 묻습니다 — 없는 값으로 추정할 수는 없습니다.
 * 체중은 추정이 아니라 **저울로 잰 진짜 값**이라 늘 사람이 넣습니다.
 *
 * **왜 저장 전에 미리 보여 주는가.** 저장하고 나서 홈에 숫자가 뜨면 사람은
 * 그 숫자를 결과지처럼 믿습니다. 저장 버튼 위에 「추정」 알약과 숫자,
 * 오차(체지방률 ±5%p · 골격근 ±3kg)를 먼저 보여 주면, 누르는 순간 이미
 * "이건 추정이다" 를 알고 누릅니다. 추정이라는 걸 숨기지 않는 것이 이
 * 기능의 조건입니다.
 *
 * **왜 곧장 목표 화면인가.** 시작하는 이유는 계획입니다 — 숫자를 보려고
 * 추정하는 사람은 없습니다. 홈으로 돌아가 「목표 정하기」 를 한 번 더
 * 누르게 하면 탭이 하나 늘 뿐입니다. 그래서 이 시트는 true 만 돌려주고,
 * 부른 쪽(홈 · 업로드)이 목표 화면을 엽니다. 그 뒤 흐름은 실측과 같습니다.
 *
 * 계산(Gallagher 2000 · Lee 2000, 아시아인 항)과 저장 규칙은 estimate.dart
 * 에 있습니다. 여기는 입력과 미리보기만 합니다. 인바디를 넣으면 추정은
 * 지워지고 계획이 실측으로 다시 세워집니다(estimate_upgrade.dart).
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../estimate.dart';
import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';

/// 시트를 띄웁니다. 추정을 저장했으면 true — 부른 쪽이 목표 화면으로 갑니다.
Future<bool> showEstimateSheet(BuildContext context) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    /* 키보드가 올라오면 시트가 그만큼 커져야 저장 버튼이 키보드 위에 남습니다. */
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const EstimateSheet(),
  );
  return r == true;
}

class EstimateSheet extends StatefulWidget {
  const EstimateSheet({super.key});

  @override
  State<EstimateSheet> createState() => _EstimateSheetState();
}

class _EstimateSheetState extends State<EstimateSheet> {
  String? _sex;
  final _height = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _ageFocus = FocusNode(debugLabel: 'estimate-age');
  final _weightFocus = FocusNode(debugLabel: 'estimate-weight');

  /// 기본 정보(성별 · 나이 · 키) 칸을 펼쳤는가. 프로필에 빈 칸이 있으면 처음부터 펼칩니다.
  bool _editing = false;

  /// 처음 열 때 기본 정보가 다 있었는가 — 그러면 체중 칸에 바로 커서를 둡니다.
  bool _basicsAtOpen = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    /* 온보딩이 넣어 둔 값으로 채웁니다. 나이 · 키는 double 로 적혀 있을 수
       있어(22.0) 엔진과 같은 글자 바꾸기(jsNumToString)로 '22' 로 보입니다. */
    final p = Scope.of(context).profile ?? const <String, Object?>{};
    final sex = p['sex'];
    if (sex == 'male' || sex == 'female') _sex = sex as String;
    final h = p['heightCm'], a = p['age'];
    if (h is num && h.isFinite) _height.text = core.jsNumToString(h);
    if (a is num && a.isFinite) _age.text = core.jsNumToString(a);
    _basicsAtOpen = _basicsOk;
    _editing = !_basicsAtOpen;
  }

  @override
  void dispose() {
    _height.dispose();
    _age.dispose();
    _weight.dispose();
    _ageFocus.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim());

  /* 온보딩과 같은 범위 — 키 100~230cm · 나이 10~100세. */
  bool get _basicsOk {
    final h = _num(_height), a = _num(_age);
    return (_sex == 'male' || _sex == 'female') &&
        h != null && h >= 100 && h <= 230 &&
        a != null && a >= 10 && a <= 100;
  }

  /// 지금 칸들로 낸 추정. 칸이 비었거나 범위를 벗어나면 null — 저장 버튼이 꺼집니다.
  Map<String, Object?>? get _comp {
    final w = _num(_weight);
    if (!_basicsOk || w == null) return null;
    return estimateComposition(
        sex: _sex, age: _num(_age)!, heightCm: _num(_height)!, weightKg: w);
  }

  void _save() {
    if (_comp == null) return;
    final app = Scope.of(context);
    final r = saveEstimate(app.store,
        sex: _sex!, age: _num(_age)!, heightCm: _num(_height)!, weightKg: _num(_weight)!);
    /* **저장이 실패했는데 넘어가지 않습니다.** 목표 화면이 추정 없이 열리면
       "현재" 가 비어 있고, 사람은 방금 넣은 체중이 어디 갔는지 모릅니다. */
    if (r == null) {
      toast(context, '기기에 저장하지 못했습니다 — 넣은 값이 남지 않습니다');
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hint = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5);
    final comp = _comp;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('키·체중으로 시작',
                style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(kEstimateHint, style: hint),
            const SizedBox(height: 14),
            if (!_editing && _basicsOk)
              /* 온보딩에서 받은 셋은 한 줄로만 — 또 묻지 않습니다. */
              Row(key: const ValueKey('estimate-basics'), children: [
                Expanded(
                  child: Text(
                      '${_sex == 'female' ? '여성' : '남성'} · '
                      '${core.jsNumToString(_num(_age)!)}세 · '
                      '${core.jsNumToString(_num(_height)!)}cm',
                      style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () => setState(() => _editing = true),
                  child: const Text('바꾸기'),
                ),
              ])
            else ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'male', label: Text('남성')),
                  ButtonSegment(value: 'female', label: Text('여성')),
                ],
                /* 프로필에 성별이 없으면 아무것도 안 고른 채로 — 남성으로 미리
                   골라 두면 안 고른 여성이 남성 식으로 추정됩니다. */
                emptySelectionAllowed: true,
                selected: {if (_sex != null) _sex!},
                onSelectionChanged: (s) => setState(() => _sex = s.isEmpty ? _sex : s.first),
              ),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('estimate-height'),
                    controller: _height,
                    keyboardType: TextInputType.number,
                    /* 「다음」 은 나이 칸으로 — 온보딩과 같은 순서입니다. */
                    textInputAction: TextInputAction.next,
                    onEditingComplete: () => _ageFocus.requestFocus(),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: '키', suffixText: 'cm', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('estimate-age'),
                    controller: _age,
                    focusNode: _ageFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onEditingComplete: () => _weightFocus.requestFocus(),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: '나이', suffixText: '세', border: OutlineInputBorder()),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('estimate-weight'),
              controller: _weight,
              focusNode: _weightFocus,
              /* 기본 정보가 다 있으면 넣을 것은 이 칸 하나 — 커서를 바로 둡니다. */
              autofocus: _basicsAtOpen,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (_comp != null) _save();
              },
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: '체중', suffixText: 'kg', border: OutlineInputBorder()),
            ),
            /* 저장 전에 무엇이 저장될지 — 「추정」 과 오차를 같이. */
            if (comp != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Pill('추정', tone: Tone.warn),
                  Text('골격근 ${n1(comp['smmKg'])}kg · 체지방률 ${n1(comp['pbfPct'])}%',
                      style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              Text(kEstimateCaveat,
                  style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('estimate-save'),
              onPressed: comp == null ? null : _save,
              child: const Text('추정치로 시작'),
            ),
          ],
        ),
      ),
    );
  }
}
