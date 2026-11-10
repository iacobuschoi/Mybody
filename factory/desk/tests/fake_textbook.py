"""시험용 가짜 교과서 — 절 제목 · 예제 · 그림(선) · 표 · 식 번호 · 장 끝 연습문제(한 단 / 두 단)"""
import pymupdf


def _body(page, x, y, text, size=10, w=470, bold=False):
    font = "hebo" if bold else "helv"
    rc = page.insert_textbox(pymupdf.Rect(x, y, x + w, y + 400), text, fontsize=size, fontname=font)
    used = 400 - rc if rc >= 0 else 400
    return y + used + 4


def make(path, two_column_problems=False):
    doc = pymupdf.open()
    # 1쪽: 3장 · 3.2 절(제목에도 「3.2」 가 있음 — 문제로 잘못 집으면 안 됨)
    p = doc.new_page()
    y = _body(p, 60, 50, "Chapter 3 Resistive Circuits", 18, bold=True)
    y = _body(p, 60, y + 10, "3.2 Kirchhoff's Laws", 14, bold=True)
    y = _body(p, 60, y, "Kirchhoff's voltage law states that the algebraic sum of voltages around a loop is zero. " * 4)
    y = _body(p, 60, y, "V = I R                                                                    (3.12)")
    y = _body(p, 60, y + 6, "Example 3.2", 11, bold=True)
    y = _body(p, 60, y, "Find the current in the circuit of Figure 3.4 when the source is 12 V and R = 6 ohm.")
    y = _body(p, 60, y, "Solution: By Ohm's law, I = 12 / 6 = 2 A. " * 2)
    y = _body(p, 60, y + 4, "Practice Problem 3.2  Repeat with R = 4 ohm.", bold=True)
    # 그림: 선으로 그린 회로 + 아래 캡션
    top = y + 10
    p.draw_rect(pymupdf.Rect(200, top, 380, top + 110), color=(0, 0, 0), width=1)
    p.draw_line((200, top + 55), (380, top + 55), color=(0, 0, 0))
    p.insert_text((210, top + 30), "R1", fontsize=9)
    y = _body(p, 60, top + 118, "Figure 3.4 A simple resistive circuit.", 9)
    # 2쪽: 표 3.1 (캡션 위, 표 아래)
    p = doc.new_page()
    y = _body(p, 60, 60, "Table 3.1 Resistor color codes.", 9)
    t0 = y + 2
    for i in range(5):
        p.draw_line((80, t0 + i * 18), (420, t0 + i * 18), color=(0, 0, 0))
        p.insert_text((90, t0 + i * 18 + 13), f"color {i}   value {i}", fontsize=9)
    y = _body(p, 60, t0 + 110, "More body text that follows the table and should not be cropped. " * 5)
    # 3쪽~: 연습문제
    p = doc.new_page()
    y = _body(p, 60, 50, "Problems", 14, bold=True)
    probs = [
        ("3.1", "Find the voltage across a 10 ohm resistor carrying 3 A."),
        ("3.2", "For the circuit in Fig. 3.4, find I when R = 3 ohm. Use Eq. (3.12) and the values in Table 3.1. "
                "Compare your answer with Example 3.2."),
        ("3.3", "Determine the power absorbed by each element in Figure P3.3."),
        ("3.4", "A battery of 9 V is connected to two resistors in series. Find the current."),
    ]
    if not two_column_problems:
        for n, t in probs:
            y = _body(p, 60, y + 6, f"{n}  {t}", 10)
            if n == "3.3":
                p.draw_rect(pymupdf.Rect(150, y + 4, 300, y + 70), color=(0, 0, 0))
                y = _body(p, 60, y + 76, "Figure P3.3", 9)
    else:
        xs = [(60, 60), (60, 300), (320, 60), (320, 300)]
        for (n, t), (x, yy) in zip(probs, xs):
            _body(p, x, yy, f"{n}  {t}", 10, w=230)
        for i in range(6):                       # 두 단으로 보이게 각 단에 줄을 더 채움
            _body(p, 60, 420 + i * 30, "filler line for left column text", 10, w=230)
            _body(p, 320, 420 + i * 30, "filler line for right column text", 10, w=230)
    # 4장
    p = doc.new_page()
    y = _body(p, 60, 50, "Chapter 4 Methods of Analysis", 18, bold=True)
    y = _body(p, 60, y + 10, "Problems", 14, bold=True)
    y = _body(p, 60, y + 6, "4.1  Use nodal analysis to find v1 in the circuit.", 10)
    y = _body(p, 60, y + 6, "4.2  Use mesh analysis to find i2.", 10)
    doc.save(path)
