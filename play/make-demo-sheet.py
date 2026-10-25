#!/usr/bin/env python3
"""
play/make-demo-sheet.py — 스토어 스크린샷용 **가짜** 체성분 결과지 그림

  python3 play/make-demo-sheet.py [출력.png]      (기본: app/test_shots/demo-sheet.png)

「인바디 올리기」 스크린샷에 사진이 붙은 모습을 보이려고 그립니다. 실제 사람의 결과지가
아니고, 숫자는 app/test_shots/shots_test.dart 의 가짜 사람(demoSheet)과 같습니다.
상표 · 기기 이름은 넣지 않습니다.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, 'app', 'assets', 'fonts', 'Pretendard-Regular.ttf')
BOLD = os.path.join(ROOT, 'app', 'assets', 'fonts', 'Pretendard-Bold.ttf')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'app', 'test_shots', 'demo-sheet.png')

W, H = 1200, 1600
INK, GRAY, LINE = (40, 40, 48), (120, 120, 130), (200, 200, 210)


def f(size, bold=False):
    path = BOLD if bold else FONT
    if not os.path.exists(path):
        path = BOLD
    return ImageFont.truetype(path, size)


paper = Image.new('RGB', (W, H), (252, 252, 250))
d = ImageDraw.Draw(paper)
d.text((60, 50), '체성분 분석 결과지', font=f(56, True), fill=INK)
d.text((60, 125), '이름 홍길동 (예시)   키 176cm   나이 31   성별 남   측정 예시 데이터', font=f(26), fill=GRAY)
d.line((60, 175, W - 60, 175), fill=INK, width=3)

d.text((60, 205), '체성분 분석', font=f(34, True), fill=INK)
rows = [('체수분 (L)', '43.6', '38.2 ~ 46.6'), ('단백질 (kg)', '11.8', '10.2 ~ 12.5'),
        ('무기질 (kg)', '4.1', '3.5 ~ 4.3'), ('체지방량 (kg)', '14.8', '7.4 ~ 14.8'),
        ('체중 (kg)', '74.3', '57.4 ~ 77.6')]
y = 265
for name, v, rng in rows:
    d.text((80, y), name, font=f(28), fill=INK)
    d.text((520, y), v, font=f(30, True), fill=INK)
    d.text((760, y), rng, font=f(26), fill=GRAY)
    d.line((60, y + 50, W - 60, y + 50), fill=LINE, width=1)
    y += 62

y += 30
d.text((60, y), '골격근 · 지방 분석', font=f(34, True), fill=INK)
y += 70
bars = [('체중', 74.3, 0.62), ('골격근량', 32.3, 0.58), ('체지방량', 14.8, 0.46)]
for name, v, frac in bars:
    d.text((80, y), name, font=f(28), fill=INK)
    d.rectangle((330, y + 6, 330 + int(640 * frac), y + 34), fill=(90, 90, 100))
    d.text((340 + int(640 * frac) + 14, y), f'{v}', font=f(28, True), fill=INK)
    y += 62

y += 30
d.text((60, y), '비만 분석', font=f(34, True), fill=INK)
y += 70
for name, v in [('BMI (kg/m²)', '24.0'), ('체지방률 (%)', '19.9'), ('복부지방률', '0.88'), ('내장지방레벨', '6')]:
    d.text((80, y), name, font=f(28), fill=INK)
    d.text((520, y), v, font=f(30, True), fill=INK)
    y += 58

y += 30
d.text((60, y), '신체변화', font=f(34, True), fill=INK)
y += 70
pts = [(0, 78.6), (1, 76.1), (2, 74.3)]
x0, x1 = 160, W - 160
for i, (k, v) in enumerate(pts):
    x = x0 + (x1 - x0) * k / 2
    yy = y + int((79 - v) * 30)
    d.ellipse((x - 9, yy - 9, x + 9, yy + 9), fill=INK)
    d.text((x - 30, yy - 50), f'{v}', font=f(24), fill=INK)
    if i:
        px = x0 + (x1 - x0) * pts[i - 1][0] / 2
        py = y + int((79 - pts[i - 1][1]) * 30)
        d.line((px, py, x, yy), fill=INK, width=3)
d.text((60, H - 70), '※ 앱 소개용 예시 결과지입니다. 실제 측정 기록이 아닙니다.', font=f(24), fill=GRAY)

# 책상 위에서 찍은 사진처럼: 살짝 기울이고 둘레는 회색 책상.
photo = Image.new('RGB', (1360, 1800), (196, 192, 186))
tilted = paper.rotate(1.2, resample=Image.BICUBIC, expand=True, fillcolor=(196, 192, 186))
photo.paste(tilted, ((photo.width - tilted.width) // 2, (photo.height - tilted.height) // 2))
photo = photo.filter(ImageFilter.GaussianBlur(0.6))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
photo.save(OUT)
print(OUT)
