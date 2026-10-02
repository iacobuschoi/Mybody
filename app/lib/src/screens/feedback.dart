/* =============================================================================
 * feedback.dart — 앱 안 「의견 보내기」: 지금 화면 한 장 붙여서, 글은 안 써도
 *
 * 왜 있나
 *   시험판을 쓰는 친구가 "여기 이상해요" 를 말할 길이 카톡뿐이었습니다. 그러면
 *   주인이 "어느 화면? 몇 판?" 을 되묻고, 친구는 캡처를 찾아 대화방에 올리고
 *   설명을 칩니다. 두세 번 오가다 그만둡니다. 그래서 화면 옆에 늘 떠 있는 말풍선
 *   (feedback_bubble.dart) 하나로 끝나게 합니다 — 누르는 순간의 화면을 찍어 붙이고,
 *   판 · 기종 · 화면 이름은 앱이 채웁니다.
 *
 * 주인이 정한 것: "앱 안 의견보내기는 텍스트도 쓸수있게 해줘(안쓰고 그냥 보내도 됨)".
 *   · **화면이 먼저, 글은 덤.** 시트가 뜨면 캡처가 이미 붙어 있고 「보내기」 가
 *     켜져 있습니다 — 한 번 더 누르면 끝. 글 칸은 있지만 비워도 됩니다. 칸에
 *     커서를 먼저 두지 않습니다 — 키보드가 올라와 붙인 화면을 가립니다.
 *   · 「보내기」 는 사진 한 장이나 글 한 글자라도 있으면 켜집니다. 둘 다 없으면
 *     서버가 어차피 돌려보냅니다(누르고 나서 거절당하는 것보다 못 누르는 게 낫습니다).
 *
 * 찍는 법
 *   앱 맨 위(main.dart 의 MaterialApp.builder, edgeSafe 바깥)를 RepaintBoundary 로
 *   감싸 두고([appCaptureBoundary]) 그걸 PNG 로 굽습니다([captureAppScreen]).
 *   · **시트를 띄우기 전에** 찍습니다. 띄운 뒤에 찍으면 시트가 화면을 가립니다.
 *   · 배율은 기기 배율과 1.5 중 작은 것. 3배 폰에서 그대로 구우면 한 장이 2~3MB 라
 *     서버 상한(1.5MB)에 걸립니다. 1.5배로도 넘으면 1배로 한 번 더, 그래도 넘으면
 *     캡처 없이 엽니다 — 「사진 추가」 로 붙이면 됩니다. 3초 안에 못 구워도 캡처 없이
 *     엽니다(굽기가 안 끝나면 말풍선이 먹통으로 남습니다).
 *   · 앱이 그린 것만 찍힙니다. 상태 막대 · 키보드는 시스템 것이라 안 찍힙니다.
 *   · 말풍선 자신은 안 찍힙니다 — 경계의 **바깥**, 형제로 서 있습니다(feedback_bubble.dart
 *     의 appFrame).
 *
 * 갤러리 사진
 *   image_picker 로 여럿 고르되 남은 칸만큼(모두 3장). 긴 변 1600 · 품질 80 으로
 *   줄여 받습니다. 서버는 PNG · JPEG 만 받으므로(앞머리 바이트까지 봄) 그 밖의 것
 *   (WebP · HEIC · GIF)은 다시 그려 PNG 로, 1.5MB 를 넘으면 더 작게 다시 그립니다
 *   ([prepareFeedbackImage]). JPEG · PNG 에 숨은 찍은 곳(GPS)은 지웁니다
 *   ([scrubJpegLocation] · [scrubPngLocation]) — 의견을 보내는 사람은 집 위치를 보낼
 *   생각이 없습니다. 처리방침이 "위치 정보는 지우고 보냅니다" 라고 적은 그 약속이라
 *   그대로 보내는 길(PNG · JPEG)은 둘 다 거칩니다(다시 그리는 길은 애초에 안 따라옴).
 *
 * 보내기
 *   api.sendFeedback — 로그인했으면 그 계정에 묶이고, 아니면 익명으로 갑니다(서버는
 *   이 길에서 401 을 주지 않습니다). 판(0.2.17+310)은 새 판 확인기(update.dart)가
 *   이미 읽어 둔 것을, 없으면 플랫폼에서 읽습니다. 화면 이름은 연 곳의 앱바 제목
 *   (홈 · 식단 · 설정 …)을 [feedbackScreenName] 으로 — 처리방침이 "어느 화면에서
 *   보냈는지" 를 받는다고 적어 둔 그 칸입니다.
 *   · 성공하면 시트를 닫고 「보냈어요 — 고마워요!」.
 *   · 실패하면 **아무것도 버리지 않고** 시트 안에 까닭을 띄웁니다 — 다시 누르면
 *     됩니다. 써 둔 글이 날아가면 다시 안 씁니다. 하루 한도(429)는 "내일 다시".
 *     401 · 404 는 이 길이 없는 옛 서버입니다(새 서버는 이 길에서 401 을 안 줌).
 *   · 보내는 사이에 시트를 닫아도(끌어 내림 · 뒤로) 보내기는 이어지고, 결과는 연
 *     화면에 한 줄로 뜹니다 — 말없이 사라지면 같은 것을 또 보냅니다.
 *
 * 지키는 것
 *   · 키보드가 올라오면 시트가 그만큼 올라가고, 「보내기」 는 스크롤 **밖** 맨 아래에
 *     붙어 있어 늘 보입니다(글 칸이 5줄로 늘어도, 작은 폰에서도).
 *   · 두 번 눌러도 시트는 한 장([_live] · [_starting]).
 *   · **우리 모달끼리 겹치지 않게** — 찍는 중부터 시트가 닫힐 때까지를 [feedbackBusy] 로
 *     알립니다. 말풍선은 그동안 숨고, 테스터 인사(tester_welcome.dart)는 그동안 기다렸다가
 *     시트가 닫히면 한 번 뜹니다. 쓰던 의견 위를 인사가 덮으면 쓰던 것이 가려집니다.
 *   · 말풍선을 보일지([feedbackBubbleOn] · [feedbackBubbleLocked])는 여기 한 곳 — 말풍선과
 *     설정의 스위치가 같은 값을 봐서, 꾹 눌러 X 로 끌어다 치우면 설정 스위치가, 설정에서
 *     켜면 말풍선이 곧바로 따라옵니다. 비공개 시험 기간에는 치울 수 없습니다(아래).
 *   · 붙인 화면에 몸 숫자가 보일 수 있다는 한 줄 — 처리방침(docs/privacy.html
 *     「의견 보내기」)과 같은 말. 사진이 없으면 할 말이 아니라 숨깁니다.
 *   · 색은 전부 테마에서 — 어두운 테마에서도 같은 대비.
 *   · 시험이 캡처 · 갤러리를 바꿔 끼울 수 있게 [feedbackCapture] · [feedbackPick].
 * ========================================================================== */
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../scope.dart';
import '../ui/edge.dart' show dismissKeyboard;
import '../ui/widgets.dart';
import '../update.dart' show UpdateCheck;

/* 서버와 같은 숫자(server/feedback.js) — 여기가 더 너그러우면 앱이 받아 준 것을
   서버가 돌려보내고, 보낸 사람은 무엇을 고쳐야 할지 모릅니다. */
const int kFeedbackMaxImages = 3;
const int kFeedbackImageMaxBytes = 1500000;
const int kFeedbackTextMax = 2000;

/// 앱 전체를 찍는 경계의 열쇠. [appCaptureBoundary] 가 앱 맨 위에 한 번만 답니다.
final GlobalKey kAppCaptureKey = GlobalKey(debugLabel: 'app-capture');

/// 앱 맨 위를 감쌉니다 — main.dart 의 MaterialApp.builder 가 edgeSafe **바깥**에.
/// 바깥이라 시스템 막대 뒤의 바탕 띠까지 창 전체가 한 장에 찍힙니다(안쪽이면 창보다
/// 작은 그림이 되어 주인이 보는 캡처와 폰 화면의 비율이 달라집니다).
/// Navigator 를 감싸므로 밀어 올린 화면 · 다이얼로그도 같이 찍힙니다.
Widget appCaptureBoundary(Widget child) =>
    RepaintBoundary(key: kAppCaptureKey, child: child);

/// 지금 앱 화면을 PNG 바이트로. 경계가 없거나 · 아직 안 그려졌거나 · 1배로 구워도
/// [kFeedbackImageMaxBytes] 를 넘으면 null — 그때는 캡처 없이 여는 것이 낫습니다.
Future<Uint8List?> captureAppScreen() async {
  final ctx = kAppCaptureKey.currentContext;
  if (ctx == null) return null;
  final dpr = MediaQuery.maybeDevicePixelRatioOf(ctx) ?? View.maybeOf(ctx)?.devicePixelRatio ?? 1.0;
  var ro = ctx.findRenderObject();
  if (ro is! RenderRepaintBoundary || !ro.attached) return null;
  /* 디버그에서는 toImage 가 "아직 칠할 것이 남았나" 를 assert 로 봅니다. 방금 누른
     단추의 물결이 경계를 더럽혔을 수 있어 한 장 그려지기를 기다립니다. 릴리스에는
     그 값이 없습니다(읽으면 던짐) — 거기서는 마지막으로 그린 그림을 그대로 굽습니다. */
  if (kDebugMode && ro.debugNeedsPaint) {
    await WidgetsBinding.instance.endOfFrame;
    ro = kAppCaptureKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.attached || ro.debugNeedsPaint) return null;
  }
  final boundary = ro;
  final first = math.min(dpr, 1.5);
  for (final ratio in [first, if (first > 1.0) 1.0]) {
    ui.Image? img;
    try {
      img = await boundary.toImage(pixelRatio: ratio);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      if (data.lengthInBytes <= kFeedbackImageMaxBytes) {
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
    } catch (_) {
      /* 굽다 막히면(앱이 내려가는 중 등) 캡처 없이 — 의견 시트는 그래도 떠야 합니다. */
      return null;
    } finally {
      img?.dispose();
    }
  }
  return null;
}

/// 앱 화면을 찍는 길. 시험에서 바꿔 끼웁니다 — 진짜 굽기는 runAsync 안에서만 끝납니다.
@visibleForTesting
Future<Uint8List?> Function() feedbackCapture = captureAppScreen;

/// 갤러리에서 [max] 장까지 고르는 길(고른 것의 바이트). 시험에서 바꿔 끼웁니다 —
/// 진짜 갤러리는 플랫폼 채널이라 시험 안에서는 열리지 않습니다.
@visibleForTesting
Future<List<Uint8List>> Function(int max) feedbackPick = _pickFromGallery;

Future<List<Uint8List>> _pickFromGallery(int max) async {
  /* 긴 변 1600 · 품질 80 — 화면 캡처와 사진 모두 알아보기에 넉넉하고, 한 장이 대개
     수백 KB 라 서버 상한(1.5MB)에 걸리지 않습니다.
     requestFullMetadata: false — 아이폰에서 사진 보관함 권한을 묻지 않습니다(고른
     사진만 받음). 의견 하나 보내려다 권한 창 앞에서 멈추면 안 됩니다. 원본 메타데이터
     (찍은 곳 등)도 덜 따라옵니다. */
  final files = await ImagePicker().pickMultiImage(
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 80,
    limit: max,
    requestFullMetadata: false,
  );
  /* 한도를 모르는 옛 안드로이드 고르기 화면은 더 많이 돌려줄 수 있습니다. */
  return [for (final f in files.take(max)) await f.readAsBytes()];
}

/// 앞머리 바이트로 본 형식 — 서버와 같은 기준(PNG 89 50 4E 47 · JPEG FF D8 FF).
/// 확장자나 고르기 화면의 말은 믿지 않습니다: 서버가 앞머리로 거절하면 보낸 사람은
/// 까닭을 알 길이 없습니다.
String? sniffImageType(Uint8List b) {
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  return null;
}

/// 고른 사진을 서버가 받는 모양으로. PNG · JPEG 이고 1.5MB 안이면 그대로(위치만
/// 지우고), 아니면 다시 그려 PNG 로. 열 수 없으면 null.
Future<FeedbackImage?> prepareFeedbackImage(Uint8List bytes) async {
  final type = sniffImageType(bytes);
  if (type != null && bytes.length <= kFeedbackImageMaxBytes) {
    return (
      type: type,
      bytes: type == 'image/jpeg' ? scrubJpegLocation(bytes) : scrubPngLocation(bytes),
    );
  }
  return _redrawAsPng(bytes);
}

/* 다시 그려 PNG 로. 긴 변을 줄여 가며 1.5MB 안에 들 때까지 — 사진은 PNG 로 구우면
   JPEG 보다 몇 배 커서 대개 두세 번째에 듭니다(앱에는 JPEG 을 굽는 길이 없습니다 —
   dart:ui 는 PNG 만 굽고, 꾸러미를 더 들이지 않습니다). 다시 그린 그림에는 위치 같은
   메타데이터가 따라오지 않습니다. 이 길은 드뭅니다(WebP · HEIC · 아주 큰 캡처). */
Future<FeedbackImage?> _redrawAsPng(Uint8List bytes) async {
  ui.ImmutableBuffer? buf;
  ui.ImageDescriptor? desc;
  try {
    buf = await ui.ImmutableBuffer.fromUint8List(bytes);
    desc = await ui.ImageDescriptor.encoded(buf);
    final w = desc.width, h = desc.height;
    final long = math.max(w, h);
    if (w <= 0 || h <= 0) return null;
    final top = math.min(long, 1600);
    final sides = [top, for (final s in const [1280, 1024, 800, 640, 480]) if (s < top) s];
    for (final side in sides) {
      final k = side / long;
      final codec = await desc.instantiateCodec(
        targetWidth: math.max(1, (w * k).round()),
        targetHeight: math.max(1, (h * k).round()),
      );
      ui.Image? img;
      try {
        img = (await codec.getNextFrame()).image;
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        if (data != null && data.lengthInBytes <= kFeedbackImageMaxBytes) {
          return (
            type: 'image/png',
            bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        }
      } finally {
        img?.dispose();
        codec.dispose();
      }
    }
    return null;
  } catch (_) {
    /* 그림이 아니거나 이 폰이 못 여는 형식 — 그 한 장만 뺍니다. */
    return null;
  } finally {
    desc?.dispose();
    buf?.dispose();
  }
}

/* --- JPEG 의 찍은 곳 지우기 ----------------------------------------------------
 *
 * 폰 카메라로 찍은 JPEG 에는 EXIF 안에 GPS(위도 · 경도 · 고도)가 들어 있곤 합니다.
 * 고르기 화면이 줄여 다시 구워도 EXIF 는 옮겨 붙입니다(안드로이드). 헬스장 기구
 * 사진 한 장에 집 주소가 실려 가면 안 됩니다.
 *
 * 통째로 다시 그리지 않고 **GPS 칸만 비웁니다**: EXIF 를 통째로 빼면 방향(세로로
 * 찍은 사진의 회전) 표시도 빠져 사진이 옆으로 눕습니다. GPS 칸은 자리를 그대로 두고
 * 값만 0 으로, 칸 수를 0 으로 — 파일 길이 · 다른 오프셋이 안 바뀌어 안전합니다.
 * XMP(위치가 글로 또 적힐 수 있는 덩어리)는 통째로 뺍니다 — 그림에 필요 없습니다.
 *
 * 모양이 예상과 다르면(깨진 파일 · 낯선 구조) 손대지 않고 돌려줍니다 — 그림을
 * 망가뜨려 서버가 거절하게 하는 것보다 낫습니다.
 * -------------------------------------------------------------------------- */
const _exifSig = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"
final _xmpSig = 'http://ns.adobe.com/xap/1.0/\u0000'.codeUnits;
final _xmpExtSig = 'http://ns.adobe.com/xmp/extension/\u0000'.codeUnits;

/// TIFF 칸 형식 → 한 값의 바이트 수.
const _tiffSize = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8};

/// JPEG 에서 찍은 곳(EXIF GPS · XMP)을 지운 바이트. JPEG 이 아니거나 모양이 낯설면 그대로.
Uint8List scrubJpegLocation(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return b;
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 2));
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return b;
    final m = b[i + 1];
    if (m == 0xFF) {
      out.addByte(0xFF); // 표시 앞의 채움 바이트
      i++;
      continue;
    }
    /* 그림 자료(SOS)부터 끝까지는 그대로 — 메타데이터는 그 앞에만 있습니다. */
    if (m == 0xDA || m == 0xD9) {
      out.add(Uint8List.sublistView(b, i));
      return out.takeBytes();
    }
    if (m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
      out.add(Uint8List.sublistView(b, i, i + 2)); // 길이 없는 표시
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    final end = i + 2 + len;
    if (len < 2 || end > b.length) return b;
    final seg = Uint8List.sublistView(b, i, end);
    if (m == 0xE1 && _startsWith(seg, 4, _exifSig)) {
      final copy = Uint8List.fromList(seg);
      _emptyGps(copy, 4 + _exifSig.length);
      out.add(copy);
    } else if (m == 0xE1 && (_startsWith(seg, 4, _xmpSig) || _startsWith(seg, 4, _xmpExtSig))) {
      // XMP — 뺍니다.
    } else {
      out.add(seg);
    }
    i = end;
  }
  return b;
}

bool _startsWith(Uint8List s, int at, List<int> sig) {
  if (s.length < at + sig.length) return false;
  for (var k = 0; k < sig.length; k++) {
    if (s[at + k] != sig[k]) return false;
  }
  return true;
}

/* EXIF(TIFF) 안의 GPS 칸을 비웁니다. [t] 는 TIFF 머리("II*\0" · "MM\0*")의 자리.
   오프셋은 전부 TIFF 머리 기준입니다. 밖을 가리키는 값은 건드리지 않습니다. */
void _emptyGps(Uint8List s, int t) {
  if (t + 8 > s.length) return;
  final bool le;
  if (s[t] == 0x49 && s[t + 1] == 0x49) {
    le = true;
  } else if (s[t] == 0x4D && s[t + 1] == 0x4D) {
    le = false;
  } else {
    return;
  }
  int u16(int o) => le ? s[o] | s[o + 1] << 8 : s[o] << 8 | s[o + 1];
  int u32(int o) => le
      ? s[o] | s[o + 1] << 8 | s[o + 2] << 16 | s[o + 3] << 24
      : s[o] << 24 | s[o + 1] << 16 | s[o + 2] << 8 | s[o + 3];
  bool fits(int o, int n) => o >= t && n >= 0 && o + n <= s.length;

  final ifd0 = t + u32(t + 4);
  if (!fits(ifd0, 2)) return;
  final n = u16(ifd0);
  if (!fits(ifd0 + 2, n * 12)) return;
  for (var k = 0; k < n; k++) {
    final e = ifd0 + 2 + k * 12;
    if (u16(e) != 0x8825) continue; // GPS 칸을 가리키는 표
    final gps = t + u32(e + 8);
    if (!fits(gps, 2)) return;
    final count = u16(gps);
    if (!fits(gps + 2, count * 12)) return;
    for (var j = 0; j < count; j++) {
      final g = gps + 2 + j * 12;
      /* 4바이트보다 긴 값(위도 · 경도는 유리수 3개 = 24바이트)은 다른 자리에 있습니다. */
      final size = (_tiffSize[u16(g + 2)] ?? 0) * u32(g + 4);
      if (size > 4) {
        final at = t + u32(g + 8);
        if (fits(at, size)) s.fillRange(at, at + size, 0);
      }
    }
    /* 칸 수 0 과 칸들 — 읽는 쪽은 빈 GPS 로 봅니다(다음 칸 자리도 0 이 됩니다). */
    s.fillRange(gps, gps + 2 + count * 12, 0);
    return;
  }
}

/* --- PNG 의 찍은 곳 지우기 -----------------------------------------------------
 *
 * PNG 에도 위치가 실릴 수 있습니다 — eXIf 덩어리(JPEG 의 EXIF 와 같은 TIFF 모양)와
 * 글 덩어리(tEXt · zTXt · iTXt: XMP, 그리고 "Raw profile type exif" 처럼 EXIF 를 글로
 * 적어 둔 것). 폰 카메라는 PNG 를 거의 안 만들지만, 안드로이드 고르기 화면이 줄여
 * 다시 구울 때 원본의 EXIF 를 옮겨 붙이는 것은 PNG 도 같습니다 — 처리방침의 "위치 정보는
 * 지우고 보냅니다" 가 JPEG 에서만 참이면 안 됩니다.
 *
 *   · eXIf 는 JPEG 과 같게 **GPS 칸만 비웁니다**(방향은 남김) — 값이 바뀌면 그 덩어리의
 *     CRC 를 다시 셉니다(틀린 CRC 는 읽는 쪽이 덩어리를 버리거나 그림을 거절합니다).
 *   · 글 덩어리는 통째로 뺍니다 — 그림을 그리는 데 필요 없습니다.
 *   · 나머지(그림 자료 IDAT · 색 · 크기)는 한 바이트도 안 바꿉니다. IEND 뒤의 꼬리는 버립니다.
 *   · 모양이 낯설면(길이가 파일 밖 · IEND 없음) 손대지 않고 돌려줍니다.
 * -------------------------------------------------------------------------- */
const _pngSig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// PNG 에서 찍은 곳(eXIf GPS · 글 덩어리)을 지운 바이트. PNG 가 아니거나 모양이 낯설거나
/// 바꿀 것이 없으면 그대로(같은 객체).
Uint8List scrubPngLocation(Uint8List b) {
  if (!_startsWith(b, 0, _pngSig)) return b;
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  var changed = false;
  var i = 8;
  while (i + 12 <= b.length) {
    final len = b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3];
    final end = i + 12 + len;
    if (end > b.length) return b;
    final type = String.fromCharCodes(b, i + 4, i + 8);
    if (type == 'tEXt' || type == 'zTXt' || type == 'iTXt') {
      changed = true; // 뺍니다
    } else if (type == 'eXIf') {
      /* 길이(4) 뒤의 [형식 4 + 자료] 가 CRC 를 세는 범위이고, 자료가 곧 TIFF 머리입니다. */
      final chunk = Uint8List.fromList(Uint8List.sublistView(b, i, end));
      _emptyGps(Uint8List.sublistView(chunk, 0, 8 + len), 8);
      final crc = _crc32(chunk, 4, 8 + len);
      for (var k = 0; k < 4; k++) {
        chunk[8 + len + k] = (crc >> (24 - 8 * k)) & 0xFF;
      }
      for (var k = 0; k < chunk.length && !changed; k++) {
        if (chunk[k] != b[i + k]) changed = true;
      }
      out.add(chunk);
    } else {
      out.add(Uint8List.sublistView(b, i, end));
    }
    i = end;
    if (type == 'IEND') return changed || i != b.length ? out.takeBytes() : b;
  }
  return b; // IEND 가 없음 — 낯선 모양
}

/* PNG 의 CRC-32(ISO 3309 — zlib · gzip 과 같은 것). 덩어리 하나 다시 셀 때만 씁니다. */
final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int _crc32(Uint8List s, int from, int to) {
  var c = 0xFFFFFFFF;
  for (var i = from; i < to; i++) {
    c = _crcTable[(c ^ s[i]) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/* --- 곁 정보: 화면 이름 · 판 · 기종 ------------------------------------------- */

/// 의견을 연 화면의 이름 — 가장 가까운 Scaffold 의 앱바 제목(글자일 때만), 64자까지.
///
/// 말풍선은 맨 위 화면의 **바깥**(경로의 안쪽 context — Scaffold 위)으로 부르므로, 위에
/// 없으면 아래로 한 번 찾습니다(맨 먼저 나오는 Scaffold 가 그 화면의 것 — 탭 안의
/// 화면에 Scaffold 가 또 있어도 셸의 것이 먼저 나옵니다).
/// 못 찾으면 null — 없어도 의견은 갑니다.
String? feedbackScreenName(BuildContext context) {
  try {
    Scaffold? found = context.findAncestorWidgetOfExactType<Scaffold>();
    if (found == null) {
      void visit(Element e) {
        if (found != null) return;
        final w = e.widget;
        if (w is Scaffold) {
          found = w;
          return;
        }
        e.visitChildren(visit);
      }
      context.visitChildElements(visit);
    }
    final bar = found?.appBar;
    final title = bar is AppBar ? bar.title : null;
    final name = title is Text ? title.data?.trim() : null;
    if (name == null || name.isEmpty) return null;
    final runes = name.runes;
    return runes.length <= 64 ? name : String.fromCharCodes(runes.take(64));
  } catch (_) {
    return null;
  }
}

/// 서버에 싣는 판 — '0.2.17+310'. 빌드 번호가 없거나 판과 같으면(웹) 판만.
/// 서버 약속(32자 · 보이는 ASCII)을 벗어나면 안 싣습니다 — 판 한 칸 때문에 의견이
/// 통째로 400 으로 돌아오면 안 됩니다.
String? feedbackAppVersion(String version, String build) {
  final v = version.trim(), b = build.trim();
  if (v.isEmpty) return null;
  final s = b.isEmpty || b == v ? v : '$v+$b';
  return RegExp(r'^[\x20-\x7e]{1,32}$').hasMatch(s) ? s : null;
}

/// 'android' · 'ios' — 그 밖(웹 · 데스크톱)은 서버가 모르는 값이라 안 싣습니다.
String? feedbackPlatform() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
}

/// 실패를 시트 안의 한 줄로. 서버가 까닭을 주면 그 말 그대로(서버 문구가 한국어).
String feedbackFailure(ApiResult r) {
  if (r.status == 429) return '오늘은 더 보낼 수 없어요 — 내일 다시';
  if (r.status == 0) return '서버에 닿지 못했어요 — 잠시 뒤 다시 눌러 주세요';
  /* 이 길이 없는 옛 서버는 "그런 경로가 없습니다"(404)를, 로그인 안 한 사람에게는 모르는
     길에 로그인부터 물어 401 을 줍니다(update.dart 와 같은 사정). 새 서버는 이 길에서
     401 을 주지 않으므로(토큰이 틀려도 익명) 401 은 곧 옛 서버입니다 — "로그인이
     필요합니다" 를 그대로 보이면 로그인 없이도 된다는 말과 어긋납니다. */
  if (r.status == 404 || r.status == 401) return '서버가 아직 의견을 못 받아요 — 다음 판에서 다시';
  final said = r.body['error'] ?? r.body['reason'];
  if (said is String && said.trim().isNotEmpty) return said.trim();
  if (r.status == 413) return '사진이 너무 커요 — 한 장을 빼고 다시';
  return '보내지 못했어요 (${r.status}) — 다시 눌러 주세요';
}

/* 서버는 글자를 코드 포인트로 셉니다. 입력칸의 2000자는 눈에 보이는 글자 단위라,
   이모지 조합이 많으면 코드 포인트로는 넘을 수 있습니다 — 넘는 꼬리만 자릅니다. */
String _clipText(String s) {
  final t = s.trim();
  final r = t.runes;
  return r.length <= kFeedbackTextMax ? t : String.fromCharCodes(r.take(kFeedbackTextMax)).trim();
}

Future<String?> _appVersion(PackageInfo? known) async {
  var p = known;
  if (p == null) {
    try {
      p = await PackageInfo.fromPlatform().timeout(const Duration(seconds: 2));
    } catch (_) {
      return null; // 판을 못 읽어도 의견은 갑니다
    }
  }
  return feedbackAppVersion(p.version, p.buildNumber);
}

/* --- 말풍선 켜기 · 끄기 ---------------------------------------------------------- */

/// 화면 옆 말풍선(feedback_bubble.dart)을 보일까. 말풍선과 설정 「도움말」 의 스위치가
/// 같이 봅니다 — 한쪽에서 바꾸면 다른 쪽이 곧바로 따라옵니다.
///
/// 이 기기의 화면 취향이라 동기화하는 settings 가 아니라 SharedPreferences 에 둡니다 —
/// 태블릿에서 숨겼다고 폰에서까지 사라지면, 폰에서는 왜 없어졌는지 모릅니다.
///
/// **시험 기간에는 이 값과 상관없이 보입니다**([feedbackBubbleLocked]). 옛 판에서 꺼 둔
/// 기기도 시험 중에는 말풍선이 뜹니다 — 값은 그대로 두어, 시험이 끝나면 그 사람이 고른
/// 대로(꺼진 채) 돌아갑니다.
final ValueNotifier<bool> feedbackBubbleOn = ValueNotifier<bool>(true);

/// 말풍선을 끌 수 없는 때 — 비공개 시험 기간(GET /api/version 의 testing, update.dart).
///
/// 주인의 말: "테스트기간에는 X표시에 갖다대면 '테스트 기간에는 없앨수없어요'". 시험판을
/// 쓰는 사람의 의견이 시험의 전부라 그동안은 치우는 길(X · 설정 스위치)을 잠급니다.
/// 확인기가 없거나(켜는 중 · 시험) 답을 아직 모르면 **시험 중으로** 봅니다 — 서버와 같은
/// 규칙(모르는 값은 켜짐)입니다.
bool feedbackBubbleLocked(UpdateCheck? update) => update?.testing ?? true;

/// 잠겼을 때 설정 스위치의 부제. 아이폰 판은 같은 빌드가 **앱스토어 심사**에도 들어가서
/// 「테스트」 라는 말을 쓰지 않습니다 — 심사하는 사람 화면에 "테스트 기간" 이 뜨면 시험판을
/// 냈다고 보고 거절할 수 있습니다(지침 2.2, tester_welcome.dart 의 welcomeTitle 과 같은 까닭).
String feedbackLockedSubtitle([TargetPlatform? platform]) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.iOS ? '의견을 모으는 동안 켜 둡니다' : '테스트 기간에는 켜 둡니다';

/// 잠겼을 때 말풍선을 X 에 갖다대면 뜨는 말 — 아이폰은 「테스트」 없이(위와 같은 까닭).
String feedbackLockedRemoveSay([TargetPlatform? platform]) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.iOS ? '지금은 없앨 수 없어요' : '테스트 기간에는 없앨 수 없어요';

const String kFeedbackBubbleOnKey = 'mybody.feedbackBubble.on.v1';

/// 저장된 값을 [feedbackBubbleOn] 에 싣습니다. 못 읽으면 켜진 채로 — 의견 길이 사라지는
/// 쪽보다 떠 있는 쪽이 낫습니다.
Future<bool> loadFeedbackBubbleOn() async {
  try {
    final sp = await SharedPreferences.getInstance();
    feedbackBubbleOn.value = sp.getBool(kFeedbackBubbleOnKey) ?? true;
  } catch (_) {}
  return feedbackBubbleOn.value;
}

/// 켜고 끄기 — 말풍선에는 곧바로, 저장은 뒤따라.
Future<void> setFeedbackBubbleOn(bool on) async {
  feedbackBubbleOn.value = on;
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kFeedbackBubbleOnKey, on);
  } catch (_) {
    // 못 적어도 이번 실행 동안은 고른 대로입니다.
  }
}

/* --- 여는 곳 ------------------------------------------------------------------ */

/* 지금 떠 있는 시트, 그리고 찍는 중인가 — 둘 중 하나면 새로 열지 않습니다(말풍선을
   두 번 누르면 두 장이 쌓였습니다). 시트가 서면 [_starting] 을 내리고 닫히면(dispose)
   [_live] 를 비웁니다. 시트의 Future 로 지키지 않는 까닭: 앱이 통째로 내려가면
   그 Future 는 끝나지 않아 영영 "열려 있음" 으로 남습니다. 둘을 바꾼 뒤에는
   [_syncBusy] 로 바깥([feedbackBusy])에 알립니다. */
_FeedbackSheetState? _live;
bool _starting = false;

final ValueNotifier<bool> _busy = ValueNotifier<bool>(false);

/// 의견 시트가 뜨는 중(화면을 찍는 중 포함)이거나 떠 있나 — 우리 모달끼리 겹치지 않게 하는
/// 한 자리입니다. 말풍선은 이 동안 숨고, 테스터 인사는 이 동안 기다립니다([feedbackClosed]).
ValueListenable<bool> get feedbackBusy => _busy;

/* 시트의 initState · dispose 는 프레임을 그리는 **도중에** 불립니다. 거기서 바로 알리면
   듣는 쪽(말풍선)이 그리는 도중에 "다시 그려라" 를 받아 던집니다 — 그때는 이 프레임이
   끝난 뒤로 미룹니다. 한 프레임(16ms) 늦는 것은 눈에 안 보입니다. */
void _syncBusy() {
  final now = _starting || _live != null;
  if (_busy.value == now) return;
  final binding = SchedulerBinding.instance;
  if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    binding.addPostFrameCallback((_) => _syncBusy());
    return;
  }
  _busy.value = now;
}

/// 의견 시트가 닫히면(찍는 중이었으면 그 뒤에 뜬 시트까지 닫히면) 끝납니다. 안 떠 있으면 곧바로.
Future<void> feedbackClosed() {
  if (!_busy.value) return Future<void>.value();
  final done = Completer<void>();
  void check() {
    if (_busy.value) return;
    _busy.removeListener(check);
    done.complete();
  }
  _busy.addListener(check);
  return done.future;
}

/// 의견 보내기 시트를 엽니다. [captureScreen] 이면 여는 순간의 앱 화면을 찍어 붙여 둡니다.
///
/// 화면 이름은 [context] 에서 가장 가까운 앱바 제목으로 읽습니다 — 말풍선은 맨 위 화면의
/// context 를 건넵니다(feedback_bubble.dart 의 FeedbackRoutes.pageContext).
Future<void> openFeedback(BuildContext context, {bool captureScreen = false}) async {
  if (_live != null || _starting) return;
  _starting = true;
  _syncBusy();
  final String? screen;
  final PackageInfo? known;
  Uint8List? shot;
  try {
    screen = feedbackScreenName(context);
    known = Scope.updateOf(context)?.package;
    if (captureScreen) {
      try {
        /* 3초까지만 기다립니다. 굽기가 끝나지 않으면(앱이 막 내려가는 중 · GPU 를 못 쓰는
           때) [_starting] 이 영영 켜진 채로 남아 말풍선이 앱을 다시 켤 때까지 죽습니다.
           보통은 0.1초 안에 끝납니다. then 으로 한 번 감싸는 것은 넘겨받은 Future 가 실제로는
           Future<Uint8List>(null 불가)일 수 있어서입니다 — 그러면 onTimeout 의 null 이 형식
           오류로 던져져 멀쩡히 찍힌 화면까지 버립니다. */
        shot = await feedbackCapture()
            .then<Uint8List?>((b) => b)
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
      } catch (_) {
        shot = null; // 못 찍어도 시트는 뜹니다
      }
    }
  } catch (_) {
    _starting = false;
    _syncBusy();
    rethrow;
  }
  if (!context.mounted) {
    _starting = false;
    _syncBusy();
    return;
  }
  /* 찍은 **뒤에** 내립니다 — 먼저 내리면 화면이 키보드 없는 모양으로 다시 짜이는
     도중을 찍습니다. */
  dismissKeyboard();
  bool? sent;
  try {
    sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FeedbackSheet(
        shot: shot,
        screen: screen,
        known: known,
        /* 보내는 사이에 시트가 닫혔을 때의 결과는 연 화면에서 알립니다([_FeedbackSheetState._send]). */
        onLate: (msg) {
          if (context.mounted) toast(context, msg);
        },
      ),
    );
  } finally {
    _starting = false;
    _syncBusy();
  }
  if (sent == true && context.mounted) toast(context, '보냈어요 — 고마워요!');
}

/* --- 시트 ---------------------------------------------------------------------- */

/// 붙인 사진 한 장. [screen] 이면 여는 순간 찍은 앱 화면.
class _Shot {
  const _Shot(this.image, {this.screen = false});
  final FeedbackImage image;
  final bool screen;
}

/* 작은 그림 칸 — 세로로 긴 폰 화면이 알아볼 만하게 3:4 쯤. 칸은 많아야 셋입니다
   (3장이 차면 「사진 추가」 칸이 사라짐) — 360 폭에서도 한 줄에 듭니다. */
const double _tileW = 76;
const double _tileH = 100;

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({
    required this.shot,
    required this.screen,
    required this.known,
    required this.onLate,
  });
  final Uint8List? shot;
  final String? screen;
  final PackageInfo? known;

  /// 보내는 **도중에** 시트가 닫혔으면(끌어 내림 · 뒤로 · 바깥 탭) 결과 한 줄을 여기로.
  final void Function(String message) onLate;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _text = TextEditingController();
  late final List<_Shot> _shots = [
    if (widget.shot case final s?) _Shot((type: 'image/png', bytes: s), screen: true),
  ];
  bool _picking = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _live = this;
    _starting = false;
    _syncBusy();
    /* 글이 생기고 없어질 때 「보내기」 가 켜지고 꺼집니다. */
    _text.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (identical(_live, this)) {
      _live = null;
      _syncBusy();
    }
    _text.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && !_picking && (_shots.isNotEmpty || _text.text.trim().isNotEmpty);

  Future<void> _add() async {
    final room = kFeedbackMaxImages - _shots.length;
    if (room <= 0 || _picking || _sending) return;
    dismissKeyboard();
    setState(() {
      _picking = true;
      _error = null;
    });
    final added = <_Shot>[];
    var failed = false;
    try {
      final picked = await feedbackPick(room);
      for (final raw in picked.take(room)) {
        final img = await prepareFeedbackImage(raw);
        if (img == null) {
          failed = true;
        } else {
          added.add(_Shot(img));
        }
      }
    } catch (_) {
      /* 사진 접근을 막아 둔 폰 등 — 플랫폼이 던집니다. 붙여 둔 것은 그대로. */
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _picking = false;
      _shots.addAll(added.take(kFeedbackMaxImages - _shots.length));
      if (failed) _error = added.isEmpty ? '사진을 못 가져왔어요' : '열 수 없는 사진은 뺐어요';
    });
  }

  void _remove(int i) {
    if (_sending || i >= _shots.length) return;
    setState(() {
      _shots.removeAt(i);
      _error = null;
    });
  }

  Future<void> _send() async {
    if (!_canSend) return;
    dismissKeyboard();
    final api = Scope.apiOf(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    final r = await api.sendFeedback(
      text: _clipText(_text.text),
      images: [for (final s in _shots) s.image],
      appVersion: await _appVersion(widget.known),
      platform: feedbackPlatform(),
      screen: widget.screen,
    );
    if (!mounted) {
      /* 보내는 사이에 시트를 닫았습니다 — 느린 데이터에서는 몇십 초라 흔합니다(닫기를
         막으면 그동안 앱에 갇히고, 끌어 내리기는 어차피 못 막습니다). 결과를 말없이
         버리면 간 의견을 또 보내거나, 못 간 것을 간 줄 압니다. */
      widget.onLate(r.ok ? '보냈어요 — 고마워요!' : '의견을 못 보냈어요 — ${feedbackFailure(r)}');
      return;
    }
    if (r.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    /* 글 · 사진은 그대로 — 고칠 것 없이 다시 누르면 되게. */
    setState(() {
      _sending = false;
      _error = feedbackFailure(r);
    });
  }

  void _preview(_Shot s) {
    dismissKeyboard();
    showDialog<void>(
      context: context,
      /* 아무 데나 누르면 닫힙니다(opaque — 그림 밖 여백도). 두 손가락 확대는 안쪽의
         InteractiveViewer 가 먼저 받습니다. */
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).pop(),
        child: Dialog(
          key: const Key('feedback-preview'),
          insetPadding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(
            child: Image.memory(s.image.bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox(height: 200)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final grey = t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.4);
    final lead = _shots.any((s) => s.screen)
        ? '화면이 같이 가요 · 글은 안 써도 돼요'
        : _shots.isNotEmpty
            ? '사진이 같이 가요 · 글은 안 써도 돼요'
            : '사진이나 글, 하나만 있어도 돼요';
    /* **키보드가 올라오면 시트를 그만큼 밀어 올립니다**(설정의 「내 몸 정보」 시트와
       같은 까닭 — 모달 시트는 스스로 키보드를 피하지 않습니다). 「보내기」 는 스크롤
       밖 맨 아래라, 글 칸이 커지거나 작은 폰이어도 스크롤 쪽이 줄어들 뿐 늘 보입니다. */
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              /* 끌면 키보드를 내립니다 — 전역 「바깥 탭」(ui/edge.dart)과 함께. */
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('의견 보내기',
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(lead, key: const Key('feedback-lead'), style: grey),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (var i = 0; i < _shots.length; i++) _thumb(context, i),
                  if (_shots.length < kFeedbackMaxImages) _addTile(context),
                ]),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('feedback-text'),
                  controller: _text,
                  readOnly: _sending,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: kFeedbackTextMax,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '무엇이 불편했나요? (안 써도 돼요)',
                    border: OutlineInputBorder(),
                  ),
                  /* 세는 글자는 끝이 가까울 때만 — 늘 떠 있으면 "2000자를 채워야 하나" 로 읽힙니다. */
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      maxLength != null && currentLength >= maxLength - 200
                          ? Text('$currentLength / $maxLength')
                          : null,
                ),
                if (_shots.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('붙인 화면에는 몸 수치가 보일 수 있어요 — 운영자만 봅니다',
                      key: const Key('feedback-privacy'),
                      style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.4)),
                ],
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error case final e?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(e,
                          key: const Key('feedback-error'),
                          style: t.textTheme.bodySmall?.copyWith(color: mb(context).bad, height: 1.4)),
                    ),
                  ),
                FilledButton(
                  key: const Key('feedback-send'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _canSend ? _send : null,
                  child: _sending
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Flexible(child: Text('보내는 중…')),
                        ])
                      : const Text('보내기'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(BuildContext context, int i) {
    final t = Theme.of(context);
    final s = _shots[i];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final radius = BorderRadius.circular(10);
    return SizedBox(
      key: Key('feedback-thumb-$i'),
      width: _tileW,
      height: _tileH,
      child: Stack(children: [
        Positioned.fill(
          child: Semantics(
            image: true,
            label: s.screen ? '붙인 화면' : '붙인 사진',
            child: GestureDetector(
              /* 보내는 동안은 안 엽니다 — 다 보내고 시트를 닫을 때 맨 위의 이 창이
                 대신 닫힙니다. */
              onTap: _sending ? null : () => _preview(s),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: t.dividerColor),
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: ColoredBox(
                    color: t.colorScheme.surfaceContainerHighest,
                    child: Image.memory(
                      s.image.bytes,
                      fit: BoxFit.cover,
                      /* 작은 칸에 원본 크기로 풀면 한 장에 몇 MB 씩 메모리를 씁니다. */
                      cacheWidth: (_tileW * dpr).round(),
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) =>
                          Center(child: Icon(LucideIcons.image, color: t.hintColor)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        /* 빼기 — 칸 안 오른쪽 위. 밖으로 삐져나오게 두면 그 부분은 눌리지 않습니다. */
        Positioned(
          top: 3,
          right: 3,
          child: Material(
            color: t.colorScheme.inverseSurface.withValues(alpha: 0.72),
            shape: const CircleBorder(),
            child: InkWell(
              key: Key('feedback-remove-$i'),
              customBorder: const CircleBorder(),
              onTap: _sending ? null : () => _remove(i),
              child: Semantics(
                button: true,
                label: '빼기',
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(LucideIcons.x, size: 16, color: t.colorScheme.onInverseSurface),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _addTile(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      width: _tileW,
      height: _tileH,
      child: OutlinedButton(
        key: const Key('feedback-add'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _picking || _sending ? null : _add,
        child: _picking
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(LucideIcons.imagePlus, size: 22),
                const SizedBox(height: 6),
                /* 색은 단추의 글자색을 따르게 크기만 — 테마의 labelSmall 을 통째로 쓰면
                   단추 색 대신 본문 색이 됩니다. */
                Text('사진 추가',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: t.textTheme.labelSmall?.fontSize, height: 1.2)),
              ]),
      ),
    );
  }
}
