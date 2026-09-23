/* =============================================================================
 * settings.dart — P12 설정 · P14 계정
 *
 * 여기서 조심하는 것 둘:
 *
 *  1. **"전부 지울까요?" 는 사진까지 지웁니다.** 결과지 사진에는 보통
 *     이름·나이·성별이 같이 인쇄돼 있습니다. 전부 지웠다고 믿고 폰을
 *     넘긴 사람에게는 그게 전부입니다.
 *
 *  2. **계정을 지워도 이 기기의 측정 기록은 안 지워집니다.** 그걸 숨기지
 *     않고 말하고, 지우는 길도 같이 놓습니다. 몸 숫자는 서버에 올라가지
 *     않으므로 계정 삭제로는 사라지지 않습니다 — 두 개는 다른 일입니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../api.dart';
import '../scope.dart';
import 'account.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _wiping = false;

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final api = Scope.apiOf(context);
    final st = app.state;
    final settings = ((st['settings'] as Map?) ?? const {}).cast<String, Object?>();
    final profile = app.profile;
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('내 몸 정보'),
            Text(
              profile == null
                  ? '아직 안 넣었습니다. 키·나이·성별이 있어야 기초대사량과 계획이 맞습니다.'
                  : '${profile['sex'] == 'male' ? '남성' : '여성'} · '
                      '${core.jsNumToString(core.jsToNumber(profile['age']))}세 · '
                      '${core.jsNumToString(core.jsToNumber(profile['heightCm']))}cm',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _editProfile(context, app),
              child: Text(profile == null ? '넣기' : '고치기'),
            ),
          ]),
        ),

        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('화면'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('연속 기록(스트릭) 숨기기'),
              subtitle: Text('연속 숫자가 부담이면 끌 수 있습니다. 기록은 그대로 남습니다.',
                  style: t.textTheme.labelSmall),
              value: core.jsTruthy(settings['hideStreaks']),
              onChanged: (on) {
                app.store.set({'settings': {...settings, 'hideStreaks': on}});
                setState(() {});
              },
            ),
            /* 간식 알림 — 서버가 아니라 폰이 직접 예약합니다. */
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('간식 단백질 알림'),
              subtitle: Text('오후 3시 반·저녁 8시 반에, 그날 단백질이 15g 넘게 남았을 때만.',
                  style: t.textTheme.labelSmall),
              value: settings['snackNudge'] != false,
              onChanged: (on) {
                app.store.set({'settings': {...settings, 'snackNudge': on}});
                setState(() {});
              },
            ),
          ]),
        ),

        /* 서버 카드는 뺐습니다. 주소는 앱에 박혀 있어서 사람이 볼 일이
           없고, "주소가 없습니다 — 친구 기능이 꺼져 있습니다" 같은 줄은
           읽는 사람을 불안하게만 합니다. 계정만 남기고, 주소 바꾸기는 맨
           아래 작은 글씨로 — 주인이 서버를 옮겼을 때만 쓰는 것. */
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('계정'),
            Text(
              api.signedIn
                  ? '로그인되어 있습니다'
                  : '로그인하지 않았습니다 — 지금은 기록이 이 기기에만 저장됩니다. 로그인하면 사진 판독 · '
                      '친구 · 기기 옮기기가 됩니다.',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              if (api.signedIn)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AccountScreen(
                            api: api,
                            onServerChange: Scope.serverSetterOf(context),
                          ))),
                  child: const Text('계정 관리'),
                ),
              if (api.signedIn)
                OutlinedButton(
                  onPressed: () async {
                    await api.signOut();
                    /* 로그아웃하면 셸이 로그인 화면으로 바뀝니다. 그 위에
                       설정이 남아 있으면 이상하니 같이 닫습니다. */
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('로그아웃'),
                ),
              if (!api.signedIn)
                FilledButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SignInScreen(
                            api: api,
                            onDone: () {
                              Navigator.of(context).pop();
                              setState(() {});
                            },
                            onServerChange: Scope.serverSetterOf(context),
                          ))),
                  child: const Text('로그인'),
                ),
            ]),
          ]),
        ),

        /* 백업 카드는 뺐습니다 — 기록이 내 계정에 저장되고 새 기기에서
           로그인하면 따라옵니다. 내보내기·가져오기는 맨 아래 작은 글씨로
           남깁니다(내 기록을 파일로 갖고 싶을 때). */
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('지우기'),
            RichishText(
              '이 기기의 모든 기록을 지우고 로그아웃합니다 — 측정·목표·계획·식단·일정, '
              '그리고 **결과지 사진까지**. 결과지에는 보통 이름과 나이가 함께 '
              '인쇄돼 있습니다. 내 계정에 저장된 기록은 남아, 다시 로그인하면 돌아옵니다.',
              style: t.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: mb(context).bad),
              onPressed: _wiping ? null : () => _wipe(context, app),
              child: Text(_wiping ? '지우는 중…' : '이 기기에서 전부 지우기'),
            ),
            if (api.signedIn) ...[
              const Divider(height: 24),
              RichishText(
                '계정을 지우면 친구 관계와 서버에 저장된 내 기록(동기화 사본·주간 요약)이 사라집니다. '
                '**이 기기의 기록은 그대로 남습니다** — 그건 위 버튼으로 지웁니다.',
                style: t.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: mb(context).bad),
                onPressed: () => _deleteAccount(context, app),
                child: const Text('계정 지우기'),
              ),
            ],
          ]),
        ),

        /* 맨 아래 작은 글씨들 — 자주 쓸 일 없는 것. */
        Wrap(children: [
          TextButton(
            onPressed: () => _export(context, app),
            child: Text('내 기록 내보내기', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ),
          TextButton(
            onPressed: () => _import(context, app),
            child: Text('가져오기', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ),
          TextButton(
            onPressed: () => unawaited(
                launchUrl(Uri.parse(kPrivacyUrl), mode: LaunchMode.externalApplication)),
            child: Text('개인정보처리방침',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
          ),
        ]),
      ]),
    );
  }

  /* 서버 주소를 바꾸는 길은 없습니다. 주소는 앱에 박혀 있고, 서버를 옮기면
     앱을 업데이트합니다 — 주인의 결정. */

  Future<void> _editProfile(BuildContext context, app) async {
    final p = app.profile ?? <String, Object?>{};
    final age = TextEditingController(
        text: p['age'] == null ? '' : core.jsNumToString(core.jsToNumber(p['age'])));
    final height = TextEditingController(
        text: p['heightCm'] == null ? '' : core.jsNumToString(core.jsToNumber(p['heightCm'])));
    var sex = '${p['sex'] ?? 'male'}';
    var activity = '${p['activityLevel'] ?? 'moderate'}';
    var trainingAge = '${p['trainingAge'] ?? 'novice'}';
    var days = core.jsToNumber(p['daysPerWeek'] ?? 4).toInt();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.all(20),
            children: [
              Text('내 몸 정보', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('기초대사량과 계획이 이 값에서 나옵니다. 나이를 비우면 '
                  '근성장 속도를 보수적으로 잡습니다.',
                  style: Theme.of(ctx).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(ctx).hintColor, height: 1.5)),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'male', label: Text('남성')),
                  ButtonSegment(value: 'female', label: Text('여성')),
                ],
                selected: {sex},
                onSelectionChanged: (s) => setSheet(() => sex = s.first),
              ),
              const SizedBox(height: 14),
              TextField(controller: height, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '키', suffixText: 'cm', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextField(controller: age, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '나이', suffixText: '세', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: activity,
                decoration: const InputDecoration(labelText: '활동량', border: OutlineInputBorder()),
                items: [
                  for (final e in core.kPal.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value.label)),
                ],
                onChanged: (v) => setSheet(() => activity = v ?? activity),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: trainingAge,
                decoration: const InputDecoration(labelText: '운동 경력', border: OutlineInputBorder()),
                items: [
                  for (final e in core.kMuscleBase.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value.label)),
                ],
                onChanged: (v) => setSheet(() => trainingAge = v ?? trainingAge),
              ),
              const SizedBox(height: 14),
              Text('주당 저항운동 일수: $days일',
                  style: Theme.of(ctx).textTheme.bodySmall),
              Slider(
                value: days.toDouble(), min: 0, max: 7, divisions: 7,
                label: '$days일',
                onChanged: (v) => setSheet(() => days = v.round()),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('저장'),
              ),
            ]),
        ),
      ),
    );
    if (saved != true) return;
    app.store.set({
      'profile': {
        ...p,
        'sex': sex,
        'age': double.tryParse(age.text.trim()),
        'heightCm': double.tryParse(height.text.trim()),
        'activityLevel': activity,
        'trainingAge': trainingAge,
        'daysPerWeek': days,
      }
    });
    if (mounted) setState(() {});
  }

  /* **내보내기는 실제로 가져갈 수 있어야 합니다.**
   *
   * 예전에는 JSON 을 화면에 띄우기만 했습니다. 그런데 앱 곳곳에서 — 그리고
   * 배포 안내문에서 — "지우기 전에 내보내기 하세요" 라고 말하고 있었습니다.
   * 따를 수 없는 안내였습니다. 폰에서 긴 JSON 을 손으로 긁어 복사하는 사람은
   * 없습니다.
   *
   * 파일로 저장하려면 플러그인이 필요한데 여기서는 시험할 수가 없습니다.
   * 그래서 클립보드로 갑니다 — 플러그인이 없어도 되고, 카톡 '나에게 보내기'
   * 나 메모에 붙여넣으면 그게 백업입니다. */
  void _export(BuildContext context, app) {
    final text = app.store.exportJSON();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('백업'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              '아래를 복사해서 카톡 「나에게 보내기」나 메모에 붙여넣어 두세요. '
              '앱을 지우거나 폰을 바꿀 때 이것만 있으면 되돌릴 수 있습니다.',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(text,
                    style: const TextStyle(fontSize: 11, height: 1.4)),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              toast(context, '복사했습니다 — 어딘가에 붙여넣어 두세요');
            },
            child: const Text('복사하기'),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, app) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('백업 붙여넣기'),
        content: TextField(
          controller: ctrl, maxLines: 8, autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('가져오기')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    try {
      app.store.importJSON(text);
      toast(context, '가져왔습니다');
      setState(() {});
    } catch (e) {
      /* **저장이 실패하면 던집니다.** 조용히 넘어가면 화면이 "가져왔습니다" 라고
         말하고, 그 말을 믿은 사람이 원본 백업 파일을 지웁니다. */
      toast(context, '$e');
    }
  }

  /* **지우면 로그아웃까지 합니다.**
   *
   * 예전엔 기기 저장만 비웠습니다. 로그인은 그대로라 두 가지가 났습니다 —
   * 다음에 켜면 동기화가 "막 깐 기기" 로 보고 계정 사본을 통째로 받아 와
   * 지운 기록이 되살아났고, 그 전에 온보딩을 다시 하면 빈 것에 가까운
   * 기록이 **계정 사본을 덮어썼습니다.** 지운 사람이 바란 건 둘 다 아닙니다.
   *
   * 로그아웃하면 둘 다 없습니다. 계정 사본은 그대로 있다가, 같은 사람이
   * 다시 로그인하면 돌아옵니다 — 다이얼로그가 그렇게 말합니다. 계정의
   * 기록까지 지우는 건 아래 「계정 지우기」 입니다.
   *
   * 순서: 못 보낸 것부터 보내 봅니다(계정 사본이 이 기기와 같아야 "다시
   * 로그인하면 돌아옵니다" 가 참입니다) → 로그아웃 → 지우기 → 큐 비우기.
   * 큐를 비우는 건 이 기기를 넘겨받은 다른 사람이 로그인했을 때 지운
   * 사람의 기록 사본이 그 계정으로 올라가지 않게 하려는 것입니다. */
  Future<void> _wipe(BuildContext context, app) async {
    final api = Scope.apiOf(context);
    final queue = Scope.queueOf(context);
    final signedIn = api.signedIn;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 기기에서 전부 지울까요?'),
        content: Text(signedIn
            ? '측정·목표·계획·식단·일정과 결과지 사진을 이 기기에서 지우고 로그아웃합니다. '
                '되돌릴 수 없습니다.\n\n'
                '내 계정에 저장된 기록은 남습니다 — 다시 로그인하면 돌아옵니다. '
                '계정의 기록까지 지우려면 아래 「계정 지우기」를 쓰세요.'
            : '측정·목표·계획·식단·일정과 결과지 사진을 지웁니다. 되돌릴 수 없습니다.\n\n'
                '백업을 먼저 내보내는 것을 권합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('그대로 두기')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('전부 지우기')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    setState(() => _wiping = true);
    if (api.signedIn) {
      try {
        await queue?.flush().timeout(const Duration(seconds: 8));
      } catch (_) {/* 못 보냈으면 못 보낸 것 — 지우기를 막지는 않습니다 */}
      await api.signOut();
    }
    app.store.reset();
    queue?.clear();
    if (!context.mounted) return;
    toast(context, '지웠습니다');
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _deleteAccount(BuildContext context, app) async {
    final api = Scope.apiOf(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('계정을 지울까요?'),
        content: const Text(
            '친구 관계와 서버에 저장된 내 기록(동기화 사본·주간 요약)이 사라집니다. '
            '되돌릴 수 없습니다.\n\n'
            '이 기기의 기록은 그대로 남습니다 — 그건 「이 기기에서 전부 지우기」로 지웁니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('그대로 두기')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('계정 지우기')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final r = await api.deleteMe();
    if (!context.mounted) return;
    if (!r.ok) {
      toast(context, r.reason);
      return;
    }
    await api.signOut();
    if (!context.mounted) return;
    toast(context, '계정을 지웠습니다');
    /* 로그아웃됐으니 밑의 셸은 이미 로그인 화면입니다. 설정을 닫아
       그걸 보여 줍니다 — 안 닫으면 없는 계정의 설정이 계속 떠 있습니다. */
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}
