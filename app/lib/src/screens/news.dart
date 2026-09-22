/* =============================================================================
 * news.dart — 친구 소식
 *
 * **좋은 소식만 흐릅니다.** 늘어난 것만 줄이 되므로 "안 했다" 는 구조적으로
 * 여기 못 올라옵니다. 찌르기를 안 만드는 것과 같은 이유입니다 — 부재는
 * 조용해야 합니다.
 *
 * 시각도 정직하게 적습니다: 친구가 **언제 운동했는지는 모릅니다.** 스냅샷에
 * 그 시각이 없습니다. 아는 건 "내가 언제 알게 됐는가" 뿐이라 그것만 적고,
 * 아래에 그렇다고 써 둡니다.
 * ========================================================================== */
import 'package:flutter/material.dart';

import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key, required this.names});
  /// friendId → 보여 줄 이름. 소식 줄에는 이름을 안 박아 둡니다 —
  /// 박아 두면 친구가 이름을 바꾼 뒤에도 옛 이름이 계속 남습니다.
  final Map<String, String> names;

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  @override
  void initState() {
    super.initState();
    /* 열었으면 읽은 것입니다. 한 박자 뒤로 미뤄 첫 그림이 끝난 다음에
       표시를 바꿉니다 — 안 그러면 새 소식 표시가 보이기도 전에 사라집니다. */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Scope.of(context).news?.markRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = Scope.of(context).news?.list() ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('소식')),
      body: items.isEmpty
          ? const EmptyState(
              title: '아직 소식이 없습니다',
              detail: '친구가 이번 주에 운동을 체크하면 여기에 쌓입니다.\n'
                  '안 한 것은 올라오지 않습니다.',
            )
          : ListView(padding: const EdgeInsets.all(16), children: [
              for (final raw in items)
                Builder(builder: (_) {
                  final it = (raw as Map).cast<String, Object?>();
                  final id = '${it['friendId']}';
                  final name = widget.names[id] ?? '친구';
                  final kept = it['keptDays'];
                  final planned = it['plannedDays'];
                  return MbCard(
                    child: Row(children: [
                      Avatar(displayName: name, id: id, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichishText(
                              '**$name**님이 이번 주 $kept일째 운동했습니다'
                              '${planned == null ? '' : ' (계획 $planned일)'}',
                              style: t.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 2),
                            Text('내가 알게 된 때 · ${dateShort(it['at'])}',
                                style: t.textTheme.labelSmall
                                    ?.copyWith(color: t.hintColor)),
                          ],
                        ),
                      ),
                    ]),
                  );
                }),
              const SizedBox(height: 4),
              Text(
                '친구가 언제 운동했는지는 앱이 모릅니다 — 서버가 보내 주는 것은 '
                '이번 주에 며칠 지켰는지뿐입니다. 그래서 「내가 알게 된 때」로 적습니다.',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5),
              ),
            ]),
    );
  }
}
