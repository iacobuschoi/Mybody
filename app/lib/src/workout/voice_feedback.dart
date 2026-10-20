/* =============================================================================
 * voice_feedback.dart — 누르고 말하기가 틀린 것을 서버로 · 서버 사전을 앱으로
 *
 * 따로 「잘못 알아들었어요」 단추는 없습니다(주인 결정 10/20). 확인 시트에서 사용자가 종목을
 * 다시 고르거나 무게 · 횟수 · 세트 수를 고친 채 「기록」 을 누르면, 그 고친 것이 곧 피드백입니다:
 *
 *   · 싣는 것 — 받아쓴 글, 알아들은 세트, 고른 세트, 앱 판 · 기종. **목소리(녹음)는 없습니다.**
 *     로그인했으면 토큰이 붙어 계정에 묶이고, 아니면 익명(「의견 보내기」 와 같은 길).
 *   · 취소 · 그대로 기록은 안 보냅니다 — 고친 것만이 「틀렸다」 는 뜻이 분명합니다.
 *   · 보내기는 화면을 막지 않습니다. 실패하면(헬스장 지하 · 옛 서버 404) 기기에 쌓아 두었다가
 *     다음에 보낼 때 같이 — 최대 [_queueMax] 건, 넘치면 오래된 것부터 버립니다.
 *
 * 반대 방향: 서버가 모아 본 뒤 고친 별칭 사전(GET /api/voice/aliases)을 받아
 * setSpokenAliasOverrides 에 꽂습니다. 받은 것은 기기에 두고 다음 실행에 바로 쓰며, 6시간에
 * 한 번만 다시 묻습니다.
 * ========================================================================== */
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import 'voice_set.dart';

/// 세트 하나를 서버 모양으로.
Map<String, Object?> spokenSetJson(SpokenSet s) => {
      'exercise': s.exercise?.id,
      if (s.exercise != null) 'name': s.exercise!.name,
      'spoken': _clip(s.spokenName, 64),
      'kg': s.kg,
      'reps': s.reps,
      'count': s.count,
    };

/// 알아들은 것([heard])과 기록한 것([chosen])이 다르면 보낼 본문, 같으면 null.
/// 종목 · 무게 · 횟수 · 세트 수 중 하나라도, 또는 줄 수가 달라도 「고친 것」 입니다.
Map<String, Object?>? voiceCorrection(SpokenEntry heard, List<SpokenSet> chosen) {
  String key(SpokenSet s) => '${s.exercise?.id}|${s.kg}|${s.reps}|${s.count}';
  final a = [for (final s in heard.sets) key(s)];
  final b = [for (final s in chosen) key(s)];
  if (listEquals(a, b) || chosen.isEmpty) return null;
  return {
    'transcript': _clip(heard.transcript, 300),
    'heard': [for (final s in heard.sets.take(10)) spokenSetJson(s)],
    'chosen': [for (final s in chosen.take(10)) spokenSetJson(s)],
  };
}

String _clip(String s, int n) {
  final r = s.trim().runes;
  return r.length <= n ? s.trim() : String.fromCharCodes(r.take(n));
}

const _queueKey = 'voiceFeedbackQueue';
const _queueMax = 30;
const _aliasKey = 'voiceAliases';
const _aliasAtKey = 'voiceAliasesAt';
const _aliasEvery = Duration(hours: 6);

/// 고친 것을 보냅니다(쌓인 것도 같이). 기다리지 않아도 됩니다 — 실패는 조용히 쌓아 둡니다.
Future<void> sendVoiceCorrection(Api api, Map<String, Object?> body) async {
  try {
    final p = await SharedPreferences.getInstance();
    final queue = [...(p.getStringList(_queueKey) ?? const <String>[])];
    queue.add(jsonEncode({...body, ...await _device()}));
    while (queue.length > _queueMax) {
      queue.removeAt(0);
    }
    await p.setStringList(_queueKey, queue);
    await flushVoiceFeedback(api);
  } catch (_) {
    /* 피드백 때문에 기록이 막히거나 화면에 오류가 뜨면 안 됩니다. */
  }
}

/// 쌓인 것을 차례로. 받았거나(2xx) 서버가 틀린 본문이라고 한 것(400 · 413)은 빼고 —
/// 다시 보내도 같은 답입니다. 닿지 못함 · 옛 서버(404 · 401) · 429 · 5xx 는 남겨 둡니다.
Future<void> flushVoiceFeedback(Api api) async {
  final p = await SharedPreferences.getInstance();
  final queue = [...(p.getStringList(_queueKey) ?? const <String>[])];
  if (queue.isEmpty) return;
  final left = <String>[];
  var stop = false;
  for (final raw in queue) {
    if (stop) {
      left.add(raw);
      continue;
    }
    final Map<String, dynamic> body;
    try {
      body = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      continue;
    }
    final r = await api.sendVoiceFeedback(body);
    if (r.ok || r.status == 400 || r.status == 413) continue;
    left.add(raw);
    stop = true;   // 하나가 막혔으면 나머지도 막힙니다 — 다음에
  }
  await p.setStringList(_queueKey, left);
}

Future<Map<String, Object?>> _device() async {
  String? version;
  try {
    final i = await PackageInfo.fromPlatform().timeout(const Duration(seconds: 2));
    final s = i.buildNumber.isEmpty || i.buildNumber == i.version ? i.version : '${i.version}+${i.buildNumber}';
    version = RegExp(r'^[\x20-\x7e]{1,32}$').hasMatch(s) ? s : null;
  } catch (_) {}
  final platform = kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          _ => null,
        };
  return {if (version != null) 'appVersion': version, if (platform != null) 'platform': platform};
}

/// 기기에 둔 서버 사전을 바로 꽂고, 오래됐으면 서버에 다시 묻습니다(헬스 화면을 열 때).
/// 쌓인 피드백도 이때 한 번 보내 봅니다.
Future<void> refreshVoiceAliases(Api api, {DateTime Function() now = DateTime.now}) async {
  try {
    final p = await SharedPreferences.getInstance();
    final cached = p.getString(_aliasKey);
    if (cached != null) setSpokenAliasOverrides(_aliasesOf(jsonDecode(cached)));
    final at = DateTime.tryParse(p.getString(_aliasAtKey) ?? '');
    unawaited(flushVoiceFeedback(api).catchError((_) {}));
    if (at != null && now().difference(at) < _aliasEvery) return;
    final r = await api.voiceAliases();
    if (!r.ok) return;
    final m = _aliasesOf(r.body['aliases']);
    setSpokenAliasOverrides(m);
    await p.setString(_aliasKey, jsonEncode(m));
    await p.setString(_aliasAtKey, now().toIso8601String());
  } catch (_) {
    /* 사전이 없어도 앱 안의 표로 알아듣습니다. */
  }
}

Map<String, String> _aliasesOf(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
