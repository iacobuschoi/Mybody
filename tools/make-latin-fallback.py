# =============================================================================
# make-latin-fallback.py — CanvasKit 이 구글에서 받아 오던 마지막 한 건을
# 앱 안에서 해결합니다.
#
#   python3 tools/make-latin-fallback.py
#
# Flutter 웹(CanvasKit)은 앱이 **Roboto 라는 이름의 글꼴을 가지고 있지
# 않으면 무조건** fonts.gstatic.com 에서 Roboto 를 받아 옵니다. 쓰든 안
# 쓰든 받습니다. 엔진 쪽 코드가 그렇습니다:
#
#     if (!loadedRoboto) {
#       pendingDownloads.add(_downloadFont('Roboto', _robotoUrl, 'Roboto'));
#     }
#     (flutter_web_sdk/lib/_engine/engine/canvaskit/fonts.dart)
#
# 그래서 **Roboto 라는 이름표를 단 글꼴을 앱에 넣어 둡니다.** 그러면
# 위 조건이 거짓이 되고 요청이 아예 안 나갑니다.
#
# 내용물은 이미 앱에 있는 Pretendard 에서 **라틴 글자만 떼어낸 것**입니다.
# 통째로 또 넣으면 1.6MB 가 두 벌이 됩니다. 그렇다고 빈 껍데기를 넣으면,
# 글꼴이 안 정해진 글자가 어딘가에 남아 있을 때 그 자리가 네모가 됩니다 —
# 지금까지 받아 오던 Roboto 가 덮어 주던 자리가 바로 거기입니다.
# 라틴만 남기면 그 자리를 그대로 덮으면서 수십 KB 로 끝납니다.
# =============================================================================
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, '..', 'app', 'assets', 'fonts')

# 받아 오던 Roboto 가 덮어 주던 범위입니다 — 라틴, 라틴 확장, 문장부호,
# 통화기호, 글자꼴 기호, 화살표, 수학기호, 도형.
RANGES = ('U+0000-024F,U+0259,U+02B0-02FF,U+0300-036F,'
          'U+2000-206F,U+20A0-20BF,U+2100-214F,'
          'U+2190-21FF,U+2200-22FF,U+25A0-25FF')

PAIRS = [('Pretendard-Regular.ttf', 'Roboto-Latin-Regular.ttf'),
         ('Pretendard-Bold.ttf', 'Roboto-Latin-Bold.ttf')]


def main():
    for src_name, out_name in PAIRS:
        src = os.path.join(FONTS, src_name)
        out = os.path.join(FONTS, out_name)
        if not os.path.exists(src):
            print('원본이 없습니다: ' + src)
            return 1

        font = TTFont(src)
        opts = subset.Options()
        opts.desubroutinize = True
        opts.notdef_outline = True          # 네모가 나오면 네모라고 보이게
        opts.drop_tables += ['DSIG']
        opts.layout_features = ['*']
        sub = subset.Subsetter(options=opts)
        sub.populate(unicodes=subset.parse_unicodes(RANGES))
        sub.subset(font)
        font.save(out)

        n = len(TTFont(out).getBestCmap())
        print('%s: %d자, %.0fKB  (%s 에서)' % (
            out_name, n, os.path.getsize(out) / 1024.0, src_name))

        # 라틴 대문자 A 가 없으면 떼어내다 잘못 떼어낸 것입니다. 조용히
        # 빈 글꼴을 내보내면 "고쳤다" 고 적어 두고 화면은 네모가 됩니다.
        if ord('A') not in TTFont(out).getBestCmap():
            print('라틴 글자가 안 들어갔습니다 — 중단합니다')
            return 1
    return 0


sys.exit(main())
