/* diffrun.dart — tools/difftest.js 가 부르는 Dart 쪽 실행기.
   사례 파일을 읽어 모듈을 돌리고 결과를 JSON 으로 찍습니다.
   형식은 JS 쪽과 같아야 합니다: {ok, v} 또는 {ok:false, v:"오류문구"}. */
import 'dart:convert';
import 'dart:io';

import 'package:mybody_core/crosscheck.dart' as crosscheck;

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
          v = crosscheck.run(
            (c['scan'] as Map?)?.cast<String, Object?>(),
            (c['profile'] as Map?)?.cast<String, Object?>(),
            (c['prev'] as Map?)?.cast<String, Object?>(),
          );
          break;
        default:
          stderr.writeln('모르는 모듈: $module');
          exit(2);
      }
      out.add({'ok': true, 'v': v});
    } catch (e) {
      out.add({'ok': false, 'v': e.toString()});
    }
  }
  stdout.write(jsonEncode(out));
}
