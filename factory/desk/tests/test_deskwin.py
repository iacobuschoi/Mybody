"""책상 화면 지킴이(desk/deskwin.py) — 가짜 화면 · 창으로 (진짜 사파리는 안 건드림)."""
import unittest

from desk import deskwin

MAIN = (0, 0, 1280, 768)
DESK = (1280, 0, 640, 1024)


class FakeAX:
    def __init__(self, wins, trusted=True):
        self.wins = wins           # pid → [{"title", "frame", "min", "full"}]
        self.ok = trusted
        self.hidden = {}

    def trusted(self):
        return self.ok

    def windows(self, pid):
        return self.wins.get(pid, [])

    def app(self, pid):
        return ("app", pid)

    def title(self, w):
        return w["title"]

    def flag(self, el, attr):
        if isinstance(el, tuple):
            return self.hidden.get(el[1], False)
        return {"AXMinimized": w_get(el, "min"), "AXFullScreen": w_get(el, "full")}[attr]

    def set_flag(self, el, attr, v):
        if isinstance(el, tuple):
            self.hidden[el[1]] = v
        else:
            el["min"] = v

    def frame(self, w):
        return w["frame"]

    def move(self, w, rect):
        w["frame"] = tuple(rect)


def w_get(w, k):
    return w.get(k, False)


def keeper(ax, screens=(MAIN, DESK), pid=10):
    opened = []
    k = deskwin.Keeper("http://127.0.0.1:7070/", ax=ax, screens_fn=lambda: screens,
                       windows_fn=lambda: [(p, w["frame"]) for p, ws in ax.wins.items() for w in ws],
                       pid_fn=lambda: pid, open_fn=opened.append)
    return k, opened


class Push(FakeAX):
    """y=0 에 놓으면 엉뚱하게 아래로 밀리는 화면 (실제 15:11)."""
    def move(self, w, rect):
        x, y, wd, ht = rect
        w["frame"] = (x, 309, wd, 1024 - 309) if y < 25 else (x, y, wd, min(ht, 1024 - y))


class KeeperTest(unittest.TestCase):
    def test_moves_desk_window_to_fill_second_screen(self):
        desk = {"title": "책상", "frame": (100, 100, 800, 600)}
        k, opened = keeper(FakeAX({10: [desk]}))
        self.assertIn("창 맞춤", k.step(now=0))
        self.assertEqual(desk["frame"], (1280, 25, 640, 999))
        self.assertEqual(k.step(now=1), "그대로")
        self.assertEqual(opened, [])

    def test_opens_window_when_missing_but_not_again_right_away(self):
        k, opened = keeper(FakeAX({10: [{"title": "Gmail", "frame": (0, 25, 800, 600)}]}))
        self.assertIn("새 창 열기", k.step(now=0))
        k.step(now=3)
        self.assertEqual(len(opened), 1)
        k.step(now=20)
        self.assertEqual(len(opened), 2)

    def test_evicts_other_windows_but_not_fullscreen(self):
        desk = {"title": "책상", "frame": DESK}
        other = {"title": "메모", "frame": (1300, 200, 400, 300)}
        full = {"title": "영상", "frame": (1290, 10, 300, 300), "full": True}
        ax = FakeAX({10: [desk], 20: [other, full]})
        k, _ = keeper(ax)
        self.assertIn("다른 창 옮김", k.step(now=0))
        self.assertFalse(deskwin.inside(other["frame"], DESK))
        self.assertTrue(deskwin.inside(other["frame"], MAIN))
        self.assertEqual(full["frame"], (1290, 10, 300, 300))
        self.assertEqual(desk["frame"], DESK)          # 이미 꽉 찬 창은 그대로

    def test_clamped_by_menu_bar_is_not_moved_every_tick(self):
        class Clamp(FakeAX):
            def move(self, w, rect):
                y = max(rect[1], 25)
                w["frame"] = (rect[0], y, rect[2], min(rect[3], 1024 - y))
        desk = {"title": "책상", "frame": (0, 0, 10, 10)}
        k, _ = keeper(Clamp({10: [desk]}))
        self.assertIn("창 맞춤", k.step(now=0))
        self.assertEqual(desk["frame"], (1280, 25, 640, 999))
        self.assertEqual(k.step(now=2), "그대로")

    def test_short_window_after_clamp_is_fixed(self):
        desk = {"title": "책상", "frame": (1280, 25, 640, 689)}   # 새 창이 뜨며 덜 커진 채 (실제 15:10)
        k, _ = keeper(FakeAX({10: [desk]}))
        self.assertIn("창 맞춤", k.step(now=0))
        self.assertEqual(desk["frame"], (1280, 25, 640, 999))

    def test_pushed_far_down_goes_under_menu_bar(self):
        desk = {"title": "책상", "frame": (1280, 25, 640, 689)}
        k, _ = keeper(Push({10: [desk]}))
        k.step(now=0)
        self.assertEqual(desk["frame"], (1280, 25, 640, 999))
        self.assertEqual(k.step(now=2), "그대로")

    def test_unminimizes_and_unhides(self):
        desk = {"title": "책상", "frame": DESK, "min": True}
        ax = FakeAX({10: [desk]})
        ax.hidden[10] = True
        k, _ = keeper(ax)
        msg = k.step(now=0)
        self.assertIn("최소화 풀기", msg)
        self.assertIn("사파리 보이기", msg)
        self.assertFalse(desk["min"])

    def test_nothing_without_second_screen_or_permission(self):
        k, opened = keeper(FakeAX({}), screens=(MAIN, None))
        self.assertEqual(k.step(now=0), "책상 화면 없음")
        k, opened = keeper(FakeAX({}, trusted=False))
        self.assertEqual(k.step(now=0), "권한 없음")
        self.assertEqual(opened, [])

    def test_evicted_fits_main(self):
        r = deskwin.evicted((1300, 0, 2000, 2000), MAIN)
        self.assertLessEqual(r[2], MAIN[2])
        self.assertGreaterEqual(r[1], 25)
        self.assertLessEqual(r[1] + r[3], MAIN[3])


class FakeQ:
    """미러링된 두 화면: 2 가 1 을 따라 함. 풀면 2 는 (0, 0) — 주 화면과 겹침 (오른쪽으로 옮겨야)."""
    kCGNullDirectDisplay = 0
    kCGConfigurePermanently = 2

    def __init__(self, origin_after=(0, 0)):
        self.mirror = {1: 0, 2: 1}
        self.bounds = {1: (0, 0, 1280, 768), 2: (0, 0, 640, 1024)}
        self.after = origin_after
        self.pending, self.commits = [], 0

    def CGGetOnlineDisplayList(self, n, a, b):
        return 0, (1, 2), 2

    def CGGetActiveDisplayList(self, n, a, b):
        return 0, tuple(d for d in (1, 2) if not self.mirror[d]), 2

    def CGMainDisplayID(self):
        return 1

    def CGDisplayMirrorsDisplay(self, d):
        return self.mirror[d]

    def CGDisplayBounds(self, d):
        from types import SimpleNamespace as N
        x, y, w, h = self.bounds[d]
        return N(origin=N(x=x, y=y), size=N(width=w, height=h))

    def CGBeginDisplayConfiguration(self, _):
        self.pending = []
        return 0, "cfg"

    def CGConfigureDisplayMirrorOfDisplay(self, cfg, d, master):
        self.pending.append(("mirror", d, master))

    def CGConfigureDisplayOrigin(self, cfg, d, x, y):
        self.pending.append(("origin", d, x, y))

    def CGCompleteDisplayConfiguration(self, cfg, how):
        assert how == self.kCGConfigurePermanently
        self.commits += 1
        for op in self.pending:
            if op[0] == "mirror":
                self.mirror[op[1]] = op[2]
                if not op[2]:
                    self.bounds[op[1]] = (*self.after, *self.bounds[op[1]][2:])
            else:
                self.bounds[op[1]] = (op[2], op[3], *self.bounds[op[1]][2:])
        return 0


class MirrorTest(unittest.TestCase):
    def test_unmirror_and_put_desk_screen_right_of_main(self):
        q = FakeQ()
        self.assertTrue(deskwin.mirrored(deskwin.mirror_state(q)))
        self.assertEqual(deskwin.unmirror(q, wait_s=0), 0)
        self.assertFalse(deskwin.mirrored(deskwin.mirror_state(q)))
        self.assertEqual(q.bounds[2], (1280, 0, 640, 1024))

    def test_unmirror_keeps_arrangement_macos_restored(self):
        q = FakeQ(origin_after=(1280, 0))
        self.assertEqual(deskwin.unmirror(q, wait_s=0), 0)
        self.assertEqual(q.bounds[2], (1280, 0, 640, 1024))
        self.assertEqual(q.commits, 1)                   # 이미 오른쪽 → 자리 옮기기 없음

    def test_not_mirrored(self):
        q = FakeQ()
        q.mirror[2] = 0
        self.assertFalse(deskwin.mirrored(deskwin.mirror_state(q)))


class KeepLoopTest(unittest.TestCase):
    def test_steps_only_on_start_and_screen_change(self):
        """켤 때 한 번, 그 뒤엔 화면 구성이 바뀔 때만 (주인 15:13: 계속 옮기지 말 것)."""
        import threading
        import time as _t
        state = {"screens": (MAIN, DESK), "calls": []}
        done = threading.Event()

        class K:
            mine = (1280, 25, 640, 999)

            def __init__(self, url):
                pass

            def screens(self):
                return state["screens"]

            def step(self, now):
                state["calls"].append(state["screens"])
                return "그대로"

            def _say(self, m):
                pass

        real_k, real_sleep = deskwin.Keeper, deskwin.time.sleep
        ticks = []

        def fake_sleep(s):
            ticks.append(s)
            n = len(ticks)
            if n == 3:
                state["screens"] = (MAIN, None)        # 화면이 잠듦
            elif n == 5:
                state["screens"] = (MAIN, DESK)        # 깸
            elif n >= 9:
                done.set()
                real_sleep(3600)
        deskwin.Keeper, deskwin.time.sleep = K, fake_sleep
        try:
            deskwin.keep("u", every_s=0)
            self.assertTrue(done.wait(5))
        finally:
            deskwin.Keeper, deskwin.time.sleep = real_k, real_sleep
            deskwin._running = False
        self.assertEqual(state["calls"], [(MAIN, DESK), (MAIN, None), (MAIN, DESK)])


if __name__ == "__main__":
    unittest.main()


class KeepMirrorLoopTest(unittest.TestCase):
    def test_unmirrors_once_then_fits_window(self):
        """깸 → 미러링이면 한 번 풀고 그다음 창을 맞춤. 풀기가 실패해도 같은 상태엔 되풀이 않음."""
        import threading
        import time as _t
        mir = ((1, 0), (2, 1))
        state = {"mirror": mir, "fail": True, "un": 0, "steps": 0}
        done = threading.Event()

        class K:
            mine = (1280, 25, 640, 999)

            def __init__(self, url):
                pass

            def screens(self):
                return (MAIN, None) if state["mirror"] == mir else (MAIN, DESK)

            def step(self, now):
                state["steps"] += 1
                return "그대로"

            def _say(self, m):
                pass

        def un():
            state["un"] += 1
            if state["fail"]:
                return 1001
            state["mirror"] = ((1, 0), (2, 0))
            return 0

        real_k, real_sleep = deskwin.Keeper, deskwin.time.sleep
        ticks = []

        def fake_sleep(s):
            ticks.append(s)
            n = len(ticks)
            if n == 4:
                self.assertEqual(state["un"], 1)          # 실패 뒤 되풀이 없음
                state["mirror"] = ((1, 0), (2, 0))       # 사람이 풂
            elif n == 6:
                state["mirror"], state["fail"] = mir, False   # 다시 미러링 (깸)
            elif n >= 10:
                done.set()
                real_sleep(3600)
        deskwin.Keeper, deskwin.time.sleep = K, fake_sleep
        try:
            deskwin.keep("u", every_s=0, mirror_fn=lambda: state["mirror"], unmirror_fn=un)
            self.assertTrue(done.wait(5))
        finally:
            deskwin.Keeper, deskwin.time.sleep = real_k, real_sleep
            deskwin._running = False
        self.assertEqual(state["un"], 2)
        self.assertEqual(state["mirror"], ((1, 0), (2, 0)))
        self.assertEqual(state["steps"], 3)               # 실패 뒤(화면 없음) · 사람이 푼 뒤 · 다시 푼 뒤 한 번씩
