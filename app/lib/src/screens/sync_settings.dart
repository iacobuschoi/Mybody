/* =============================================================================
 * sync_settings.dart — 설정의 「내 계정에 기록 동기화」 카드
 *
 * 스위치 하나, 마지막으로 맞춘 때 한 줄, 「지금 동기화」 단추. 스위치는
 * settings.cloudSync 에 남고 cloud.dart 가 그걸 봅니다 — 끄면 올리지도
 * 받지도 않습니다. 설치할 때 온보딩이 같은 스위치를 먼저 묻습니다.
 *
 * 로그인이 안 돼 있으면 스위치는 그대로 두고(다음에 로그인하면 그대로
 * 먹습니다) 로그인이 필요하다고만 말합니다.
 * ========================================================================== */
import 'package:flutter/material.dart';

import '../api.dart';
import '../cloud.dart';
import '../scope.dart';
import '../ui/widgets.dart';

/// [CloudSync.lastResult] 를 사람 말로. 모르는 값은 빈 글자.
String syncResultLabel(String? r) => switch (r) {
      'merged' || 'imported' || 'pushed' => '합침',
      'same' => '같음',
      'offline' => '오프라인',
      'rejected' => '서버가 거절함',
      'stale' => '보내는 중',
      'off' => '꺼짐',
      _ => '',
    };

/// 「지금 동기화」 를 누른 뒤 띄우는 말.
String syncNowMessage(String r, {String? error}) => switch (r) {
      'merged' => '합쳤습니다',
      'imported' => '계정의 기록을 받았습니다',
      'pushed' => '이 기기의 기록을 올렸습니다',
      'same' => '이미 같습니다',
      'offline' => '서버에 닿지 못했습니다 — 나중에 다시 합니다',
      'rejected' => error ?? '서버가 거절했습니다',
      'stale' => '보내는 중입니다 — 잠시 뒤 다시 확인합니다',
      'off' => '동기화가 꺼져 있습니다',
      _ => error ?? '지금은 할 것이 없습니다',
    };

/// '방금' · 'N분 전' · 'N시간 전' · 'N일 전'.
String agoLabel(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.isNegative || d.inMinutes < 1) return '방금';
  if (d.inHours < 1) return '${d.inMinutes}분 전';
  if (d.inDays < 1) return '${d.inHours}시간 전';
  return '${d.inDays}일 전';
}

class SyncSettingsCard extends StatelessWidget {
  const SyncSettingsCard({super.key, required this.cloud, required this.api, this.now});

  /// 없으면(시험 등) 스위치만 있고 상태 줄은 없습니다.
  final CloudSync? cloud;
  final Api api;

  /// 시험에서 시계를 세워 두려고 뚫어 놓은 구멍입니다.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final c = cloud;
    if (c == null) return _body(context, null);
    return ListenableBuilder(listenable: c, builder: (context, _) => _body(context, c));
  }

  Widget _body(BuildContext context, CloudSync? c) {
    final app = Scope.of(context);
    final t = Theme.of(context);
    final settings = ((app.state['settings'] as Map?) ?? const {}).cast<String, Object?>();
    final on = CloudSync.enabledIn(app.state);

    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('내 계정에 기록 동기화'),
          subtitle: Text('기기를 바꾸거나 두 기기를 같이 써도 기록이 합쳐집니다. 사진은 안 올라갑니다.',
              style: t.textTheme.labelSmall),
          value: on,
          onChanged: (v) => app.store.set({'settings': {...settings, 'cloudSync': v}}),
        ),
        if (!api.signedIn)
          Text('로그인하면 동기화됩니다 — 지금은 이 기기에만 저장됩니다.',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor))
        else if (on) ...[
          Row(children: [
            Expanded(
              child: Text(_status(c), style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
            ),
            if (c != null)
              OutlinedButton(
                onPressed: c.busy ? null : () => _syncNow(context, c),
                child: Text(c.busy ? '맞추는 중…' : '지금 동기화'),
              ),
          ]),
          if (c?.lastError != null && c?.lastResult != 'offline')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(c!.lastError!, style: t.textTheme.labelSmall?.copyWith(color: mb(context).bad)),
            ),
        ] else
          Text('꺼져 있습니다 — 이 기기의 기록은 이 기기에만 남습니다.',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
      ]),
    );
  }

  String _status(CloudSync? c) {
    final at = c?.lastSyncedAt;
    if (at == null) return '아직 동기화하지 않았습니다';
    final label = syncResultLabel(c?.lastResult);
    final ago = agoLabel(at, (now ?? DateTime.now)());
    return label.isEmpty ? '마지막 동기화 $ago' : '마지막 동기화 $ago · $label';
  }

  Future<void> _syncNow(BuildContext context, CloudSync c) async {
    final r = await c.syncNow();
    if (!context.mounted) return;
    toast(context, syncNowMessage(r, error: c.lastError));
  }
}
