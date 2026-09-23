#!/usr/bin/env python3
"""
play/make-shots.py — 폰 화면 캡처를 플레이 스토어 규격(1080×1920, 9:16)으로

  python3 play/make-shots.py 원본폴더 [출력폴더]

원본은 어떤 크기든 됩니다(에뮬레이터 1080×2400, 웹 780×1688 …). 각 장을
9:16 캔버스 안에 **통째로 맞춰** 넣고(둥근 모서리 · 그림자), 남는 자리는
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
    ('friend',   '친구에겐 원하는 정보만 공유해요'),
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
    top = BAND if cap else 60
    # 화면 **전체**를 캔버스 안에 맞춥니다(위 띠와 아래 여백을 뺀 자리). 폰 화면은
    # 9:16 보다 길쭉해서(1080×2400) 그대로 넣으면 아래가 잘립니다 — 잘라 내는 대신
    # 조금 줄여 통째로 보여 주고, 둥근 모서리와 옅은 그림자로 폰처럼 세웁니다.
    box_w, box_h = W - 2 * 60, H - top - 60
    scale = min(box_w / im.width, box_h / im.height)
    nw, nh = int(im.width * scale), int(im.height * scale)
    im = im.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new('RGB', (W, H), BG)
    x, y = (W - nw) // 2, top + (box_h - nh) // 2
    radius = 48
    # 그림자
    from PIL import ImageFilter
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([x, y + 14, x + nw, y + nh + 14], radius=radius, fill=(23, 23, 31, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    canvas.paste(shadow, (0, 0), shadow)
    # 둥근 모서리
    mask = Image.new('L', (nw, nh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, nw - 1, nh - 1], radius=radius, fill=255)
    canvas.paste(im, (x, y), mask)
    # 얇은 테두리
    ImageDraw.Draw(canvas).rounded_rectangle([x, y, x + nw - 1, y + nh - 1], radius=radius,
                                             outline=(210, 208, 230), width=3)
    if cap:
        d = ImageDraw.Draw(canvas)
        f = ImageFont.truetype(BOLD, 52)
        tw = d.textlength(cap, font=f)
        d.text(((W - tw) / 2, (BAND - 52) / 2 + 10), cap, font=f, fill=INK)
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
