/* 친구가 카톡에서 복사해 붙여넣는 주소를 받아 주는가.
 *
 * 여기서 거부당하면 그 친구는 폰 키보드로 주소 앞에 글자를 끼워 넣어야
 * 합니다. 거기서 그만두게 되는 종류의 일입니다. */
import 'package:flutter_test/flutter_test.dart';
import 'package:mybody/src/screens/account.dart';

void main() {
  group('붙여넣은 주소 다듬기', () {
    const want = 'https://mypc.tail1234.ts.net';

    final cases = <String, String>{
      '맨 주소':            'mypc.tail1234.ts.net',
      '이미 https':         'https://mypc.tail1234.ts.net',
      '끝에 빗금':           'https://mypc.tail1234.ts.net/',
      '빗금 여러 개':         'https://mypc.tail1234.ts.net///',
      '앞뒤 공백':           '  mypc.tail1234.ts.net  ',
      '문장 끝 마침표':        'mypc.tail1234.ts.net.',
      'tailscale 이 내준 끝점': 'mypc.tail1234.ts.net.',
      '따옴표로 감쌈':         '"mypc.tail1234.ts.net"',
      '꺾쇠로 감쌈':          '<https://mypc.tail1234.ts.net>',
      '대문자 스킴':          'HTTPS://mypc.tail1234.ts.net',
    };

    cases.forEach((name, input) {
      test(name, () {
        final got = normalizeServerUrl(input);
        // 대문자 스킴은 그대로 두되(서버가 알아봅니다) 나머지는 같아야 합니다.
        expect(got.toLowerCase(), want.toLowerCase(), reason: '넣은 것: "$input"');
      });
    });

    test('http 는 https 로 바꾸지 않는다 — 본인이 정한 것이므로', () {
      // 맨 주소만 https 를 붙입니다. 일부러 http 를 적은 건 그대로 두고,
      // 화면에서 "안드로이드가 막습니다" 라고 말해 줍니다.
      expect(normalizeServerUrl('http://192.168.0.10:8080'),
             'http://192.168.0.10:8080');
    });

    test('빈 칸은 빈 채로 둔다', () {
      expect(normalizeServerUrl('   '), '');
    });

    test('포트가 붙어도 살아 있다', () {
      expect(normalizeServerUrl('mypc.tail1234.ts.net:8443'),
             'https://mypc.tail1234.ts.net:8443');
    });

    test('경로가 붙어도 살아 있다', () {
      expect(normalizeServerUrl('https://example.com/mybody/'),
             'https://example.com/mybody');
    });
  });
}
