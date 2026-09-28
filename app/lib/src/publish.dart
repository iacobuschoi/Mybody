/* =============================================================================
 * publish.dart — 저장할 때마다 이번 주 요약을 친구에게 올리는 고리
 *
 * 코어의 Store 는 저장할 때마다 publishWeekly() 를 부르는데, 그게 실제로
 * 어디로 가는지는 화면 쪽이 꽂아 줘야 합니다. 이 고리가 안 꽂혀 있어서
 * 앱은 주간 요약을 **한 번도** 안 올렸습니다 — 친구 기능의 절반이
 * 없었습니다. 웹 앱에서 같은 고장이 같은 이유로 있었습니다.
 *
 * 큐로 보냅니다. 서버에 못 닿으면 큐가 들고 있다가 망이 돌아오면 보냅니다.
 * 같은 주는 하나만 남습니다(큐가 겹치는 것을 지웁니다).
 *
 * **키 · 체중 추정으로 나눈 몸 숫자는 친구에게 안 나갑니다**(estimate.dart).
 * 친구 화면은 받은 숫자를 잰 값으로 읽습니다 — 공식으로 어림한 근육 · 지방을
 * 측정처럼 보내면 틀릴 수 있는 숫자가 남의 화면에서 사실이 됩니다. 몸 숫자는
 * 인바디에서만 나가고, 추정뿐이면 체중까지 뺍니다(친구 화면이 "kg · 근 · 지" 를
 * 한 줄로 찍습니다). 스냅샷을 만드는 코어(weeklySnapshot)는 원본 자바스크립트와
 * 짝이라 건드리지 않고, 나가기 직전 이 고리에서 거릅니다. 거르고 나니 남는 게
 * 없으면 안 올립니다 — "빈 스냅샷은 안 올립니다" 규칙 그대로입니다.
 *
 * **이 기기의 기록이 지금 로그인한 계정의 것일 때만** 올립니다(피드백 52 — local_owner.dart).
 * 예전엔 로그인하는 순간의 알림에서 앞 계정의 기록으로 만든 요약이 새 계정 이름으로 나갔습니다.
 * 요약에는 누구의 것인지(owner)를 실어, 서버가 다른 계정의 것이면 409 로 거절합니다.
 * ========================================================================== */
import 'package:mybody_core/mybody_core.dart' as core;

import 'api.dart';
import 'app_state.dart';
import 'estimate.dart';
import 'local_owner.dart';
import 'sync_queue.dart';

void wirePublishing(AppState app, Api api, SyncQueue? queue) {
  /* 칸의 주인이 지금 로그인이 아니면 "로그인 안 함" 과 같이 아무것도 안 올립니다. */
  app.store.currentUser = () => mayLeave(app, api) ? api.token : null;
  app.store.publishSnapshot = (weekStart, snap) {
    if (queue == null) return {'ok': false, 'reason': '큐가 없습니다'};
    final clean = withoutEstimatedBody(snap,
        scans: app.store.sortedScans(), plan: app.state['plan']);
    if (!core.Store.hasAnything(clean)) return {'ok': false, 'reason': '추정치뿐'};
    /* 요약을 만든 기록 칸의 주인 — 토큰이 아니라 칸의 것을 먼저 싣습니다(cloud.dart _owned 와 같은 까닭). */
    final owner = app.owner.current?.uid ?? api.userId;
    queue.add('snapshot', {
      'weekStart': weekStart,
      'payload': {...clean, if (owner != null) 'owner': owner},
    });
    return {'ok': true, 'queued': true};
  };
  /* 로그인하는 순간에도 한 번. 저장이 있어야만 올라가면, 방금 로그인한
     사람은 다음에 뭔가를 바꿀 때까지 친구 화면에서 빈 사람입니다. */
  api.addListener(() {
    if (api.signedIn) app.store.publishWeekly();
  });
}
