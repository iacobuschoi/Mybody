/* =============================================================================
 * update_banner.dart — 새 판 안내 카드 (판단은 update.dart)
 *
 * 홈 맨 위에 둘 다 띄웁니다. 로그인 화면과 첫 설정(온보딩)에는 「서버와
 * 안 맞음」 만 띄웁니다. 서버가 옛 앱을 안 받게 되면 가장 먼저 막히는 곳이
 * 가입 · 로그인인데, 그 사람은 아직 홈에 못 와 있습니다. 거기서 안내가
 * 없으면 "동의해야 계정을 만들 수 있습니다" 같은 엉뚱한 오류만 봅니다.
 * 새 판 소식(접을 수 있는 것)은 거기까지 끌고 가지 않습니다 — 처음 켠
 * 사람에게는 소음입니다.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../scope.dart';
import '../ui/symbols.dart';
import '../ui/widgets.dart';
import '../update.dart';

/* 두 가지만 띄웁니다.

   · 새 판 — 「업데이트」 와 「나중에」. 「나중에」 는 그 판 하나만 접습니다.
     더 새 판이 나오면 다시 보입니다.
   · 서버와 안 맞는 판 — 접을 수 없습니다. 그래도 **앱을 막지는 않습니다.**
     로그인 · 동기화 · 친구가 안 될 뿐, 기기의 기록은 그대로 됩니다.
     막아 버리면 지하철에서 오늘 먹은 것 하나 못 적습니다.

   직접 깐 APK 는 "지우고 새로 깔기" 를 하기 쉽습니다. 그러면 기기의 기록이
   사라집니다 — 그래서 그 경우만 "지우지 말고 그 위에 설치" 를 덧붙입니다. */
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, this.requiredOnly = false});

  /// 「서버와 안 맞음」 만 띄웁니다 — 로그인 · 첫 설정 화면용.
  final bool requiredOnly;

  @override
  Widget build(BuildContext context) {
    final check = Scope.updateOf(context);
    if (check == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: check,
      builder: (context, _) {
        final n = check.notice;
        if (n == null) return const SizedBox.shrink();
        if (requiredOnly && n.kind != UpdateKind.required) return const SizedBox.shrink();
        return n.kind == UpdateKind.required
            ? _UpdateRequired(check: check, n: n)
            : _UpdateAvailable(check: check, n: n);
      },
    );
  }
}

/* 채널마다 한 줄. 아이폰에서는 안드로이드 이름이 안 나오고, 그 반대도
   같습니다 — 채널이 곧 플랫폼이라 한쪽 말만 나갑니다. */
String _howTo(UpdateChannel c) => switch (c) {
      UpdateChannel.apk => '새 APK 를 받아 설치하세요. **지금 앱을 지우지 말고** 그 위에 '
          '설치해야 이 기기의 기록이 남습니다.',
      UpdateChannel.play => '플레이 스토어에서 업데이트합니다. 기록은 그대로 남습니다.',
      UpdateChannel.testflight => 'TestFlight 앱에서 새 빌드를 받으세요. 기록은 그대로 남습니다.',
      _ => '앱스토어에서 업데이트합니다. 기록은 그대로 남습니다.',
    };

Future<void> _openUpdate(BuildContext context, UpdateCheck check, UpdateNotice n) async {
  final ok = await check.open(n);
  /* 못 열었으면 주소라도 보여 줍니다 — 친구에게 불러 줄 수 있게. */
  if (!ok && context.mounted) toast(context, '열지 못했습니다 — ${n.url}');
}

class _UpdateAvailable extends StatelessWidget {
  const _UpdateAvailable({required this.check, required this.n});
  final UpdateCheck check;
  final UpdateNotice n;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('새 버전 ${josa(n.version, '이', '가')} 나왔습니다',
            trailing: Icon(LucideIcons.arrowUpCircle, size: 18, color: mb(context).ok)),
        RichishText('지금 쓰는 버전은 ${n.current}입니다. ${_howTo(n.channel)}',
            style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton(
              onPressed: () => unawaited(_openUpdate(context, check, n)),
              child: const Text('업데이트')),
          const SizedBox(width: 8),
          TextButton(onPressed: () => unawaited(check.dismiss()), child: const Text('나중에')),
        ]),
      ]),
    );
  }
}

class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired({required this.check, required this.n});
  final UpdateCheck check;
  final UpdateNotice n;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Note(
          tone: Tone.warn,
          title: '이 버전은 이제 서버와 맞지 않습니다.',
          text: '로그인 · 동기화 · 친구 기능이 안 될 수 있습니다. '
              '이 기기에 적는 기록은 그대로 쓸 수 있습니다.',
        ),
        RichishText(
            '${n.version} 이상으로 업데이트해 주세요. 지금은 ${n.current}입니다. '
            '${_howTo(n.channel)}',
            style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: () => unawaited(_openUpdate(context, check, n)),
            child: const Text('업데이트')),
      ]),
    );
  }
}
