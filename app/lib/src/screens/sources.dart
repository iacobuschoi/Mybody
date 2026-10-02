/* =============================================================================
 * sources.dart — 「근거 · 출처」
 *
 * 앱이 보여 주는 칼로리 · 단백질 · 감량 속도 · 운동 처방 · 체성분 추정이 어떤
 * 공개 연구 · 지침에서 왔는지를 한곳에 모읍니다(목록은 citations.dart). 항목을
 * 누르면 원문이 앱 밖(브라우저)에서 열리고, 꾹 누르면 주소를 복사합니다 — 링크가
 * 안 열리는 기기에서도 주소는 가져갈 수 있어야 합니다.
 *
 * 가는 길 둘: 설정 → 도움말의 「근거 · 출처」(전체), 그리고 숫자 옆 「출처」 링크의
 * 시트에서 「모든 출처 보기」. [SourcesScreen.topics] 를 주면 그 주제의 출처만
 * 먼저 보여 주고, 「모든 출처 보기」 로 전체를 펼칩니다.
 *
 * 의료 안내(진단 · 치료를 대신하지 않음)도 여기 둡니다 — 온보딩에서 한 번 보고
 * 지나간 사람이 다시 볼 곳이 없었습니다.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../citations.dart';
import '../ui/widgets.dart';

const String kSourcesTitle = '근거 · 출처';

/// 목록 화면의 제목 — 영어로 보는 심사자도 출처 화면인 줄 알게 「(Sources)」 를 덧붙입니다.
const String kSourcesScreenTitle = '$kSourcesTitle (Sources)';

/// 일부 기준(연속 감량 한도 · 활동계수 · 근육 증가 계수 …)은 앱이 정한 값이라 「바탕으로
/// 계산합니다」 라고만 하면 지나칩니다(citations.dart 의 kAppSetTopics · kTopicRelated).
const String kSourcesIntro = '이 앱의 권장값은 아래 공개 연구·지침을 참고해 계산하며, 일부 기준은 '
    '앱이 정한 값입니다 — 그런 자리의 「출처」 에는 그렇다고 적어 둡니다.';
const String kSourcesTapHint = '누르면 원문이 열립니다 · 꾹 누르면 주소 복사';

/// 의료 안내 — **모든 사람에게** 의사와 상의하라고 합니다(애플 지침 1.4.1). 조건(질환 ·
/// 임신 · 약)은 그 뒤에 「특히」 로.
const String kMedicalDisclaimer = '이 앱은 의료기기가 아니며 진단·치료를 대신하지 않습니다. '
    '식단·운동을 크게 바꾸거나 건강에 관한 결정을 하기 전에는 의사와 상의하세요. '
    '질환이 있거나 임신·수유 중이거나 약을 먹고 있다면 특히 그렇습니다.';

/// 숫자 카드 밑에 다는 짧은 한 줄(플랜의 「하루 식단 목표」).
const String kMedicalShort = '의료기기가 아닙니다 — 식단·운동을 크게 바꾸기 전에는 의사와 상의하세요.';

/// 링크를 앱 밖에서 엽니다. 시험은 이것을 바꿔 끼워 실제로 열지 않고 주소만 봅니다.
@visibleForTesting
Future<bool> Function(Uri uri) openSourceUrl =
    (u) => launchUrl(u, mode: LaunchMode.externalApplication);

/// 출처 한 건을 엽니다. 못 열면 주소를 알려 줍니다.
Future<void> openCitation(BuildContext context, Citation c) async {
  var ok = false;
  try {
    ok = await openSourceUrl(Uri.parse(c.url));
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) toast(context, '링크를 열지 못했습니다 — ${c.url}');
}

/// 출처 한 줄 — 무엇의 근거인지, 서지 정보, 주소. 누르면 원문, 꾹 누르면 주소 복사.
class CitationTile extends StatelessWidget {
  const CitationTile(this.c, {super.key});
  final Citation c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final link = t.colorScheme.primary;
    final shown = c.url.replaceFirst(RegExp(r'^https://'), '');
    return Semantics(
      link: true,
      child: InkWell(
        key: ValueKey('citation-${c.id}'),
        onTap: () => unawaited(openCitation(context, c)),
        onLongPress: () {
          unawaited(Clipboard.setData(ClipboardData(text: c.url)));
          toast(context, '주소를 복사했습니다');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title,
                    style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
                const SizedBox(height: 3),
                Text(c.reference,
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.45)),
                const SizedBox(height: 3),
                Text(shown,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelSmall?.copyWith(
                        color: link, decoration: TextDecoration.underline, decorationColor: link)),
              ]),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(LucideIcons.externalLink, size: 16, color: link),
            ),
          ]),
        ),
      ),
    );
  }
}

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key, this.topics = const []});

  /// 먼저 보여 줄 주제들. 비어 있으면 전체.
  final List<String> topics;

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  late bool _all = widget.topics.isEmpty;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final focused = widget.topics.isNotEmpty;
    final shown = _all ? kCitations : citationsFor(widget.topics);
    final hint = t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5);
    final own = focused && !_all ? appSetNote(widget.topics) : null;

    return Scaffold(
      appBar: AppBar(title: const Text(kSourcesScreenTitle)),
      body: ListView(
        key: const Key('sources-list'),
        padding: const EdgeInsets.all(16),
        children: [
          MbCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(kSourcesIntro, style: t.textTheme.bodyMedium?.copyWith(height: 1.5)),
              const SizedBox(height: 4),
              Text(kSourcesTapHint, style: hint),
            ]),
          ),
          const Note(
            key: Key('sources-disclaimer'),
            tone: Tone.warn,
            title: '의료 안내',
            text: kMedicalDisclaimer,
          ),
          if (focused)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: Text(
                      _all
                          ? '전체 출처 ${kCitations.length}개'
                          : '${topicLabels(widget.topics)} — 관련 출처 ${shown.length}개',
                      style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  key: const Key('sources-toggle'),
                  onPressed: () => setState(() => _all = !_all),
                  child: Text(_all ? '관련만 보기' : '모든 출처 보기'),
                ),
              ]),
            ),
          /* 시트와 같은 한 줄 — 앱이 정한 기준이면 아래 문헌은 관련 근거입니다. */
          if (own != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(own,
                  key: const Key('sources-app-set'),
                  style: t.textTheme.bodySmall?.copyWith(height: 1.45, fontWeight: FontWeight.w600)),
            ),
          for (final g in kCitationGroups)
            if (shown.any((c) => c.group == g)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 0, 8),
                child: Text(g,
                    style: t.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700, color: t.hintColor)),
              ),
              MbCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, c) in shown.where((c) => c.group == g).indexed) ...[
                    if (i > 0) Divider(height: 1, color: t.dividerColor),
                    CitationTile(c),
                  ],
                ]),
              ),
            ],
        ],
      ),
    );
  }
}
