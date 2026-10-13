/* =============================================================================
 * workout_voice.dart — 헬스 화면의 「누르고 말하기」
 *
 * 책상 비서의 누르고 말하기와 같은 손짓입니다: **꾹 누른 채** 「벤치 80키로 4개」, 떼면
 * 받아쓴 글을 풀어(workout/voice_set.dart) **확인 시트**에 보여 주고, 「기록」 을 눌러야
 * 세트가 올라갑니다. 받아쓰기는 틀립니다 — 그래서 저장 전에 늘 한 번 보여 줍니다.
 *
 *   · 짧게 누르면 **글로 넣는 칸**입니다. 마이크가 없는 곳(웹 · 권한 거절 · 시끄러운 헬스장)
 *     의 길이고, 시험이 같은 길로 받아쓴 글을 넣습니다. 확인 시트의 「글로 고치기」 도 여기로.
 *   · 받아쓰기는 speech_to_text(안드로이드 SpeechRecognizer · iOS SFSpeechRecognizer) —
 *     기기의 한국어 인식을 씁니다. 서버로 가는 것은 없습니다. 첫 누름에 마이크 권한을 묻습니다.
 *   · 떼는 순간 stop() 을 부르고 최종 결과를 잠깐(1.5초) 기다립니다. 안 오면 마지막 중간
 *     결과를 씁니다 — 안드로이드는 stop 뒤에 최종 결과가 늦게 오거나 안 올 때가 있습니다.
 *   · [VoiceSetButton.speechFactory] 는 시험이 가짜 인식기를 꽂는 구멍입니다.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../ui/widgets.dart';
import '../workout/exercises.dart';
import '../workout/loads.dart';
import '../workout/voice_set.dart';

/* ---------------------------------------------------------------------------
 * 받아쓰기 — 플러그인을 얇게 감쌉니다(시험이 바꿔 끼울 수 있게).
 * ------------------------------------------------------------------------ */

abstract class SpeechInput {
  /// 준비(권한 포함). false 면 이 기기에서 못 씁니다.
  Future<bool> init();
  /// 듣기 시작. [onResult] 는 중간 · 최종 결과마다. [onEnd] 는 **기기 쪽이 먼저 끝냈을 때**
  /// (시간 초과 · 오류 · 소리 없음) — 손을 떼기 전에 끝나면 단추가 「듣는 중」 에 갇히지 않게.
  Future<void> start(void Function(String text, bool isFinal) onResult, {void Function(String? error)? onEnd});
  /// 듣기 끝 — 최종 결과가 뒤따라 올 수 있습니다.
  Future<void> stop();
  Future<void> cancel();
  bool get listening;
}

class PluginSpeechInput implements SpeechInput {
  final _stt = stt.SpeechToText();
  bool _ready = false;
  String? _lastError;
  void Function(String? error)? _onEnd;

  String? get lastError => _lastError;

  @override
  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onError: (e) {
          _lastError = e.errorMsg;
          /* 에뮬레이터 · 조용한 방에서는 error_no_match · error_speech_timeout 이 바로 옵니다 —
             그러면 플러그인은 이미 멈춘 것이고, 화면도 같이 멈춰야 합니다. */
          final cb = _onEnd;
          _onEnd = null;
          cb?.call(e.errorMsg);
        },
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            final cb = _onEnd;
            _onEnd = null;
            cb?.call(null);
          }
        },
        finalTimeout: const Duration(milliseconds: 1500),
      );
    } catch (e) {
      _lastError = '$e';
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<void> start(void Function(String text, bool isFinal) onResult, {void Function(String? error)? onEnd}) {
    _onEnd = onEnd;
    return _stt.listen(
        onResult: (r) => onResult(r.recognizedWords, r.finalResult),
        listenOptions: stt.SpeechListenOptions(
          localeId: 'ko_KR',
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          /* 손을 떼기 전에 저절로 끝나지 않게 — 숨 고르는 사이(2~3초)에 끊기면 「80키로」 까지만 남습니다. */
          pauseFor: const Duration(seconds: 8),
          listenFor: const Duration(seconds: 30),
        ),
      );
  }

  @override
  Future<void> stop() {
    _onEnd = null;   // 우리가 멈추는 것 — 뒤따르는 'done' 은 알릴 필요 없습니다
    return _stt.stop();
  }

  @override
  Future<void> cancel() {
    _onEnd = null;
    return _stt.cancel();
  }

  @override
  bool get listening => _stt.isListening;
}

/* ---------------------------------------------------------------------------
 * 단추
 * ------------------------------------------------------------------------ */

/// 누르고 말하기 단추. 꾹 누르면 듣고, 떼면 [onText] 에 받아쓴 글. 짧게 누르면 글로 넣는 칸.
class VoiceSetButton extends StatefulWidget {
  const VoiceSetButton({super.key, required this.onText});

  /// 받아쓴(또는 글로 넣은) 글 — 화면이 풀어서 확인 시트를 띄웁니다.
  final Future<void> Function(String text) onText;

  /// 시험이 가짜 인식기를 꽂는 구멍. null 이면 플러그인.
  static SpeechInput Function()? speechFactory;

  @override
  State<VoiceSetButton> createState() => _VoiceSetButtonState();
}

class _VoiceSetButtonState extends State<VoiceSetButton> {
  SpeechInput? _speech;
  bool _listening = false;
  bool _busy = false;
  /// 손가락이 지금 눌려 있는가. 권한 창이 뜨는 동안 손을 떼면 — 돌아와서 듣기를 시작하면 안 됩니다
  /// (실기기 시험에서 그렇게 「듣는 중」 에 갇혔습니다).
  bool _held = false;
  String _partial = '';
  Completer<String>? _final;

  SpeechInput get speech => _speech ??= (VoiceSetButton.speechFactory?.call() ?? PluginSpeechInput());

  @override
  void dispose() {
    if (_listening) _speech?.cancel();
    super.dispose();
  }

  Future<void> _typed([String initial = '']) async {
    final text = await showTypedSetSheet(context, initial: initial);
    if (text == null || text.trim().isEmpty || !mounted) return;
    await widget.onText(text.trim());
  }

  Future<void> _begin() async {
    _held = true;
    if (_busy || _listening) return;
    _busy = true;
    final ok = await speech.init();
    _busy = false;
    if (!mounted) return;
    if (!ok) {
      final why = _speech is PluginSpeechInput ? (_speech as PluginSpeechInput).lastError : null;
      toast(context, '이 기기에서 음성 인식을 쓸 수 없어요${why == null ? '' : ' ($why)'} — 글로 넣어 주세요');
      await _typed();
      return;
    }
    /* 권한 창이 뜨는 사이 손을 뗐으면 여기서 끝 — 다음 누름부터 바로 듣습니다. */
    if (!_held) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _listening = true;
      _partial = '';
      _final = Completer<String>();
    });
    await speech.start(
      (text, isFinal) {
        if (!mounted) return;
        setState(() => _partial = text);
        if (isFinal && _final != null && !_final!.isCompleted) _final!.complete(text);
      },
      onEnd: (error) {
        /* 기기가 먼저 끝냈습니다(시간 초과 · 소리 없음 · 오류). 손이 아직 눌려 있어도 더 들을 수 없으니
           지금까지 들은 것으로 마무리합니다. */
        if (!mounted || !_listening) return;
        _finish(stopPlugin: false, error: error);
      },
    );
  }

  Future<void> _end({bool cancelled = false}) async {
    _held = false;
    if (!_listening) return;
    if (cancelled) {
      setState(() => _listening = false);
      await speech.cancel();
      return;
    }
    await _finish(stopPlugin: true);
  }

  /// 듣기를 마치고 글을 넘깁니다. [stopPlugin] 은 우리가 멈추는 경우(손을 뗌) — 기기가 먼저 끝낸
  /// 경우는 false. 최종 결과를 잠깐 기다리고, 안 오면 마지막 중간 결과를 씁니다.
  Future<void> _finish({required bool stopPlugin, String? error}) async {
    final waiter = _final;
    setState(() => _listening = false);
    if (stopPlugin) {
      await speech.stop();
      HapticFeedback.lightImpact();
    }
    var text = _partial;
    if (waiter != null && error == null) {
      try {
        text = await waiter.future.timeout(const Duration(milliseconds: 1500));
      } on TimeoutException {
        text = _partial;
      }
    }
    if (!mounted) return;
    if (text.trim().isEmpty) {
      final why = switch (error) {
        null => '',
        'error_no_match' || 'error_speech_timeout' => ' (말소리를 못 찾았어요)',
        'error_audio' || 'error_audio_error' => ' (마이크를 못 열었어요)',
        'error_network' || 'error_network_timeout' => ' (음성 인식에 인터넷이 필요해요)',
        'error_permission' || 'error_insufficient_permissions' => ' (마이크 권한이 없어요)',
        _ => ' ($error)',
      };
      toast(context, '못 들었어요$why — 꾹 누른 채 말하고 떼 주세요. 짧게 누르면 글로 넣습니다');
      return;
    }
    await widget.onText(text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final on = _listening;
    final bg = on ? t.colorScheme.error : t.colorScheme.primary;
    final fg = on ? t.colorScheme.onError : t.colorScheme.onPrimary;
    return Semantics(
      button: true,
      label: '누르고 말하기 — 꾹 누른 채 「벤치 80키로 4개」',
      child: GestureDetector(
        onTap: _listening ? null : () => _typed(),
        onLongPressStart: (_) => _begin(),
        onLongPressEnd: (_) => _end(),
        onLongPressCancel: () => _end(cancelled: true),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 32 - 130),
          padding: EdgeInsets.symmetric(horizontal: on ? 14 : 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(22),
            boxShadow: on ? [BoxShadow(color: bg.withValues(alpha: 0.35), blurRadius: 14, spreadRadius: 2)] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? LucideIcons.mic : LucideIcons.mic, size: 20, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                on ? (_partial.isEmpty ? '듣는 중…' : _partial) : '꾹 누르고 말하기',
                key: const ValueKey('voice-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/* ---------------------------------------------------------------------------
 * 글로 넣기
 * ------------------------------------------------------------------------ */

/// 「벤치 80키로 4개」 를 글로. 답은 글 — null 은 닫은 것.
Future<String?> showTypedSetSheet(BuildContext context, {String initial = ''}) {
  final ctl = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final t = Theme.of(ctx);
      return _VoiceSheet(children: [
        Text('말하듯이 적어 주세요', style: t.textTheme.titleMedium),
        Text('종목 · 무게 · 횟수 — 순서는 상관없고 「80 5」 처럼 단위를 빼도 됩니다',
            style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('voice-typed'),
          controller: ctl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v),
          decoration: const InputDecoration(
            hintText: '예: 벤치 80키로 4개 · 스쿼트 100 5개씩 3세트',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: FilledButton(
            key: const ValueKey('voice-typed-ok'),
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('풀어 보기'),
          ),
        ),
      ]);
    },
  ).whenComplete(() => Future<void>.delayed(const Duration(milliseconds: 400), ctl.dispose));
}

/* ---------------------------------------------------------------------------
 * 확인 시트
 * ------------------------------------------------------------------------ */

/// 확인 시트의 답. [sets] 가 있으면 기록, [retypeText] 가 있으면 그 글로 다시 풀기. 둘 다 없으면 취소.
class SpokenConfirm {
  const SpokenConfirm({this.sets, this.retypeText});
  final List<SpokenSet>? sets;
  final String? retypeText;
}

/// 「이렇게 들었어요」 — 세트마다 종목(눌러서 바꾸기) · 무게 · 횟수 · 세트 수. 종목을 못 찾은 줄은
/// 「종목 고르기」 가 켜져 있고, 다 정해질 때까지 「기록」 이 꺼져 있습니다.
Future<SpokenConfirm?> showSpokenConfirm(
  BuildContext context,
  SpokenEntry entry, {
  required Future<Exercise?> Function() pickOther,
}) {
  /* 사본 — 시트에서 고친 것이 닫을 때 버려질 수 있어야 합니다. */
  final sets = [
    for (final s in entry.sets)
      SpokenSet(exercise: s.exercise, spokenName: s.spokenName, kg: s.kg, reps: s.reps, count: s.count),
  ];
  if (sets.isEmpty) sets.add(SpokenSet(spokenName: entry.transcript));
  return showModalBottomSheet<SpokenConfirm>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final t = Theme.of(ctx);
      final c = mb(ctx);
      final ready = sets.isNotEmpty && sets.every((s) => s.exercise != null);
      final heardNothing = entry.empty;
      return _VoiceSheet(children: [
        Row(children: [
          Icon(LucideIcons.mic, size: 18, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(heardNothing ? '잘 못 알아들었어요' : '이렇게 들었어요', style: t.textTheme.titleMedium)),
        ]),
        const SizedBox(height: 4),
        Text('"${entry.transcript}"',
            key: const ValueKey('voice-transcript'),
            style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, fontStyle: FontStyle.italic)),
        if (heardNothing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('종목 · 무게 · 횟수를 「벤치 80키로 4개」 처럼 말해 주세요. 아래에서 직접 고를 수도 있습니다.',
                style: t.textTheme.bodySmall?.copyWith(height: 1.5)),
          ),
        const SizedBox(height: 12),
        for (var i = 0; i < sets.length; i++) ...[
          _SpokenSetCard(
            key: ValueKey('spoken-$i'),
            index: i,
            set: sets[i],
            onChanged: () => setSheet(() {}),
            onPick: () async {
              final e = await pickOther();
              if (e != null) setSheet(() => sets[i].exercise = e);
            },
            onRemove: sets.length > 1 ? () => setSheet(() => sets.removeAt(i)) : null,
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('spoken-add'),
            onPressed: () => setSheet(() => sets.add(SpokenSet(
                exercise: sets.isNotEmpty ? sets.last.exercise : null,
                kg: sets.isNotEmpty ? sets.last.kg : null,
                reps: sets.isNotEmpty ? sets.last.reps : null))),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('세트 줄 더하기'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: const ValueKey('spoken-ok'),
            onPressed: ready ? () => Navigator.pop(ctx, SpokenConfirm(sets: sets)) : null,
            icon: const Icon(LucideIcons.check, size: 18),
            label: Text(ready ? '${sets.fold<int>(0, (a, s) => a + s.count)}세트 기록' : '종목을 골라 주세요'),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(
            key: const ValueKey('spoken-retype'),
            onPressed: () async {
              final text = await showTypedSetSheet(ctx, initial: entry.transcript);
              if (text != null && text.trim().isNotEmpty && ctx.mounted) {
                Navigator.pop(ctx, SpokenConfirm(retypeText: text.trim()));
              }
            },
            child: const Text('글로 고치기'),
          ),
          TextButton(
            key: const ValueKey('spoken-cancel'),
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: TextStyle(color: c.bad)),
          ),
        ]),
      ]);
    }),
  );
}

/// 세트 한 줄 — 종목 단추 · 무게 − + · 횟수 − + · 세트 수.
class _SpokenSetCard extends StatelessWidget {
  const _SpokenSetCard({
    super.key,
    required this.index,
    required this.set,
    required this.onChanged,
    required this.onPick,
    this.onRemove,
  });
  final int index;
  final SpokenSet set;
  final VoidCallback onChanged;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = set.exercise;
    final weighted = e == null || !(e.equip == 'bodyweight' || e.equip == 'band');
    final step = e == null ? 2.5 : (stepFor(e.equip, set.kg ?? 20) > 0 ? stepFor(e.equip, set.kg ?? 20) : 2.5);
    Widget counter({
      required Key key,
      required String label,
      required String value,
      required VoidCallback? onMinus,
      required VoidCallback onPlus,
    }) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _Tiny(icon: LucideIcons.minus, onTap: onMinus),
            SizedBox(
              width: 68,
              child: Text(value,
                  key: key,
                  textAlign: TextAlign.center,
                  style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            _Tiny(icon: LucideIcons.plus, onTap: onPlus),
          ]),
        ]);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              key: ValueKey('spoken-pick-$index'),
              onTap: onPick,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Flexible(
                    child: Text(
                      e?.name ?? (set.spokenName.isEmpty ? '종목 고르기' : '"${set.spokenName}" — 종목 고르기'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, color: e == null ? t.colorScheme.primary : null),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.chevronDown, size: 16, color: t.hintColor),
                ]),
              ),
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: '이 줄 빼기',
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              icon: Icon(LucideIcons.x, size: 18, color: t.hintColor),
            ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 8, children: [
          if (weighted)
            counter(
              key: ValueKey('spoken-kg-$index'),
              label: '무게',
              value: set.kg == null ? '맨몸' : '${SpokenSet.kgText(set.kg!)}kg',
              onMinus: set.kg == null
                  ? null
                  : () {
                      final n = set.kg! - step;
                      set.kg = n <= 0 ? null : n;
                      onChanged();
                    },
              onPlus: () {
                set.kg = (set.kg ?? 0) + step;
                onChanged();
              },
            ),
          counter(
            key: ValueKey('spoken-reps-$index'),
            label: '횟수',
            value: set.reps == null ? '—' : '${set.reps}회',
            onMinus: set.reps == null
                ? null
                : () {
                    final n = set.reps! - 1;
                    set.reps = n <= 0 ? null : n;
                    onChanged();
                  },
            onPlus: () {
              set.reps = (set.reps ?? 0) + 1;
              onChanged();
            },
          ),
          counter(
            key: ValueKey('spoken-count-$index'),
            label: '세트 수',
            value: '${set.count}',
            onMinus: set.count <= 1
                ? null
                : () {
                    set.count--;
                    onChanged();
                  },
            onPlus: () {
              if (set.count < 20) set.count++;
              onChanged();
            },
          ),
        ]),
      ]),
    );
  }
}

class _Tiny extends StatelessWidget {
  const _Tiny({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        onPressed: onTap,
        style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            fixedSize: const Size(32, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        icon: Icon(icon, size: 16),
      );
}

class _VoiceSheet extends StatelessWidget {
  const _VoiceSheet({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}
