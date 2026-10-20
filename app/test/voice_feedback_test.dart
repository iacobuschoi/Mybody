/* =============================================================================
 * voice_feedback_test.dart — 누르고 말하기를 고친 것이 피드백으로 · 서버 별칭 사전
 *
 *   · voiceCorrection — 고친 것만 본문이 되고, 그대로 기록하면 null.
 *   · sendVoiceCorrection — 서버에 닿지 못하면 쌓아 두었다가 다음에 같이 보냅니다.
 *   · refreshVoiceAliases — 서버 사전이 짧은 말 표보다 먼저, 모르는 종목 id 는 버림.
 * ========================================================================== */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybody/src/api.dart';
import 'package:mybody/src/workout/exercises.dart';
import 'package:mybody/src/workout/voice_feedback.dart';
import 'package:mybody/src/workout/voice_set.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setSpokenAliasOverrides(const {});
  });

  List<SpokenSet> copy(SpokenEntry e) => [
        for (final s in e.sets)
          SpokenSet(exercise: s.exercise, spokenName: s.spokenName, kg: s.kg, reps: s.reps, count: s.count),
      ];

  group('voiceCorrection', () {
    test('그대로 기록하면 보낼 것이 없다', () {
      final e = parseSpokenSets('벤치 80키로 4개');
      expect(voiceCorrection(e, copy(e)), isNull);
    });

    test('종목을 다시 고르면 받아쓴 글 · 알아들은 것 · 고른 것이 간다(녹음은 없음)', () {
      final e = parseSpokenSets('벤치 80키로 4개');
      final chosen = copy(e)..first.exercise = exerciseById('deadlift');
      final b = voiceCorrection(e, chosen)!;
      expect(b['transcript'], '벤치 80키로 4개');
      expect((b['heard'] as List).single, containsPair('exercise', 'bench-press'));
      expect((b['chosen'] as List).single, containsPair('exercise', 'deadlift'));
      expect((b['chosen'] as List).single, containsPair('kg', 80.0));
      expect(b.keys, isNot(contains('audio')));
    });

    test('무게만 고쳐도 · 못 알아들은 말에 종목을 골라도 고친 것', () {
      final e = parseSpokenSets('벤치 80키로 4개');
      expect(voiceCorrection(e, copy(e)..first.kg = 85), isNotNull);
      final none = parseSpokenSets('뿡뿡이 80키로 4개');
      expect(none.sets.first.exercise, isNull);
      final fixed = copy(none)..first.exercise = exerciseById('bench-press');
      final b = voiceCorrection(none, fixed)!;
      expect((b['heard'] as List).single, containsPair('exercise', null));
      expect((b['heard'] as List).single['spoken'], contains('뿡뿡이'));
    });
  });

  group('보내기', () {
    test('닿지 못하면 쌓아 두고, 다음에 서버가 받으면 쌓인 것까지 비운다', () async {
      final got = <Map<String, dynamic>>[];
      var up = false;
      final api = Api(
          baseUrl: 'https://x.test',
          client: MockClient((req) async {
            if (req.url.path != '/api/voice/feedback') return http.Response('{"ok":false}', 404);
            if (!up) return http.Response('{"ok":false}', 503);
            got.add((jsonDecode(req.body) as Map).cast<String, dynamic>());
            return http.Response('{"ok":true,"id":1}', 200);
          }));
      final e = parseSpokenSets('벤치 80키로 4개');
      await sendVoiceCorrection(api, voiceCorrection(e, copy(e)..first.kg = 85)!);
      expect(got, isEmpty);
      final p = await SharedPreferences.getInstance();
      expect(p.getStringList('voiceFeedbackQueue'), hasLength(1));
      up = true;
      await sendVoiceCorrection(api, voiceCorrection(e, copy(e)..first.reps = 5)!);
      expect(got, hasLength(2), reason: '쌓인 것 + 새것');
      expect(got.first['transcript'], '벤치 80키로 4개');
      expect(p.getStringList('voiceFeedbackQueue'), isEmpty);
    });

    test('서버가 틀린 본문이라고 하면(400) 다시 보내지 않는다', () async {
      var calls = 0;
      final api = Api(
          baseUrl: 'https://x.test',
          client: MockClient((req) async {
            calls++;
            return http.Response.bytes(utf8.encode('{"ok":false,"error":"틀림"}'), 400);
          }));
      final e = parseSpokenSets('벤치 80키로 4개');
      await sendVoiceCorrection(api, voiceCorrection(e, copy(e)..first.kg = 85)!);
      final p = await SharedPreferences.getInstance();
      expect(calls, 1);
      expect(p.getStringList('voiceFeedbackQueue'), isEmpty);
    });
  });

  group('서버 별칭 사전', () {
    test('사전의 말이 짧은 말 표보다 먼저 · 모르는 종목 id 는 버린다', () async {
      expect(matchSpokenExercise('벤츠')?.id, 'bench-press');
      final api = Api(
          baseUrl: 'https://x.test',
          client: MockClient((req) async => http.Response.bytes(
              utf8.encode(jsonEncode({
                'ok': true,
                'version': 'v1',
                'aliases': {'벤츠': 'deadlift', '뱅뱅': 'no-such-exercise'},
              })),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'})));
      await refreshVoiceAliases(api);
      expect(matchSpokenExercise('벤츠')?.id, 'deadlift');
      expect(matchSpokenExercise('뱅뱅')?.id, isNot('no-such-exercise'));
      /* 기기에 남아 다음 실행에 서버 없이 바로 씁니다. */
      setSpokenAliasOverrides(const {});
      final offline = Api(baseUrl: 'https://x.test', client: MockClient((_) async => http.Response('', 503)));
      await refreshVoiceAliases(offline);
      expect(matchSpokenExercise('벤츠')?.id, 'deadlift');
    });
  });
}
