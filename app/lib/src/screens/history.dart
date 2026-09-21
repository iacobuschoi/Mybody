/* =============================================================================
 * history.dart — P10 측정 기록
 *
 * 지울 때 **딸린 사진도 같이 지웁니다.** 예전에는 측정만 지우고 사진을
 * 두고 왔습니다. 사용자는 "이 측정을 지웠다" 고 생각하는데 결과지 사진은
 * 기기에 남아 있었고, 어디서도 안 보이니 지울 방법도 없었습니다.
 * 결과지에는 보통 이름·나이·성별이 같이 인쇄돼 있습니다.
 * ========================================================================== */
import 'package:flutter/material.dart';
import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import 'scandetail.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Scope.of(context);
    final scans = app.store.sortedScans().reversed.toList();
    final profile = app.profile ?? core.kSeedProfile;
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('측정 기록')),
      body: scans.isEmpty
          ? const EmptyState(title: '아직 측정이 없습니다')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: scans.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final s = scans[i];
                final d = core.derive(s, profile);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dateK(s['measuredAt'])),
                  subtitle: Text(
                      '${n1(d['weightKg'])}kg · 근 ${n1(d['smmKg'])} · 지 ${n1(d['bfmKg'])} '
                      '(${n1(d['pbfPct'])}%)',
                      style: t.textTheme.bodySmall),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => ScanDetailScreen(scanId: s['id']))),
                );
              },
            ),
    );
  }
}
