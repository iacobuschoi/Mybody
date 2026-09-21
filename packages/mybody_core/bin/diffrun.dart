/* diffrun.dart — tools/difftest.js 가 부르는 Dart 쪽 실행기.
   사례 파일을 읽어 모듈을 돌리고 결과를 JSON 으로 찍습니다.
   형식은 JS 쪽과 같아야 합니다: {ok, v} 또는 {ok:false, v:"오류문구"}. */
import 'dart:convert';
import 'dart:io';

import 'package:mybody_core/crosscheck.dart' as crosscheck;
import 'package:mybody_core/engine.dart' as engine;

/// JSON.stringify 는 NaN·Infinity 를 **null** 로 씁니다. Dart 의 jsonEncode 는
/// 던집니다. 옮긴 코드에서 NaN 은 정상적으로 나옵니다(자바스크립트가 없는
/// 값으로 산수하면 NaN 이 되고, 우리는 그 길을 그대로 흉내 냅니다).
/// 그러니 여기서 같은 모양으로 맞춰 줘야 비교가 성립합니다.
Object? _clean(Object? v) {
  if (v is double && (v.isNaN || v.isInfinite)) return null;
  if (v is Map) {
    final out = <String, Object?>{};
    v.forEach((k, x) => out['$k'] = _clean(x));
    return out;
  }
  if (v is List) return v.map(_clean).toList();
  return v;
}

Map<String, Object?>? _m(Object? x) =>
    x == null ? null : (x as Map).cast<String, Object?>();

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: diffrun <module> <cases.json>');
    exit(2);
  }
  final module = args[0];
  final cases = jsonDecode(File(args[1]).readAsStringSync()) as List;

  final out = <Map<String, Object?>>[];
  for (final c0 in cases) {
    final c = c0 as Map<String, Object?>;
    try {
      Object? v;
      switch (module) {
        case 'crosscheck':
          v = crosscheck.run(_m(c['scan']), _m(c['profile']), _m(c['prev']));
          break;
        case 'engine.validateScan':
          v = engine.validateScan(_m(c['scan']), _m(c['prev']));
          break;
        case 'engine.derive':
          v = engine.derive(_m(c['scan'])!, _m(c['profile'])!);
          break;
        default:
          stderr.writeln('모르는 모듈: $module');
          exit(2);
      }
      out.add({'ok': true, 'v': _clean(v)});
    } catch (e) {
      out.add({'ok': false, 'v': e.toString()});
    }
  }
  stdout.write(jsonEncode(out));
}
