/* =============================================================================
 * source_link.dart — 권장값 옆의 작은 「출처」 링크
 *
 * 애플 심사(1.4.1)는 "출처가 쉽게 찾아져야 한다" 고 했습니다. 설정 깊숙이 목록
 * 하나만 두면 숫자를 보는 자리에서는 안 보입니다. 그래서 칼로리 · 단백질 · 기간 ·
 * 세트 × 반복 같은 숫자가 있는 자리마다 **같은 모양의** 작은 링크를 둡니다.
 * 누르면 그 숫자에 해당하는 문헌만 아래 시트로 뜨고(누르면 원문이 앱 밖에서 열림),
 * 맨 아래 「모든 출처 보기」 가 설정의 「근거 · 출처」 화면으로 갑니다.
 *
 * 모양은 하나뿐입니다 — 화면마다 다르게 그리면 같은 것인지 모릅니다.
 * ========================================================================== */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../citations.dart';
import '../screens/sources.dart';

/// 권장값 옆의 「출처」 링크. [topics] 는 [kSourceTopics] 의 열쇠입니다. 비어 있으면
/// 시트 없이 「근거 · 출처」 전체 화면을 엽니다(온보딩처럼 한 주제가 아닌 자리).
///
/// 누르는 자리는 적어도 44 × 32 — 글자(12pt)와 아이콘만 누르게 하면 높이가 18pt 남짓이라
/// 아이패드 호환 모드에서 잘 안 눌립니다(HIG 권장 44pt). 모양은 그대로 작게, 누르는 자리만
/// 넓힙니다. [inline] 은 문장 끝에 붙일 때(Note) — 위아래 여백 없이 글줄 높이 안에 듭니다
/// (문장 속 링크는 글줄보다 키우면 줄 간격이 벌어집니다). [dense] 는 높이가 정해진 자리
/// (키보드 위에 저장 단추가 보여야 하는 시트의 제목 줄)에서 누르는 자리를 44 × 24 로 —
/// 제목(titleMedium) 한 줄 높이라 줄이 늘지 않습니다.
class SourceLink extends StatelessWidget {
  const SourceLink(this.topics, {super.key, this.label = '출처', this.inline = false, this.dense = false});
  final List<String> topics;
  final String label;
  final bool inline;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: '$label 보기',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => unawaited(
          topics.isEmpty
              ? Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SourcesScreen()))
              : showSourcesSheet(context, topics),
        ),
        child: ConstrainedBox(
          constraints: inline
              ? const BoxConstraints()
              : BoxConstraints(
                  minHeight: dense ? kSourceLinkDenseHeight : kSourceLinkMinHeight,
                  minWidth: kSourceLinkMinWidth,
                ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: inline ? 0 : 2),
            /* 자리가 아주 좁으면(큰 글자 · 좁은 폰에서 옆 글이 폭을 다 쓸 때 — 체크인 「계획 N주차」
               머리는 390px · 2배에서 제목 칸이 9px 였습니다) 넘치지 않고 작게 그립니다. 넉넉하면
               제 크기 그대로. */
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.bookMarked, size: 12, color: color),
                  const SizedBox(width: 3),
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「출처」 링크(문장 속이 아닌 것)의 누르는 자리 최소 크기.
const double kSourceLinkMinHeight = 32;
const double kSourceLinkMinWidth = 44;

/// [SourceLink.dense] 의 누르는 자리 높이.
const double kSourceLinkDenseHeight = 24;

/// [topics] 의 출처를 아래 시트로. 맨 아래 「모든 출처 보기」 는 전체 목록 화면으로.
///
/// 시트 안에 제 [ScaffoldMessenger] · [Scaffold] 를 둡니다 — 「링크를 열지 못했습니다」 ·
/// 「주소를 복사했습니다」 토스트가 바깥 화면의 Scaffold 로 가면 시트 밑에 깔려 안 보입니다.
/// Scaffold 는 DraggableScrollableSheet 안쪽(시트 크기)이라 시트가 화면을 다 덮지 않습니다.
Future<void> showSourcesSheet(BuildContext context, List<String> topics) {
  final nav = Navigator.of(context);
  final list = citationsFor(topics);
  final own = appSetNote(topics);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final t = Theme.of(ctx);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (ctx, sc) => ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              top: false,
              child: ListView(
                key: const Key('sources-sheet'),
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  Text('출처', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    topicLabels(topics),
                    style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5),
                  ),
                  Text(
                    kSourcesTapHint,
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5),
                  ),
                  /* 문헌이 그 숫자를 그대로 주지 않는 주제(앱이 정한 기준)면 그렇다고 — 아래
                     목록을 그 숫자의 출처로 읽지 않게. */
                  if (own != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      own,
                      key: const Key('sources-app-set'),
                      style: t.textTheme.bodySmall?.copyWith(height: 1.45, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 6),
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: t.dividerColor),
                    CitationTile(list[i]),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    kMedicalDisclaimer,
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('sources-all'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      unawaited(nav.push(MaterialPageRoute(builder: (_) => const SourcesScreen())));
                    },
                    icon: const Icon(LucideIcons.library, size: 18),
                    label: const Text('모든 출처 보기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
