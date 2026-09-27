import datetime as dt
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from desk.briefing import compose, _line  # noqa: E402
from desk.mac import speakable  # noqa: E402

BODY = """단계: S4 구현 (3/7 기능)          마지막 갱신: 2026-10-02 21:10
한 일: 온보딩 · 기록 화면 머지
다음: 알림 · 통계 화면
막힘: 없음
주인 할 일: 플레이 콘솔 첫 등록 (15분)"""


class BriefingTest(unittest.TestCase):
    def test_reads_status_issue_body(self):
        self.assertEqual(_line(BODY, "단계"), "S4 구현 (3/7 기능)")
        self.assertEqual(_line(BODY, "주인 할 일"), "플레이 콘솔 첫 등록 (15분)")

    def test_compose_full(self):
        data = {"weather": "맑음 +18°C",
                "factory": {"ok": True, "apps": [{"name": "습관", "stage": "S4 구현 (3/7 기능)"},
                                                 {"name": "가계부", "stage": "S6 출시 준비"}],
                            "owner_todo": ["가계부: 플레이 콘솔 첫 등록 (15분)"], "waiting_approvals": 1, "red_main": 0},
                "lab": {"android": 2, "iphone": True, "runner": True}}
        s = compose(data, dt.datetime(2026, 10, 2, 21, 5))
        for want in ["좋은 저녁이에요", "10월 2일 금요일, 오후 9시 5분", "맑음 18도", "앱 2개", "습관은 구현 단계",
                     "가계부는 출시 단계", "승인 대기가 1건", "직접 하실 일이 1건", "실험실은 정상", "안드로이드 2대"]:
            self.assertIn(want, s)

    def test_compose_when_things_are_missing(self):
        s = compose({"weather": "", "factory": {"ok": False}, "lab": {"android": 0, "iphone": False, "runner": False}},
                    dt.datetime(2026, 10, 3, 8, 0))
        self.assertIn("좋은 아침이에요", s)
        self.assertIn("공장 상황은 지금 못 읽었어요", s)
        self.assertIn("실험실 확인이 필요해요 — 시험 러너 꺼짐, 아이폰 연결 안 됨.", s)

    def test_speakable_strips_markdown(self):
        s = speakable("## 결과\n- **습관** 앱: `flutter test` 통과했어요. 자세한 건 [링크](https://x.y) 보세요. 세 번째. 네 번째.")
        self.assertNotIn("**", s)
        self.assertNotIn("http", s)
        self.assertNotIn("네 번째", s)


if __name__ == "__main__":
    unittest.main()
