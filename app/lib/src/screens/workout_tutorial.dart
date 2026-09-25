/* =============================================================================
 * workout_tutorial.dart — 헬스 화면 「따라 해 보기」 와 스와이프 힌트
 *
 * 헬스 화면의 길은 눈에 안 보입니다: 줄을 밀면 빠지고, 꾹 누르면 옮겨지고, 무게
 * 칩을 누르면 스테퍼가 뜹니다. 주인이 실기기에서 "제거가 없어 보인다" 고 했습니다
 * (3차 피드백 29) — 있었는데 못 찾은 것입니다. 글로 설명하는 대신 한 번 해 보게
 * 합니다(34-보강): 연습용 종목 줄 하나로 세트 → 무게 → 밀어 빼기 → 꾹 눌러 옮기기,
 * 네 단계. 단계마다 해내면 체크와 함께 다음으로, 넷째를 해내면 닫힙니다 — 글로 된
 * 안내 장은 없습니다(「종목 추가」 · 「종료」 는 실제 화면에 단추로 있습니다).
 * 「건너뛰기」 는 늘 있습니다.
 *
 *   · 연습 줄은 실제 줄(ExerciseRow)입니다 — 콜백만 연습용. 배운 줄과 실제 줄이
 *     달라 보이면 배운 것이 소용없습니다.
 *   · 실제 기록에는 아무것도 남기지 않습니다. 남기는 것은 settings 의
 *     gymTutorialSeen — 건너뛰어도 본 것입니다(다시 보려면 설정) — 과, 끝까지 한
 *     사람에게는 gymSwipeHintSeen(밀어 빼기를 이미 해 봤으니 힌트도 본 것). 둘 다
 *     [show] 가 적습니다 — 헬스 화면에서 열든 설정에서 열든 같아야 합니다.
 *   · SwipeHint 는 첫 줄이 살짝 밀렸다 돌아오는 그림 — 3단계와, 튜토리얼을 건너뛴
 *     사람의 실제 첫 줄에 한 번 씁니다. 그림만 움직이고 아무것도 빼지 않습니다.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../app_state.dart';
import '../scope.dart';
import '../ui/widgets.dart';
import '../workout/loads.dart';
import 'workout_session.dart';

/// settings 의 표 — 튜토리얼을 한 번 봤는가(건너뛴 것도 본 것).
const String kGymTutorialSeenKey = 'gymTutorialSeen';

/// settings 의 표 — 첫 줄 스와이프 힌트를 한 번 보여 줬는가(튜토리얼 완주도 본 것).
const String kGymSwipeHintSeenKey = 'gymSwipeHintSeen';

/// 화면 제목이자 설정 줄의 이름 — 같은 것에 이름이 둘이면 다른 것을 기대합니다.
const String kGymTutorialTitle = '헬스 화면 따라 해 보기';

/// 첫 줄이 살짝 밀렸다 돌아오는 힌트. [child] 를 감싸고 한 번만 움직입니다 —
/// 실제 제거는 하지 않습니다(Dismissible 은 바깥에 있고, 이건 그림만 옮깁니다).
/// 밀린 자리에는 밀어 뺄 때와 같은 빨간 띠와 휴지통이 비칩니다 — "저쪽으로 밀면
/// 저게 된다" 를 보여 주는 것이 이 그림의 전부입니다. 다 돌아오면 [onShown].
class SwipeHint extends StatefulWidget {
  const SwipeHint({
    super.key,
    required this.child,
    this.onShown,
    this.bottomGap = 0,
    this.delay = const Duration(milliseconds: 600),
  });

  final Widget child;
  final VoidCallback? onShown;
  /// 줄이 아래에 두는 여백 — 빨간 띠는 그 위까지만.
  final double bottomGap;
  /// 화면이 선 뒤 이만큼 기다렸다 움직입니다. 뜨자마자 움직이면 못 봅니다.
  final Duration delay;

  /// 밀리는 거리. 살짝 — 빼려는 게 아니라 알려 주는 것입니다.
  static const double distance = 48;
  /// 기다림 뒤 움직이는 시간(밀림 · 멈춤 · 돌아옴).
  static const Duration duration = Duration(milliseconds: 1100);

  @override
  State<SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<SwipeHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _dx;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.delay + SwipeHint.duration);
    final wait = widget.delay.inMilliseconds.toDouble();
    _dx = TweenSequence<double>([
      if (wait > 0) TweenSequenceItem(tween: ConstantTween(0), weight: wait),
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: -SwipeHint.distance).chain(CurveTween(curve: Curves.easeOut)),
          weight: 400),
      TweenSequenceItem(tween: ConstantTween(-SwipeHint.distance), weight: 200),
      TweenSequenceItem(
          tween: Tween(begin: -SwipeHint.distance, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 500),
    ]).animate(_c);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onShown?.call();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    return AnimatedBuilder(
      animation: _dx,
      child: widget.child,
      builder: (context, child) {
        final dx = _dx.value;
        return Stack(children: [
          if (dx < -1)
            Positioned(
              top: 0,
              bottom: widget.bottomGap,
              right: 0,
              width: -dx,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  color: c.badBg,
                  alignment: Alignment.center,
                  child: Icon(LucideIcons.trash2, size: 20, color: c.bad),
                ),
              ),
            ),
          Transform.translate(offset: Offset(dx, 0), child: child),
        ]);
      },
    );
  }
}

/// 튜토리얼 한 단계 — 제목 한 줄, 밑에 짧은 말 한 줄.
class _Step {
  const _Step(this.title, this.sub);
  final String title;
  final String sub;
}

const List<_Step> _steps = [
  _Step('「세트」 를 눌러 보세요', '줄 어디를 눌러도 한 세트 · 시간은 알아서 갑니다'),
  _Step('무게 칩을 눌러 보세요', '오늘 쓸 무게를 정합니다'),
  _Step('줄을 왼쪽으로 밀어 빼 보세요', '5초 안에 「되돌리기」 할 수 있습니다'),
  _Step('꾹 눌러 「다른 종목」 아래로 옮겨 보세요', '순서는 기록에도 그대로 남습니다'),
];

/// 헬스 화면 첫 진입의 「따라 해 보기」. 전체 화면으로 올라오고, 끝까지 하면 true,
/// 건너뛰면 false 로 닫힙니다. 여는 곳은 [show] — 닫히면 어느 쪽이든 본 것으로 적습니다.
class WorkoutTutorial extends StatefulWidget {
  const WorkoutTutorial({super.key});

  /// 한 번 봤는가(건너뛴 것도 본 것).
  static bool seen(Map<String, Object?> state) =>
      core.jsTruthy(((state['settings'] as Map?) ?? const {})[kGymTutorialSeenKey]);

  static void markSeen(AppState app) => _flag(app, kGymTutorialSeenKey);

  /// 첫 줄 스와이프 힌트를 봤는가.
  static bool swipeHintSeen(Map<String, Object?> state) =>
      core.jsTruthy(((state['settings'] as Map?) ?? const {})[kGymSwipeHintSeenKey]);

  static void markSwipeHintSeen(AppState app) => _flag(app, kGymSwipeHintSeenKey);

  static void _flag(AppState app, String key) {
    final settings = ((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>();
    if (core.jsTruthy(settings[key])) return;
    app.store.set({'settings': {...settings, key: true}});
  }

  /// 전체 화면으로 엽니다. 끝까지 했으면 true, 건너뛰었으면 false. 어느 쪽이든
  /// 본 것으로 적습니다 — 건너뛴 사람에게 다음에 또 올리면 그건 안내가 아니라 방해입니다.
  /// 끝까지 한 사람은 3단계에서 밀어 빼기를 해 봤으니 첫 줄 힌트도 본 것으로 — 여는 곳이
  /// 헬스 화면이든 설정이든 여기서 적어야 한쪽만 빠지지 않습니다.
  static Future<bool> show(BuildContext context) async {
    final app = Scope.of(context);
    final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const WorkoutTutorial()));
    markSeen(app);
    if (done == true) markSwipeHintSeen(app);
    return done == true;
  }

  @override
  State<WorkoutTutorial> createState() => _WorkoutTutorialState();
}

class _WorkoutTutorialState extends State<WorkoutTutorial> {
  int _step = 0;
  /// 이 단계를 해냈는가 — 체크가 뜨고 잠깐 뒤 다음 단계로.
  bool _done = false;
  Timer? _advance;
  /// 밀어 뺀 줄을 다음 단계에서 다시 세울 때 키가 달라야 합니다 — 같은 키면
  /// Dismissible 이 "이미 뺀 줄" 로 봅니다.
  int _epoch = 0;

  /// 연습 줄 — 머신 종목이라 무게 칩이 붙습니다(2단계). 이름과 메모가 "연습" 이라고
  /// 말하고, 기록에는 가지 않습니다.
  final GymExercise _ex = GymExercise(
    id: 'practice',
    name: '연습 종목',
    sets: 3,
    reps: '10-12',
    restSec: 60,
    equip: 'machine',
    note: '연습용 · 기록에 안 남습니다',
    load: const Load(kg: 20, step: 5, source: 'body', hint: '안 되면 5kg 씩 줄여 보세요'),
  );
  /// 4단계에서 자리를 바꿀 상대.
  final GymExercise _other = GymExercise(
    id: 'other',
    name: '다른 종목',
    sets: 3,
    reps: '10-15',
    restSec: 75,
    equip: 'dumbbell',
    load: const Load(kg: 8, step: 1, source: 'body', hint: ''),
  );
  late final List<GymExercise> _order = [_ex, _other];

  bool get _last => _step == _steps.length - 1;

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  /// 해냈습니다 — 체크를 보여 주고 잠깐 뒤 다음으로. 「다음」 을 또 누르게 하지 않습니다.
  /// 마지막 단계면 그 잠깐 뒤에 닫힙니다(true) — 「시작하기」 도 안내 장도 없습니다.
  void _complete() {
    if (_done) return;
    setState(() => _done = true);
    _advance?.cancel();
    _advance = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_last) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _step++;
        _done = false;
        _epoch++;
      });
    });
  }

  void _onSet(GymExercise e) {
    setState(() => e.done++);
    if (_step == 0) _complete();
  }

  void _onUndo(GymExercise e) {
    if (e.done > 0) setState(() => e.done--);
  }

  /// 실제 화면과 같은 스테퍼 시트 — 닫기만 해도 "칩을 누르면 이게 뜬다" 는 배웠습니다.
  Future<void> _onKg(GymExercise e) async {
    final r = await showKgStepper(context, e);
    if (!mounted) return;
    if (r != null) {
      setState(() {
        e.kg = r.kg;
        e.kgSet = true;
      });
    }
    if (_step == 1) _complete();
  }

  void _onReorder(int oldIndex, int newIndex) {
    final to = (newIndex > oldIndex ? newIndex - 1 : newIndex).clamp(0, _order.length - 1);
    if (to == oldIndex) return;
    setState(() => _order.insert(to, _order.removeAt(oldIndex)));
    if (_order.first.id != _ex.id) _complete();
  }

  ExerciseRow _row(GymExercise e) => ExerciseRow(
        ex: e,
        onSet: () => _onSet(e),
        onUndo: () => _onUndo(e),
        onKg: () => _onKg(e),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = mb(context);
    final step = _steps[_step];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(kGymTutorialTitle),
        actions: [
          TextButton(
            key: const ValueKey('tut-skip'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('건너뛰기'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (var i = 0; i < _steps.length; i++)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _step || (i == _step && _done)
                          ? c.ok
                          : (i == _step ? t.colorScheme.primary : null),
                      border: Border.all(
                          color: i < _step || (i == _step && _done)
                              ? c.ok
                              : (i == _step ? t.colorScheme.primary : t.hintColor),
                          width: 1.5),
                    ),
                  ),
                const Spacer(),
                Text('${_step + 1}/${_steps.length}',
                    key: const ValueKey('tut-step'),
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(step.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (_done)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(LucideIcons.checkCircle2, key: const ValueKey('tut-check'), color: c.ok),
                  ),
              ]),
              if (step.sub.isNotEmpty)
                Text(step.sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
            ]),
          ),
          Expanded(child: _practice(context)),
        ]),
      ),
    );
  }

  static const _pad = EdgeInsets.fromLTRB(16, 4, 16, 24);

  Widget _practice(BuildContext context) {
    final c = mb(context);
    switch (_step) {
      case 0:
      case 1:
        return ListView(padding: _pad, children: [_row(_ex)]);
      case 2:
        if (_done) {
          return ListView(padding: _pad, children: const [
            Note(tone: Tone.ok, text: '뺐습니다 — 실제 화면에선 「되돌리기」 가 5초 뜹니다'),
          ]);
        }
        return ListView(padding: _pad, children: [
          Dismissible(
            key: ValueKey('tut-dismiss-$_epoch'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _complete(),
            background: Container(
              alignment: Alignment.centerRight,
              margin: const EdgeInsets.only(bottom: ExerciseRow.gap),
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(color: c.badBg, borderRadius: BorderRadius.circular(14)),
              child: Icon(LucideIcons.trash2, color: c.bad),
            ),
            child: SwipeHint(bottomGap: ExerciseRow.gap, child: _row(_ex)),
          ),
        ]);
      default:
        /* 끌기 장식은 실제 화면과 같은 gymDragProxy — 기본 장식(각진 Material 그림자)이면
           배우는 줄이 실제 줄과 달라 보입니다. */
        return ReorderableListView.builder(
          padding: _pad,
          buildDefaultDragHandles: false,
          proxyDecorator: gymDragProxy,
          itemCount: _order.length,
          onReorder: _onReorder,
          itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
            key: ValueKey('tut-order-${_order[i].id}'),
            index: i,
            child: _row(_order[i]),
          ),
        );
    }
  }
}
