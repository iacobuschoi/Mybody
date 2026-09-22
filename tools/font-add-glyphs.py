# =============================================================================
# font-add-glyphs.py — 앱 글꼴에 **없는 글자를 채워 넣습니다**
#
# 앱에 넣어 둔 Noto Sans KR 에는 한글 11,172자가 다 있지만 −, ≈, ▸, ①, Δ
# 같은 기호가 빠져 있습니다. Flutter 는 글꼴에 없는 글자를 만나면
# fonts.gstatic.com 에서 받아 오려 합니다 — 망이 막힌 곳에서는 네모가 되고,
# 안 막힌 곳에서는 몸 관리 앱을 켤 때마다 구글에 신호가 갑니다.
#
# FreeSans 에 그 기호들이 있고 **단위가 1000 으로 같습니다**(Noto 와 동일).
# 그래서 크기를 다시 맞출 필요 없이 그대로 옮겨 붙일 수 있습니다.
# DejaVu 는 2048 이라 옮기면 그 글자만 커집니다 — 그래서 FreeSans 입니다.
#
# fontTools 의 merge 는 안 씁니다. FreeSans 의 수식 조판 표(MATH)에서
# 터지고, 떼어 내도 다음 표에서 또 터집니다. 우리가 원하는 건 글자 몇 개라
# **윤곽선과 폭만 직접 옮깁니다** — 합자·커닝은 한글 글꼴 것을 그대로 씁니다.
#
#   python3 tools/font-add-glyphs.py <대상.ttf> <코드포인트(16진)…>
# =============================================================================
import sys, os
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen

# 도너 후보. **크기 단위(upem)가 맞는 것끼리만 붙일 수 있습니다** — 단위가
# 다른 글꼴에서 떼어 오면 그 글자만 커지거나 작아집니다. 그래서 단위별로
# 나눠 두고, 대상 글꼴의 단위에 맞는 쪽에서 고릅니다.
#   1000 — FreeSans (NotoSansKR 이 1000 이었습니다)
#   2048 — DejaVu   (Pretendard 가 2048 입니다)
SRC = [
    '/usr/share/fonts/truetype/freefont/FreeSansBold.ttf',
    '/usr/share/fonts/truetype/freefont/FreeSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
]


def donor_for(target, need):
    """**단위가 같고** 필요한 글자를 다 가진 글꼴을 고릅니다.

    굵은 대상에는 굵은 도너를 먼저 봅니다 — 기호 몇 개가 굵지 않은 것과
    그 자리가 네모인 것 중에서는 앞쪽이 낫습니다."""
    upem = TTFont(target)['head'].unitsPerEm
    bold = 'Bold' in os.path.basename(target)
    cands = [p for p in SRC if os.path.exists(p)]
    if not bold:
        cands.sort(key=lambda p: 'Bold' in os.path.basename(p))
    for path in cands:
        f = TTFont(path)
        if f['head'].unitsPerEm != upem:
            continue
        cm = f.getBestCmap()
        if all(c in cm for c in need):
            return f, path
    return None, None


def main():
    target = sys.argv[1]
    cps = [int(x, 16) for x in sys.argv[2:]]
    if not cps:
        print('채울 글자가 없습니다')
        return 0

    dst = TTFont(target)
    have = set(dst.getBestCmap().keys())
    need = [c for c in cps if c not in have]
    if not need:
        print('%s: 이미 다 있습니다' % os.path.basename(target))
        return 0

    donor, used = donor_for(target, need)
    if donor is None:
        upem = dst['head'].unitsPerEm
        have = set()
        for path in SRC:
            if os.path.exists(path) and TTFont(path)['head'].unitsPerEm == upem:
                have |= set(TTFont(path).getBestCmap().keys())
        gone = [c for c in need if c not in have]
        print('단위 %d 짜리 도너 중에 이 글자를 가진 것이 없습니다:' % upem)
        # 여기서 멈춥니다. 조용히 건너뛰면 "고쳤다" 는 말과 달리 그 글자는
        # 여전히 네모가 됩니다 — 그게 원래 문제였습니다.
        print('  ' + ' '.join('%s U+%04X' % (chr(c), c) for c in gone))
        print('그 글자는 화면에서 빼거나 아이콘으로 그려야 합니다.')
        return 1

    if donor['head'].unitsPerEm != dst['head'].unitsPerEm:
        print('단위가 달라 옮기면 크기가 틀어집니다 — 중단합니다')  # 여기 오면 안 됩니다
        return 1

    dcmap = donor.getBestCmap()
    dset = donor.getGlyphSet()
    dhmtx = donor['hmtx']
    tglyf, thmtx = dst['glyf'], dst['hmtx']
    # **글자 목록은 하나입니다.**
    # dst.getGlyphOrder() 가 돌려주는 리스트는 glyf 표가 들고 있는 바로 그
    # 리스트입니다. `tglyf[name] = ...` 이 거기에 이름을 넣는데, 거기에
    # 대고 또 append 하면 이름이 두 번 들어갑니다 — 저장할 때
    # "목록 길이와 글자 수가 안 맞는다" 며 터집니다.
    # 넣는 일은 glyf 표에 맡기고, 우리는 이름이 겹치는지만 봅니다.
    order = dst.getGlyphOrder()

    # 세로쓰기 표가 있는 글꼴이면(한글 글꼴은 대개 있습니다) 새 글자의
    # 세로 폭을 기존 글자에서 그대로 빌려 옵니다.
    tvmtx = dst['vmtx'] if 'vmtx' in dst else None
    vdefault = tvmtx[order[1] if len(order) > 1 else order[0]] if tvmtx else None

    added = []
    for cp in need:
        src_name = dcmap[cp]
        name = 'uni%04X' % cp if cp <= 0xFFFF else 'u%05X' % cp
        while name in order:
            name += '_'

        # **합성 글자를 단순 윤곽선으로 풀어서** 옮깁니다.
        # 합성 글자는 다른 글자를 조각으로 참조하는데(①은 원 + 숫자),
        # 그 조각 이름은 대상 글꼴에 없습니다. 이름만 들고 오면 글자가
        # 빈 네모가 되거나 엉뚱한 모양이 됩니다.
        rec = DecomposingRecordingPen(dset)
        dset[src_name].draw(rec)
        pen = TTGlyphPen(None)
        rec.replay(pen)
        tglyf[name] = pen.glyph()        # 목록에는 이 줄이 알아서 넣습니다
        thmtx[name] = dhmtx[src_name]
        # **세로쓰기 폭도 같이 넣습니다.** 안 넣으면 글자 수(maxp)만
        # 늘고 vmtx 는 그대로라서, 저장된 글꼴이 **깨진 글꼴**이 됩니다.
        # 가로로 그리는 동안에는 티가 안 나다가, 이 글꼴을 제대로 읽는
        # 쪽에서 "vmtx 가 24바이트 모자랍니다" 하고 터집니다.
        if tvmtx is not None:
            tvmtx[name] = vdefault

        for table in dst['cmap'].tables:
            if table.isUnicode():
                table.cmap[cp] = name
        added.append(cp)

    dst.setGlyphOrder(tglyf.glyphOrder)
    dst['maxp'].numGlyphs = len(tglyf.glyphOrder)
    dst.save(target)

    after = set(TTFont(target).getBestCmap().keys())
    still = [c for c in need if c not in after]
    if still:
        print('못 넣은 글자: ' + ' '.join('U+%04X' % c for c in still))
        return 1
    print('%s: %d자 넣었습니다 (%s) — %s' % (
        os.path.basename(target), len(added), os.path.basename(used),
        ' '.join(chr(c) for c in added)))
    return 0


sys.exit(main())
