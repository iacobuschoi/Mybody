"""화면을 「꺼진 것처럼」 — 맥은 화면을 재우지 않고, 모니터에 보내는 색만 검게(감마 표를 0 으로) 합니다.

    deskd ──mac.display_off()──▶ python -m desk.blackout --parent <deskd pid>
                                   · 연결된 화면마다 감마 0 (0.5초마다 다시 — 새로 꽂은 화면 · Night Shift 가 되돌려도)
                                   · caffeinate -d (macOS 의 「10분 뒤 화면 끄기」가 진짜로 재우지 않게)
                                   · 진짜 키보드 · 마우스 클릭을 보면 stdout 에 "input" 한 줄
          ◀─mac.display_on()──── 끝냄 → 감마는 macOS 가 원래대로(ColorSync) 되돌림

왜 이렇게: pmset displaysleepnow 로 재우면 화면 캡처(CGDisplayCreateImage)가 검게 나와 폰 비서 앱(7071)의 화면 보기가
안 됩니다. 감마는 모니터로 나가는 신호 끝에서만 바뀌므로 캡처 · 창 배치 · 화면 목록은 그대로입니다.
DDC(모니터 전원 대기 · 밝기 0)는 이 맥에선 안 됩니다 — M1 의 HDMI(HKC TV)는 DDC 가 막혀 있고, S22E450 도 응답이
없습니다(m1ddc 로 읽으면 엉터리 값, 2026-10-05). 그래서 백라이트는 켜진 채 검은 화면입니다.

폰 앱이 넣는 클릭 · 글자(desk/phone.py)는 PHONE_TAG 를 달고 오므로 「진짜 입력」으로 치지 않습니다 — 폰으로 조작해도
방 화면은 검은 채. 마우스 움직임만으로는 깨지 않습니다(손 마우스 · 책상 흔들림).
부모(deskd)가 죽으면 같이 끝나 화면이 돌아옵니다.
"""
from __future__ import annotations

import os
import subprocess
import sys
import threading
import time

PHONE_TAG = 0x7071D35C            # kCGEventSourceUserData — 폰 앱이 넣은 입력 표시


def _displays(Q) -> list[int]:
    _, ids, n = Q.CGGetOnlineDisplayList(16, None, None)
    return list(ids[:n])


def black(Q) -> int:
    z = [0.0, 0.0]
    n = 0
    for d in _displays(Q):
        if Q.CGSetDisplayTransferByTable(d, 2, z, z, z) == 0:
            n += 1
    return n


def _watch_input(Q) -> None:
    """진짜 키보드 · 클릭을 듣기만 함(막지 않음). 권한이 없으면 조용히 없이 감"""
    kinds = (Q.kCGEventKeyDown, Q.kCGEventLeftMouseDown, Q.kCGEventRightMouseDown, Q.kCGEventOtherMouseDown)
    mask = 0
    for k in kinds:
        mask |= Q.CGEventMaskBit(k)
    last = [0.0]

    def cb(proxy, kind, ev, refcon):  # noqa: ARG001
        if kind in kinds and Q.CGEventGetIntegerValueField(ev, Q.kCGEventSourceUserData) != PHONE_TAG \
                and time.time() - last[0] > 1:
            last[0] = time.time()
            print("input", flush=True)
        return ev

    tap = Q.CGEventTapCreate(Q.kCGSessionEventTap, Q.kCGHeadInsertEventTap, Q.kCGEventTapOptionListenOnly,
                             mask, cb, None)
    if tap is None:
        print("no-tap", flush=True)
        return
    src = Q.CFMachPortCreateRunLoopSource(None, tap, 0)
    Q.CFRunLoopAddSource(Q.CFRunLoopGetCurrent(), src, Q.kCFRunLoopCommonModes)
    Q.CGEventTapEnable(tap, True)
    Q.CFRunLoopRun()


def main(argv: list[str]) -> int:
    import Quartz as Q
    parent = int(argv[argv.index("--parent") + 1]) if "--parent" in argv else os.getppid()
    caf = subprocess.Popen(["caffeinate", "-d", "-w", str(os.getpid())],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"black {black(Q)}", flush=True)

    def keep() -> None:
        while True:
            time.sleep(0.5)
            try:
                os.kill(parent, 0)
            except OSError:
                break
            black(Q)
        Q.CGDisplayRestoreColorSyncSettings()
        caf.terminate()
        os._exit(0)

    def stdin_gone() -> None:                      # deskd 가 파이프를 닫으면(끝나면) 바로 끝
        sys.stdin.read()
        Q.CGDisplayRestoreColorSyncSettings()
        caf.terminate()
        os._exit(0)

    threading.Thread(target=keep, daemon=True).start()
    threading.Thread(target=stdin_gone, daemon=True).start()
    _watch_input(Q)
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
