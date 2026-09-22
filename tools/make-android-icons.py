# =============================================================================
# make-android-icons.py — 폰 홈 화면 아이콘을 만듭니다
#
#   python3 tools/make-android-icons.py
#
# 원본은 `prototype/assets/icon-512.png` 입니다 — 친구들이 지금 쓰는 웹 앱을
# 홈 화면에 얹었을 때 나오는 바로 그 아이콘입니다. 설치하는 앱이 다른 그림을
# 쓰면 같은 앱으로 안 보입니다.
#
# 두 벌을 만듭니다:
#
#   1. 옛날 방식(PNG 다섯 크기) — 안드로이드 7 이하.
#   2. adaptive icon — 안드로이드 8 이상. 바탕과 그림을 따로 줍니다.
#      이걸 안 주면 런처가 우리 사각 아이콘을 **흰 동그라미 안에 축소해서**
#      넣습니다. 보라 타일이 흰 테두리에 둘러싸여 작아 보입니다.
#
# adaptive icon 은 108dp 중에 가운데 66dp 만 확실히 보입니다 (런처가 모양을
# 마음대로 깎습니다). 그래서 막대를 그 안에 넣고, 바탕은 끝까지 채웁니다.
# =============================================================================
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'prototype', 'assets', 'icon-512.png')
RES = os.path.join(HERE, '..', 'app', 'android', 'app', 'src', 'main', 'res')

LEGACY = [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
          ('xxhdpi', 144), ('xxxhdpi', 192)]
# adaptive 는 108dp 짜리 정사각형입니다.
ADAPTIVE = [('mdpi', 108), ('hdpi', 162), ('xhdpi', 216),
            ('xxhdpi', 324), ('xxxhdpi', 432)]
SAFE = 66.0 / 108.0          # 런처가 절대 안 깎는 가운데 영역


def bg_color(im):
    """구석 픽셀 = 바탕색. 둥근 모서리라 진짜 구석은 투명일 수 있어서
    살짝 안쪽을 봅니다."""
    w, h = im.size
    return im.getpixel((w // 2, h // 12))[:3]


def cut_background(im, bg, tol=60):
    """바탕색에 가까운 픽셀을 투명하게. 막대는 흰색·하늘색·주황이라
    보라와 한참 떨어져 있어서 이 정도 여유로 깨끗하게 떨어집니다."""
    out = im.copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0 or (abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2])) < tol:
                px[x, y] = (r, g, b, 0)
    return out


def main():
    if not os.path.exists(SRC):
        print('원본이 없습니다: ' + SRC)
        return 1
    src = Image.open(SRC).convert('RGBA')
    bg = bg_color(src)
    print('바탕색 #%02X%02X%02X' % bg)

    bars = cut_background(src, bg)
    if bars.getchannel('A').getextrema()[1] == 0:
        print('막대를 못 골라냈습니다 — 전부 투명해졌습니다')
        return 1

    for name, size in LEGACY:
        d = os.path.join(RES, 'mipmap-' + name)
        os.makedirs(d, exist_ok=True)
        src.resize((size, size), Image.LANCZOS).save(
            os.path.join(d, 'ic_launcher.png'))

    for name, size in ADAPTIVE:
        d = os.path.join(RES, 'mipmap-' + name)
        inner = int(round(size * SAFE))
        canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        small = bars.resize((inner, inner), Image.LANCZOS)
        off = (size - inner) // 2
        canvas.paste(small, (off, off), small)
        canvas.save(os.path.join(d, 'ic_launcher_foreground.png'))

    d = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android='
                '"http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')

    d = os.path.join(RES, 'values')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'ic_launcher_background.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<resources>\n'
                '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n'
                '</resources>\n' % bg)

    print('아이콘 %d개 + adaptive %d개 만들었습니다'
          % (len(LEGACY), len(ADAPTIVE)))
    return 0


sys.exit(main())
