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
 *     않고 말하고, 지우는 길도 같이 놓습니다. 계정 삭제는 서버의 사본을 지우고,
 *     이 기기의 기록은 누구 것인지 모르는 기록으로 남습니다 — 다른 계정으로 로그인하면
 *     「다른 계정의 기록일 수 있어요」 와 함께 합칠지 먼저 묻고, 기본은 합치지 않기입니다
 *     (local_owner.dart). 두 개는 다른 일입니다.
 *
 * 차례(위 → 아래): 내 몸 정보 · 화면 · 운동 환경 · 계정 · 기본 공유(로그인
 * 했을 때) · 동기화 · **도움말(의견함 · 가입자 목록 — 운영자만 · 의견 버튼 보이기 · 앱 안내
 * 다시 보기)** · 지우기 ·
 * **로그아웃(로그인했을 때)** · 작은 글씨(내보내기 · 가져오기 ·
 * 개인정보처리방침) · 앱 버전.
 *
 * **도움말은 「지우기」 바로 위입니다.** 사람은 "어디다 말하지" · "처음 안내 다시
 * 보고 싶은데" 를 설정의 끝 쪽에서 찾습니다. 그렇다고 「지우기」 와 「로그아웃」
 * 사이에 끼우면 둘이 갈라집니다 — 빨간 카드 바로 밑에 로그아웃이 있어야 "지우는
 * 것" 과 "나가는 것" 이 한눈에 구분됩니다(아래).
 *
 * **「의견 보내기」 줄은 없습니다.** 주인의 말: "의견보내기는 설정 드가서 하는게
 * 아니라 앱 어딘가에 상시 떠있는 버튼으로". 화면 옆 말풍선(feedback_bubble.dart)이
 * 이 화면에도 떠 있어서, 여기 줄을 또 두면 같은 일을 하는 단추가 한 화면에 둘입니다.
 * 대신 그 말풍선을 켜고 끄는 스위치를 둡니다("설정에서 의견보내기 아이콘 표시 끄고
 * 킬수있게해") — 말풍선을 X 로 끌어다 치운 사람이 되찾는 곳이 여기이고, 치울 때
 * 「다시 켜려면 설정 → 도움말에서 켜세요」 라고 이 자리를 알려 줍니다.
 * **비공개 시험 기간에는 켜진 채 잠급니다**(「테스트 기간에는 켜 둡니다」) — 말풍선의
 * X 도 그동안은 못 치웁니다. 시험판의 의견이 시험의 전부라서입니다(feedback.dart 의
 * feedbackBubbleLocked). 시험이 끝나면(서버 testing 거짓) 평소처럼 켜고 끕니다.
 *
 * **보낸 의견을 읽는 곳(「의견함」)은 도움말 맨 위** — 운영자(서버 설정 feedbackNotify 의
 * 계정)에게만 섭니다. 주인의 물음 "의견 어디서 봐" 의 답이 노트북 도구뿐이었습니다. 다른
 * 사람에게는 줄도 자리표시도 없습니다(feedback_inbox.dart FeedbackInboxRow). 바로 아래
 * 「가입자 목록」 도 같은 규칙입니다 — 노트북의 reset-password.js 로만 보던 아이디 · 가입일을
 * 폰에서, 누르면 아이디 복사(user_list.dart OperatorUsersRow).
 *
 * **로그아웃은 맨 아래 한 곳입니다.** 예전엔 긴 페이지 한가운데 「계정」
 * 카드 안, 「계정 관리」 옆의 작은 버튼이었고 주인이 못 찾았습니다 —
 * "설정 하단에 로그아웃 버튼 만들어". 사람은 로그아웃을 설정의 맨 끝에서
 * 찾습니다. 그래서 거기에 한 줄 폭으로, 아이콘과 함께 두고, 계정 카드에서는
 * 뺐습니다(두 곳이면 어느 게 진짜인지 또 찾게 됩니다). 색은 빨강이 아니라
 * 보통 글자색입니다 — 로그아웃은 아무것도 지우지 않습니다. 이 계정의 기록은
 * **이 기기에 따로 보관**됩니다(local_owner.dart — 계정 칸). 다음 사람의
 * 「로그인 없이 쓰기」 나 다른 계정에는 안 보이고, 같은 계정으로 다시 로그인하면
 * 그대로 돌아옵니다. 계정에 저장된 사본도 그대로입니다(피드백 52 — 예전엔 기록이
 * 화면에 남아 다음에 가입한 계정으로 올라갔습니다). 빨강은 바로 위 「지우기」
 * 카드의 몫입니다. 그래도 한 번은 묻습니다 — 잘못 누르면 비밀번호를 다시 쳐야
 * 하고, 그동안 친구 알림도 이 폰으로 안 옵니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../api.dart';
import '../local_owner.dart';
import '../native_push.dart';
import '../scope.dart';
import '../update.dart';
import 'account.dart';
import 'feedback.dart'
    show feedbackBubbleLocked, feedbackBubbleOn, loadFeedbackBubbleOn, setFeedbackBubbleOn;
import 'feedback_inbox.dart' show FeedbackInboxRow;
import 'gym_settings.dart';
import 'share_defaults.dart';
import 'sync_settings.dart';
import 'tester_welcome.dart' show showTesterWelcome;
import 'user_list.dart' show OperatorUsersRow;
import 'workout_tutorial.dart';
import '../ui/edge.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _wiping = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    /* 말풍선 켜짐은 앱이 켤 때 말풍선이 이미 읽어 둡니다. 여기서 한 번 더 읽는 것은
       스위치가 저장된 값과 어긋나 보이는 일이 없게 — 싸고, 같은 값을 다시 실을 뿐입니다. */
    unawaited(loadFeedbackBubbleOn());
  }

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final api = Scope.apiOf(context);
    final st = app.state;
    final settings = ((st['settings'] as Map?) ?? const {}).cast<String, Object?>();
    final profile = app.profile;
    final update = Scope.updateOf(context);
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('내 몸 정보'),
            Text(
              profile == null
                  ? '아직 안 넣었습니다 — 키·나이·성별이 계획의 기준입니다'
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
              subtitle: Text('기록은 그대로 남습니다',
                  style: t.textTheme.labelSmall),
              value: core.jsTruthy(settings['hideStreaks']),
              onChanged: (on) {
                app.store.set({'settings': {...settings, 'hideStreaks': on}});
                setState(() {});
              },
            ),
            /* 끼니 기록 알림 — 서버가 아니라 폰이 직접 예약합니다. */
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('끼니 기록 알림'),
              subtitle: Text('10시 · 13시 · 19시 — 이미 적은 끼니는 안 울립니다',
                  style: t.textTheme.labelSmall),
              value: settings['mealReminder'] != false,
              onChanged: (on) {
                app.store.set({'settings': {...settings, 'mealReminder': on}});
                setState(() {});
              },
            ),
            /* 운동 알림 — 헬스 가기로 한 날 저녁까지 기록이 없으면 집에서 15분. */
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('운동 알림'),
              subtitle: Text('헬스 날 저녁 8시 반 — 아직 안 갔으면 알림',
                  style: t.textTheme.labelSmall),
              value: settings['workoutReminder'] != false,
              onChanged: (on) {
                app.store.set({'settings': {...settings, 'workoutReminder': on}});
                setState(() {});
              },
            ),
            /* 간식 알림 — 서버가 아니라 폰이 직접 예약합니다. */
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('간식 단백질 알림'),
              subtitle: Text('오후 3시 반 · 저녁 8시 반, 단백질이 15g 넘게 남았을 때만',
                  style: t.textTheme.labelSmall),
              value: settings['snackNudge'] != false,
              onChanged: (on) {
                app.store.set({'settings': {...settings, 'snackNudge': on}});
                setState(() {});
              },
            ),
            /* 친구 알림(앱 알림) 상태 한 줄 — 로그인했을 때만(친구는 계정 기능). */
            if (api.signedIn) _PushRows(key: ValueKey(api)),
            /* 헬스 화면의 「따라 해 보기」 는 처음 한 번만 뜹니다 — 다시 보는 길은 여기뿐.
               이름은 열리는 화면의 제목과 같은 상수 — 「도움말」 을 눌렀는데 「따라 해 보기」 가
               열리면 다른 것을 기대합니다. */
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(kGymTutorialTitle),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: () => WorkoutTutorial.show(context),
            ),
          ]),
        ),

        /* 운동 환경 — 있는 기구 · 기구 수 · 익숙한 종목. 운동 기록 화면이 여기에 맞춰 종목을 바꿉니다. */
        const GymSettingsCard(),

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
                  : '로그인하지 않았습니다 — 기록은 이 기기에만 · 로그인하면 사진 판독 · 친구 · 기기 옮기기',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
            ),
            const SizedBox(height: 10),
            /* 로그아웃은 여기 없습니다 — 맨 아래 한 곳(머리 주석). 여기엔
               「계정 관리」 나 「로그인」 중 하나만 남습니다. */
            if (api.signedIn)
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AccountScreen(
                          api: api,
                          onServerChange: Scope.serverSetterOf(context),
                        ))),
                child: const Text('계정 관리'),
              )
            else
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
        ),

        /* 새 친구에게 기본으로 보여 주는 것 — 친구 탭의 「기본 공유」 와 같은 카드. */
        if (api.signedIn) const ShareDefaultsCard(),

        /* 동기화 — 두 기기의 기록을 합치는 것. 상태와 「지금 동기화」 는 여기서. */
        SyncSettingsCard(cloud: Scope.cloudOf(context), api: api),

        /* 도움말 — 「지우기」 바로 위(머리 주석). 말풍선 스위치와 「앱 안내 다시 보기」.
           로그인과 상관없이 둘 다 — 의견은 로그인 없이도 가고(서버가 익명으로 받음),
           안내는 누구에게나 같습니다. 스위치는 말풍선과 같은 값(feedbackBubbleOn)을
           봐서, 켜면 뒤로 가기 전에도 이 화면 옆에 말풍선이 바로 돌아옵니다.
           시험 기간이면 켜진 채 잠급니다 — 새 판 확인기가 시험이 끝났다는 답을 받으면
           이 화면을 연 채로도 곧바로 풀립니다(확인기도 같이 듣습니다).
           맨 위 「의견함」 과 그 아래 「가입자 목록」 은 운영자에게만 — 아니면 줄이 아무것도 안
           그립니다. 서버를 옮기면 Api 가 새것이라 줄도 새로 묻습니다(열쇠 — 둘이 겹치지 않게 따로). */
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('도움말'),
            if (api.signedIn) FeedbackInboxRow(key: ValueKey(api)),
            if (api.signedIn) OperatorUsersRow(key: ValueKey((api, 'users'))),
            ListenableBuilder(
              listenable: Listenable.merge([feedbackBubbleOn, if (update != null) update]),
              builder: (context, _) {
                final locked = feedbackBubbleLocked(update);
                return SwitchListTile(
                  key: const Key('settings-feedback-bubble'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('의견 버튼 보이기'),
                  subtitle: Text(locked ? '테스트 기간에는 켜 둡니다' : '화면 가장자리 말풍선 · 꾹 눌러 옮겨요',
                      style: t.textTheme.labelSmall),
                  value: locked || feedbackBubbleOn.value,
                  onChanged: locked ? null : (v) => unawaited(setFeedbackBubbleOn(v)),
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('settings-welcome'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              /* 처음 한 번만 뜨는 인사(tester_welcome.dart) — 다시 보는 길은 여기뿐. */
              onPressed: () => showTesterWelcome(context, force: true),
              icon: const Icon(LucideIcons.bookOpen, size: 18),
              label: const Text('앱 안내 다시 보기'),
            ),
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

        /* 로그아웃 — 설정의 맨 끝, 한 줄 폭(머리 주석). 「지우기」 카드 밑,
           작은 글씨 위: 카드들을 다 지나 내려온 곳에서 바로 보이고, 빨간
           「지우기」 와는 카드 경계로 갈라져 헷갈리지 않습니다. 색은
           onSurface — 파랑(primary)이면 「고치기」 같은 할 일로, 빨강이면
           지우는 일로 읽힙니다. 로그아웃은 둘 다 아닙니다. */
        if (api.signedIn)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              key: const Key('settings-logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.colorScheme.onSurface,
                minimumSize: const Size.fromHeight(48),
              ),
              /* 서버가 느리면 로그아웃이 몇 초 걸립니다(알림 등록 빼기 4초 +
                 요청). 그동안 두 번 누르지 않게 막고, 누른 게 먹었다고 보여 줍니다. */
              onPressed: _signingOut ? null : () => _signOut(context),
              icon: const Icon(LucideIcons.logOut, size: 18),
              label: Text(_signingOut ? '로그아웃하는 중…' : '로그아웃'),
            ),
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
        const _AppVersionLine(),
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
      /* **키보드가 올라오면 시트를 그만큼 밀어 올립니다.** 모달 시트는 스스로
         키보드를 피하지 않아서, 안 하면 시트 아래쪽 — 「저장」 이 있는 곳 — 이
         키보드 뒤에 깔립니다. 끝까지 스크롤해도 시트의 뷰포트 자체가 키보드
         뒤까지 뻗어 있어 꺼낼 수 없습니다. 아이폰 숫자 패드에는 완료 키가 없어
         그러면 저장으로 갈 길이 없고, 탈출은 시트 바깥 탭 — 넣은 것이 사라집니다. */
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        /* 시트가 다 펴질 때까지(0.85 → 1.0)는 끌기가 목록을 스크롤하지 않고 시트를
           키우는 데 쓰여 ListView 의 onDrag 가 반응하지 못합니다 — 첫 끌기에서
           키보드가 남습니다. 시트 크기가 바뀌는 알림을 받아 그때도 내립니다.
           이 알림은 손으로 끌 때(와 그 관성)만 오고, 키보드가 올라와 시트가
           밀릴 때는 오지 않습니다(availablePixels 만 바뀜). */
        child: NotificationListener<DraggableScrollableNotification>(
          onNotification: (_) {
            dismissKeyboard();
            return false;
          },
          child: StatefulBuilder(
            builder: (ctx, setSheet) => DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              builder: (ctx, sc) => ListView(
                controller: sc,
                padding: const EdgeInsets.all(20),
                /* 목록을 끌면 키보드를 내립니다 — 숫자 패드는 달리 닫을 키가 없습니다. */
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  Text('내 몸 정보', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('계획의 기준값입니다 — 나이를 비우면 보수적으로 잡습니다',
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
                  /* 키 → 「다음」 으로 나이 칸에, 나이 → 「완료」 로 키보드를 내립니다
                     (안드로이드 숫자판에 있는 키. 아이폰 숫자 패드에는 없어서 거기서는
                     바깥 탭 · 목록 끌기로 닫습니다). */
                  TextField(
                      controller: height,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          labelText: '키', suffixText: 'cm', border: OutlineInputBorder())),
                  const SizedBox(height: 14),
                  TextField(
                      controller: age,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                          labelText: '나이', suffixText: '세', border: OutlineInputBorder())),
                  const SizedBox(height: 14),
                  /* isExpanded — 라벨이 길어("매우 활동적 (육체노동/2회 운동)") 360 폭
                     화면에서 오른쪽으로 넘칩니다. 늘려 두면 칸 폭에 맞춰 줄입니다. */
                  DropdownButtonFormField<String>(
                    initialValue: activity,
                    isExpanded: true,
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
                    isExpanded: true,
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
              '복사해서 메모나 카톡 「나에게 보내기」에 붙여 두세요',
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

  /* 로그아웃 — 한 번 묻고, api.signOut → 설정 닫기(셸까지 걷는 쪽으로 — 맨 아래 주석).
   *
   * 다이얼로그의 한 줄은 코드가 실제로 하는 일입니다(api.dart · local_owner.dart):
   *   · 먼저 못 보낸 것을 이 계정으로 보내 봅니다 — 3초 모으던 변경 · 오프라인 큐. 짧게만
   *     기다리고, 못 보낸 것은 계정 칸에 남았다가 다시 로그인하면 갑니다. 큐에 남은 건수는
   *     다이얼로그가 미리 말합니다.
   *   · 이 기기의 기록 — 이 계정의 칸으로 치워 둡니다(사진 파일은 그대로). 셸은 로그인 화면으로
   *     가고, 「로그인 없이 쓰기」 는 빈 기록(또는 전에 로그인 없이 쓰던 기록)입니다.
   *   · 내 계정의 기록 — POST /auth/signout(세션 끝내기)과 토큰 · 친구/공유 캐시 지우기뿐,
   *     서버 사본은 안 건드립니다.
   *   · 다시 로그인하면 — 같은 계정이면 치워 둔 칸이 그대로 돌아옵니다. 동기화를 꺼 뒀어도
   *     기록은 칸에 있으니 "돌아와요" 는 참입니다.
   * 그래서 「지우기」 처럼 "되돌릴 수 없습니다" 가 아니라 안심시키는 한 줄입니다
   * — 로그아웃을 망설이게 하는 건 "내 기록 날아가나?" 한 가지입니다.
   *
   * **알림 등록 빼기는 여기서 따로 부르지 않습니다.** 앱의 Api 는 PushAwareApi
   * (native_push.dart)라서 signOut 이 로그인이 살아 있을 때 먼저 이 기기를
   * 알림 받는 곳에서 뺍니다. 로그아웃 길이 여러 곳이라 거기 한 곳에서 잡고,
   * 예전 버튼도 그것에 기댔습니다. 여기서 또 부르면 DELETE 가 두 번 갑니다. */
  Future<void> _signOut(BuildContext context) async {
    final api = Scope.apiOf(context);
    final yes = await confirmSignOut(context,
        unsent: Scope.queueOf(context)?.pending ?? 0, idUnknown: api.signedIn && api.userId == null);
    if (yes != true || !context.mounted) return;
    setState(() => _signingOut = true);
    /* signOut 은 던지지 않습니다 — 요청 실패 · 저장 실패 · 알림 빼기 실패를
       전부 안에서 삼키고 토큰은 지웁니다(api.dart · native_push.dart). */
    await api.signOut();
    /* 로그아웃하면 셸이 로그인 화면으로 바뀝니다. 그 위에 설정이 남아
       있으면 이상하니 같이 닫습니다.
       pop() 이 아니라 셸까지 — 아래 _wipe · _deleteAccount 와 같은 방식.
       로그아웃은 몇 초 걸리고 그동안 설정의 다른 단추는 살아 있습니다. 그 사이
       「내 기록 내보내기」 같은 창을 열었으면 pop() 은 **그 창**을 닫고 설정은
       로그아웃된 채 남았고, 뒤로 가기로 설정이 닫히는 중이었으면 밑의 **셸**을
       닫았습니다. 셸(첫 자리)까지 걷으면 둘 다 없습니다 — 설정은 셸에서만 엽니다. */
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /* **지우면 로그아웃까지 합니다.** 이 기기에 치워 둔 다른 계정 · 로그인 없이 쓴 기록의
   * 칸까지 전부입니다(local_owner.dart wipeDevice) — "전부 지웠다" 고 믿고 폰을 넘긴 사람에게
   * 누군가의 기록이 남아 있으면 안 됩니다.
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
   * 로그인하면 돌아옵니다" 가 참입니다) → 로그아웃 → 지우기(모든 칸 · 사진 ·
   * 독촉 · 소식 · 초대 표시) → 큐 비우기.
   * 큐를 비우는 건 이 기기를 넘겨받은 다른 사람이 로그인했을 때 지운
   * 사람의 기록 사본이 그 계정으로 올라가지 않게 하려는 것입니다. */
  Future<void> _wipe(BuildContext context, app) async {
    final api = Scope.apiOf(context);
    final queue = Scope.queueOf(context);
    final signedIn = api.signedIn;
    /* 화면에 안 보이는 보관된 칸도 같이 지워집니다 — 동기화를 끈 계정이면 서버에 사본이 없어
       되찾을 수 없습니다. 있을 때만 한 줄 더합니다(2차 검토). */
    final p = await parkedSlots();
    final parked = p.accounts > 0 && p.guest
        ? '이 기기에 따로 보관된 다른 계정 ${p.accounts}개와 로그인 없이 쓴 기록도 지워져요.'
        : p.accounts > 0
            ? '이 기기에 따로 보관된 다른 계정 ${p.accounts}개의 기록도 지워져요.'
            : p.guest
                ? '이 기기에 따로 보관된 로그인 없이 쓴 기록도 지워져요.'
                : null;
    if (!context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 기기에서 전부 지울까요?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(signedIn
              ? '측정·목표·계획·식단·일정과 결과지 사진을 이 기기에서 지우고 로그아웃합니다. '
                  '되돌릴 수 없습니다.\n\n'
                  '내 계정에 저장된 기록은 남습니다 — 다시 로그인하면 돌아옵니다. '
                  '계정의 기록까지 지우려면 아래 「계정 지우기」를 쓰세요.'
              : '측정·목표·계획·식단·일정과 결과지 사진을 지웁니다. 되돌릴 수 없습니다.\n\n'
                  '백업을 먼저 내보내는 것을 권합니다.'),
          if (parked != null) ...[
            const SizedBox(height: 12),
            Text(parked, key: const Key('wipe-parked'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ]),
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
    /* 친구 목록 · 공유 설정 캐시도 — 로그아웃이 지우지만, 로그인 안 한 채로
       눌렀을 때 예전 판이 남긴 것까지(wipeDevice 안). */
    if (!context.mounted) return;
    await wipeDevice(app: app, queue: queue, cloud: Scope.cloudOf(context),
        invites: Scope.slotsOf(context)?.invites);
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
            '이 기기의 기록은 그대로 남고, 다른 계정으로 로그인하면 합칠지 먼저 물어요. '
            '지우려면 「이 기기에서 전부 지우기」를 쓰세요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('그대로 두기')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('계정 지우기')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    /* 지우고 로그아웃까지(api.dart deleteAccount). 이 기기의 기록은 누구 것인지 모르는 기록으로
       남습니다 — local_owner.dart 의 「계정 지우기」 주석. */
    final r = await api.deleteAccount();
    if (!context.mounted) return;
    if (!r.ok) {
      toast(context, r.reason);
      return;
    }
    toast(context, '계정을 지웠습니다');
    /* 로그아웃됐으니 밑의 셸은 이미 로그인 화면입니다. 설정을 닫아
       그걸 보여 줍니다 — 안 닫으면 없는 계정의 설정이 계속 떠 있습니다. */
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

/* 「푸시 알림」 상태 한 줄 — 친구 독촉 · 소식이 이 폰에 앱 알림으로 바로 오는가.
 *
 * 크롬 이야기는 여기 없습니다(주인 의견 47 "설정에서 크롬 알림관련내용 없애"). 예전엔 이 밑에
 * 「크롬(웹) 알림 끄기」 가 있었습니다 — 예전 웹 앱이 크롬에 남긴 알림 구독 때문에 독촉이 앱이
 * 아니라 크롬으로 왔기 때문입니다. 이제는 앱 알림이 등록되면 앱이 그 구독을 계정마다 한 번
 * 저절로 지웁니다(native_push.dart). 사람이 찾아 누를 것이 없습니다.
 *
 * 이 줄은 남깁니다 — 「꺼짐 — 폰 설정에서 Mybody 알림을 켜면…」 처럼 사람이 할 일이 있는
 * 경우를 알려 주는 곳이 여기뿐입니다. 서버가 등록 길을 모르면(404) 「서버 미지원」. */
class _PushRows extends StatefulWidget {
  const _PushRows({super.key});
  @override
  State<_PushRows> createState() => _PushRowsState();
}

class _PushRowsState extends State<_PushRows> {
  ApiResult? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final r = await Scope.apiOf(context).pushStatus();
    if (mounted) setState(() => _status = r);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final push = NativePush.instance;
    return ListenableBuilder(
      listenable: push,
      builder: (context, _) {
        final d = describePush(push, status: _status);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('푸시 알림'),
          subtitle: Text(d.hint, style: t.textTheme.labelSmall),
          trailing: Text(d.label,
              style: t.textTheme.labelLarge?.copyWith(
                  color: d.line == PushLine.on ? t.colorScheme.primary : t.hintColor)),
        );
      },
    );
  }
}

/* 앱 판 · 빌드 번호 · 받은 곳. 친구를 도울 때 "몇 판이야? 어디서 깔았어?"
   를 묻는 대신 이 줄을 읽어 달라고 하면 됩니다. 받은 곳에 따라 업데이트
   길이 다릅니다(스토어 · TestFlight · GitHub 의 APK). 아이폰에서 받은 곳이
   안 적혀 있으면 TestFlight 입니다 — 앱스토어 심사 빌드와 구분이 안 돼서
   이름을 안 붙입니다(update.dart 의 channelLabel). */
class _AppVersionLine extends StatelessWidget {
  const _AppVersionLine();

  @override
  Widget build(BuildContext context) {
    final check = Scope.updateOf(context);
    if (check == null) return const SizedBox.shrink();
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: check,
      builder: (context, _) {
        final p = check.package;
        if (p == null || p.version.isEmpty) return const SizedBox.shrink();
        final build = p.buildNumber.isEmpty || p.buildNumber == p.version
            ? '' : ' (빌드 ${p.buildNumber})';
        final where = channelLabel(check.channel);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Text('앱 버전 ${p.version}$build${where.isEmpty ? '' : ' · $where'}',
              style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
        );
      },
    );
  }
}
