#!/usr/bin/env python3
"""
play/make-shots.py — 폰 화면 캡처를 플레이 스토어 규격(1080×1920, 9:16)으로

  python3 play/make-shots.py 원본폴더 [출력폴더]

원본은 어떤 크기든 됩니다(에뮬레이터 1080×2400, 웹 780×1688 …). 각 장을
9:16 캔버스에 **위를 맞춰** 넣고 — 앱은 위쪽이 중요합니다 — 남는 아래는
캔버스 색으로 채웁니다. 파일 이름이 CAPTIONS 에 있으면 위에 한 줄 설명을
얹습니다(글꼴은 앱이 쓰는 Pretendard).

플레이 요건: PNG/JPEG, 16:9 또는 9:16, 한 변 320~3840px, 알파 없음.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOLD = os.path.join(ROOT, 'app', 'assets', 'fonts', 'Pretendard-Bold.ttf')
W, H = 1080, 1920
BAND = 200                      # 위 설명 띠 높이
BG = (244, 243, 255)            # 연보라 종이
INK = (23, 23, 31)

# 파일 이름(확장자 빼고)에 이 글자가 들어 있으면 그 설명을 얹습니다. 순서대로
# 처음 맞는 것. 없으면 설명 없이 화면만.
CAPTIONS = [
    ('home',     '홈 — 최신 인바디와 변화량, 이번 주 운동'),
    ('upload',   '결과지 사진 한 장이면 숫자를 읽어 줍니다'),
    ('review',   '읽은 값을 검산하고 확인합니다'),
    ('goal',     '목표를 정하면 언제 닿는지 알려 줍니다'),
    ('intensity','기간과 강도를 고릅니다'),
    ('plan',     '주차별 운동·식단 계획'),
    ('food',     '오늘 먹은 것과 남은 탄단지'),
    ('progress', '체중 · 골격근 · 체지방 추이'),
    ('social',   '친구와 서로 응원합니다'),
    ('friend',   '친구의 이번 주 — 켠 것만 보입니다'),
]

def caption_for(name):
    low = name.lower()
    for key, text in CAPTIONS:
        if key in low:
            return text
    return None

def convert(src, dst):
    im = Image.open(src).convert('RGB')
    cap = caption_for(os.path.splitext(os.path.basename(src))[0])
    top = BAND if cap else 0
    box_h = H - top
    # 폭을 맞추고, 높이가 남으면 아래를 비우고, 넘치면 아래를 자릅니다.
    scale = W / im.width
    new_h = int(im.height * scale)
    im = im.resize((W, new_h), Image.LANCZOS)
    canvas = Image.new('RGB', (W, H), BG)
    if new_h > box_h:
        im = im.crop((0, 0, W, box_h))
    canvas.paste(im, (0, top))
    if cap:
        d = ImageDraw.Draw(canvas)
        f = ImageFont.truetype(BOLD, 52)
        tw = d.textlength(cap, font=f)
        d.text(((W - tw) / 2, (BAND - 52) / 2 - 6), cap, font=f, fill=INK)
    canvas.save(dst, optimize=True)

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    src_dir = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'play', '그림', '스크린샷')
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for name in sorted(os.listdir(src_dir)):
        if not name.lower().endswith(('.png', '.jpg', '.jpeg')):
            continue
        dst = os.path.join(out_dir, os.path.splitext(name)[0] + '.png')
        convert(os.path.join(src_dir, name), dst)
        n += 1
        print('  ✓', dst)
    print(f'{n}장 → {out_dir}')

if __name__ == '__main__':
    main()
