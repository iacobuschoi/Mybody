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
 * ========================================================================== */
import 'api.dart';
import 'app_state.dart';
import 'sync_queue.dart';

void wirePublishing(AppState app, Api api, SyncQueue? queue) {
  app.store.currentUser = () => api.signedIn ? api.token : null;
  app.store.publishSnapshot = (weekStart, snap) {
    if (queue == null) return {'ok': false, 'reason': '큐가 없습니다'};
    queue.add('snapshot', {'weekStart': weekStart, 'payload': snap});
    return {'ok': true, 'queued': true};
  };
  /* 로그인하는 순간에도 한 번. 저장이 있어야만 올라가면, 방금 로그인한
     사람은 다음에 뭔가를 바꿀 때까지 친구 화면에서 빈 사람입니다. */
  api.addListener(() {
    if (api.signedIn) app.store.publishWeekly();
  });
}
