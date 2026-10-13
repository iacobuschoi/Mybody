/* =============================================================================
 * voice_set.dart — 받아쓴 말을 세트로 풀기
 *
 * 헬스 화면의 「누르고 말하기」 가 받아쓴 글(「벤치 80키로 4개」)을 종목 · 무게 ·
 * 횟수 · 세트 수로 풉니다. 화면은 이 답을 **확인 시트**에 보여 주고, 사용자가
 * 고친 뒤에 기록합니다 — 여기서 틀려도 기록이 바로 틀리지는 않습니다. 그래서
 * 이 파일은 **너그럽게** 읽는 쪽으로 기울어 있습니다:
 *
 *   · 숫자: 아라비아(80 · 82.5) · 한자어(팔십 · 백이십 · 팔십이점오) · 고유어
 *     (네 · 다섯 · 열두 · 스무). 「세」 「네」 「한」 「두」 같은 한 글자 고유어와 「일」 「이」
 *     는 단위가 바로 붙을 때만 숫자로 봅니다 — 「네」 는 대답이고, 「이」 는 조사입니다.
 *   · 단위: 무게 = 키로 · 킬로 · kg · 케이지 · 킬로그램(+그람), 횟수 = 개 · 회 · 번 · 렙,
 *     세트 = 세트 · 셋트. 「개씩」 「회씩」 도 횟수입니다.
 *   · 단위 없는 숫자는 빈 칸에 차례로 — 무게 → 횟수. 소수점이 있으면 무게, 맨몸 ·
 *     밴드 종목이면 전부 횟수. 「벤치 80 다섯개」 → 80kg × 5.
 *   · 한 마디에 여러 세트: 「80키로 5개 85키로 3개」 → 두 세트, 「80키로 5개 5개 5개」 →
 *     80kg 세 세트, 「80키로 5개씩 3세트」 → 80kg × 5 가 세 세트.
 *   · 종목: 숫자와 단위를 걷어낸 나머지로 찾습니다. 오늘 목록에서 먼저(「벤치」 라고 했는데
 *     오늘 종목이 덤벨 벤치프레스면 그것), 그다음 사전(이름 · 별칭 · 부분 일치), 그래도
 *     없으면 자모를 풀어 가장 가까운 것(받아쓰기 오류 — 「밴치」 「스쿼드」 「렛풀」). 짧게
 *     부르는 말(벤치 · 스쿼트 · 데드 · 숄더 · 렛풀)은 표(kSpokenShortNames)에 있습니다.
 *     충분히 가깝지 않으면 null — 확인 시트가 「종목 고르기」 를 띄웁니다.
 *
 * 순수 Dart 입니다 — 화면 없이 `flutter test test/voice_set_test.dart` 로 돕니다.
 * ========================================================================== */
library;

import 'exercises.dart';

/// 말에서 읽은 세트 하나. [exercise] 가 null 이면 종목을 못 찾은 것 — 그래도 [spokenName]
/// 은 남겨서 확인 시트가 「"밴치" 라고 들었어요」 를 보여 줄 수 있게 합니다.
class SpokenSet {
  SpokenSet({this.exercise, this.spokenName = '', this.kg, this.reps, this.count = 1});

  Exercise? exercise;
  /// 숫자 · 단위를 걷어낸 나머지 말(종목으로 들린 부분).
  String spokenName;
  double? kg;
  int? reps;
  /// 같은 무게 · 횟수를 몇 세트 — 「5개씩 3세트」 의 3.
  int count;

  bool get hasNumbers => kg != null || reps != null;

  /// 확인 시트 · 시험이 읽는 한 줄 — '바벨 벤치프레스 80kg × 4 (3세트)'.
  String get summary {
    final name = exercise?.name ?? (spokenName.isEmpty ? '종목 모름' : '"$spokenName"');
    final parts = <String>[
      if (kg != null) '${kgText(kg!)}kg',
      if (reps != null) '$reps회',
    ];
    final tail = count > 1 ? ' ($count세트)' : '';
    return '$name${parts.isEmpty ? '' : ' ${parts.join(' × ')}'}$tail';
  }

  /// 82.5 → '82.5', 80.0 → '80'.
  static String kgText(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? '${r.round()}' : '$r';
  }
}

/// 한 마디를 푼 결과.
class SpokenEntry {
  SpokenEntry({required this.transcript, required this.sets});
  final String transcript;
  final List<SpokenSet> sets;

  /// 숫자가 하나도 없고 종목도 없으면 — 못 알아들은 것입니다.
  bool get empty => sets.isEmpty || sets.every((s) => !s.hasNumbers && s.exercise == null);
}

/* ---------------------------------------------------------------------------
 * 짧게 부르는 말 → 종목 id. 헬스장에서 실제로 쓰는 말과 받아쓰기가 자주 내는 모양을
 * 같이 둡니다. 오늘 목록에 같은 계열(벤치 → 덤벨 벤치프레스)이 있으면 목록이 이깁니다 —
 * 이 표는 목록에 없을 때의 기본값입니다.
 * ------------------------------------------------------------------------ */
const Map<String, String> kSpokenShortNames = {
  '벤치': 'bench-press', '벤치프레스': 'bench-press', '밴치': 'bench-press', '벤취': 'bench-press',
  '벤츠': 'bench-press', '뺀치': 'bench-press', '벤지': 'bench-press', '벤치프래스': 'bench-press',
  '플랫벤치': 'bench-press', '바벨벤치': 'bench-press',
  '덤벨벤치': 'db-bench-press', '덤벨프레스': 'db-bench-press',
  '인클라인': 'incline-db-press', '인클라인벤치': 'incline-barbell-press',
  '체스트프레스': 'chest-press-machine', '체스트': 'chest-press-machine',
  '스쿼트': 'barbell-squat', '스쿼드': 'barbell-squat', '스콰트': 'barbell-squat', '스쾃': 'barbell-squat',
  '스쿼': 'barbell-squat', '스쿼츠': 'barbell-squat',
  '데드': 'deadlift', '데드리프트': 'deadlift', '대드리프트': 'deadlift', '데들': 'deadlift', '데드립': 'deadlift',
  '루마니안': 'rdl', '알디엘': 'rdl', 'rdl': 'rdl',
  '렛풀': 'pullup-latpulldown', '랫풀': 'pullup-latpulldown', '렛풀다운': 'pullup-latpulldown',
  '랫풀다운': 'pullup-latpulldown', '풀다운': 'pullup-latpulldown', '풀업': 'pull-up', '턱걸이': 'pull-up',
  '친업': 'pull-up',
  '로우': 'barbell-row', '바벨로우': 'barbell-row', '시티드로우': 'seated-cable-row', '케이블로우': 'seated-cable-row',
  '덤벨로우': 'one-arm-db-row', '티바': 't-bar-row',
  '숄더': 'db-shoulder-press', '숄더프레스': 'db-shoulder-press', '숄다': 'db-shoulder-press',
  '오버헤드': 'overhead-press', '오버헤드프레스': 'overhead-press', '밀리터리': 'overhead-press',
  '밀리터리프레스': 'overhead-press', '오에이치피': 'overhead-press',
  '사레레': 'lateral-raise', '사이드레터럴': 'lateral-raise', '레터럴': 'lateral-raise', '레터럴레이즈': 'lateral-raise',
  '래터럴': 'lateral-raise', '측면': 'lateral-raise',
  '레그프레스': 'leg-press', '레그프래스': 'leg-press', '렉프레스': 'leg-press', '레그': 'leg-press',
  '레그익스텐션': 'leg-extension', '익스텐션': 'leg-extension', '레그컬': 'leg-curl', '레그걸': 'leg-curl',
  '런지': 'lunge', '불가리안': 'bulgarian-split-squat', '핵스쿼트': 'hack-squat',
  '힙쓰러스트': 'hip-thrust', '힙스러스트': 'hip-thrust', '힙트러스트': 'hip-thrust',
  '컬': 'db-curl', '덤벨컬': 'db-curl', '바벨컬': 'barbell-curl', '해머컬': 'hammer-curl', '이지바': 'ez-bar-curl',
  '푸시다운': 'cable-pushdown', '푸쉬다운': 'cable-pushdown', '케이블푸시다운': 'cable-pushdown',
  '딥스': 'dips', '딥': 'dips',
  '푸시업': 'push-up', '푸쉬업': 'push-up', '팔굽혀펴기': 'push-up',
  '플랭크': 'plank', '크런치': 'cable-crunch', '카프': 'calf-raise', '카프레이즈': 'calf-raise', '종아리': 'calf-raise',
  '페이스풀': 'face-pull', '슈러그': 'db-shrug', '쉬러그': 'db-shrug',
};

/* ---------------------------------------------------------------------------
 * 숫자 읽기
 * ------------------------------------------------------------------------ */

const _sinoDigit = {'영': 0, '공': 0, '일': 1, '이': 2, '삼': 3, '사': 4, '오': 5, '육': 6, '륙': 6, '칠': 7, '팔': 8, '구': 9};
const _sinoUnit = {'십': 10, '백': 100, '천': 1000};

/// 한자어 수 — '팔십' 80 · '백이십' 120 · '이천' 2000 · '십오' 15. 못 읽으면 null.
double? _sino(String s) {
  if (s.isEmpty) return null;
  var total = 0, cur = 0;
  var any = false;
  for (final ch in s.split('')) {
    final d = _sinoDigit[ch];
    final u = _sinoUnit[ch];
    if (d != null) {
      cur = cur * 10 + d;
      any = true;
    } else if (u != null) {
      total += (cur == 0 ? 1 : cur) * u;
      cur = 0;
      any = true;
    } else {
      return null;
    }
  }
  return any ? (total + cur).toDouble() : null;
}

const _nativeTens = {'열': 10, '스물': 20, '스무': 20, '서른': 30, '마흔': 40, '쉰': 50, '예순': 60, '일흔': 70, '여든': 80, '아흔': 90};
const _nativeOnes = {
  '하나': 1, '한': 1, '둘': 2, '두': 2, '셋': 3, '세': 3, '석': 3, '넷': 4, '네': 4, '넉': 4,
  '다섯': 5, '여섯': 6, '일곱': 7, '여덟': 8, '여덜': 8, '아홉': 9,
};

/// 고유어 수 — '네' 4 · '열두' 12 · '스물다섯' 25 · '서른' 30. 못 읽으면 null.
double? _native(String s) {
  if (s.isEmpty) return null;
  var rest = s;
  var v = 0;
  for (final e in _nativeTens.entries) {
    if (rest.startsWith(e.key)) {
      v += e.value;
      rest = rest.substring(e.key.length);
      break;
    }
  }
  if (rest.isNotEmpty) {
    final o = _nativeOnes[rest];
    if (o == null) return null;
    v += o;
  }
  return v == 0 ? null : v.toDouble();
}

/// 숫자 토큰 → 값. 아라비아('82.5' · '82,5' · '82점5') · 한자어('팔십이점오') · 고유어.
double? spokenNumber(String tok) {
  final t = tok.trim();
  if (t.isEmpty) return null;
  final arabic = RegExp(r'^(\d+)(?:[.,점쩜](\d+))?$').firstMatch(t);
  if (arabic != null) return double.tryParse('${arabic.group(1)}.${arabic.group(2) ?? '0'}');
  final sinoDec = RegExp(r'^([영공일이삼사오육륙칠팔구십백천]+)(?:[점쩜]([영공일이삼사오육륙칠팔구]+))?$').firstMatch(t);
  if (sinoDec != null) {
    final whole = _sino(sinoDec.group(1)!);
    if (whole == null) return null;
    final frac = sinoDec.group(2);
    if (frac == null) return whole;
    final digits = [for (final ch in frac.split('')) _sinoDigit[ch]];
    if (digits.any((d) => d == null)) return null;
    return double.tryParse('${whole.round()}.${digits.join()}');
  }
  return _native(t);
}

/* ---------------------------------------------------------------------------
 * 토큰 — 숫자(+단위)와 그 밖의 말
 * ------------------------------------------------------------------------ */

const _kgUnit = r'(?:킬로그램|키로그램|킬로그람|키로그람|킬로|키로|케이지|kg|㎏|KG|Kg)';
const _repUnit = r'(?:개씩|회씩|번씩|개|회|번|렙스|렙|reps|rep)';
const _setUnit = r'(?:세트씩|세트|셋트|쎄트|sets|set)';
const _numArabic = r'\d+(?:[.,점쩜]\d+)?';
const _numSino = r'[영공일이삼사오육륙칠팔구십백천]+(?:[점쩜][영공일이삼사오육륙칠팔구]+)?';
const _numNative =
    r'(?:열|스물|스무|서른|마흔|쉰|예순|일흔|여든|아흔)(?:하나|한|둘|두|셋|세(?!트)|석|넷|네|넉|다섯|여섯|일곱|여덟|여덜|아홉)?'
    r'|(?:하나|한|둘|두|셋|세(?!트)|석|넷|네|넉|다섯|여섯|일곱|여덟|여덜|아홉)';

/* 고유어를 한자어보다 먼저 — 「일곱」 을 한자어 「일」 + 「곱」 으로 끊으면 7 을 잃습니다. */
final RegExp _numberRe = RegExp(
  '($_numArabic|$_numNative|$_numSino)\\s*($_kgUnit|$_repUnit|$_setUnit)?',
  caseSensitive: false,
);

/// 단위 없는 한자어 수는 「십 · 백 · 천」 이 든 것만 — 「사이드」 의 「사이」, 「오버헤드」 의 「오」,
/// 「삼두」 의 「삼」 은 숫자가 아닙니다. 아라비아 · 고유어(다섯 · 열두)는 그대로 숫자입니다.
bool _bareOk(String tok) {
  if (RegExp(r'^\d').hasMatch(tok)) return true;
  if (_needsUnit.contains(tok)) return false;
  if (RegExp(r'^[영공일이삼사오육륙칠팔구십백천점쩜]+$').hasMatch(tok)) return RegExp(r'[십백천]').hasMatch(tok);
  return true;
}

/// 한 글자짜리 수 말 — 단위가 붙을 때만 숫자입니다('네' 는 대답, '이' 는 조사, '한' 은 관형사).
const _needsUnit = {'일', '이', '한', '두', '세', '네', '석', '넉', '공', '영'};

enum _Kind { bare, kg, rep, set }

class _Num {
  _Num(this.value, this.kind, this.start, this.end);
  final double value;
  final _Kind kind;
  final int start, end;
}

_Kind _kindOf(String? unit) {
  if (unit == null || unit.isEmpty) return _Kind.bare;
  if (RegExp('^$_kgUnit\$', caseSensitive: false).hasMatch(unit)) return _Kind.kg;
  if (RegExp('^$_setUnit\$', caseSensitive: false).hasMatch(unit)) return _Kind.set;
  return _Kind.rep;
}

/// 숫자(단위 포함)를 뽑고, 나머지 글(종목으로 들린 부분)을 돌려줍니다.
({List<_Num> nums, String rest}) _tokenize(String text) {
  final nums = <_Num>[];
  final buf = StringBuffer();
  var last = 0;
  for (final m in _numberRe.allMatches(text)) {
    final tok = m.group(1)!;
    final unit = m.group(2);
    final kind = _kindOf(unit);
    /* 'k' 는 단위로 안 받습니다(케이블 · 킥백의 첫소리와 겹침). 숫자 바로 뒤의 'k' 만 kg. */
    final v = spokenNumber(tok);
    final glued = m.start > 0 && RegExp(r'[가-힣a-z]', caseSensitive: false).hasMatch(text[m.start - 1]);
    final skip = v == null ||
        (kind == _Kind.bare && !_bareOk(tok)) ||
        /* 말 가운데 붙은 수 글자('이지바' 의 '이', '페이스풀' 의 '이' 는 앞 글자에 이어진 것) */
        (kind == _Kind.bare && glued && !RegExp(r'^\d').hasMatch(tok)) ||
        /* 한 글자 수 + 단위가 앞 글자에 이어 붙은 것 — 아라비아 숫자면 믿습니다 */
        (kind != _Kind.bare && glued && !RegExp(r'^\d').hasMatch(tok) && _needsUnit.contains(tok));
    if (skip) continue;
    buf.write(text.substring(last, m.start));
    buf.write(' ');
    last = m.end;
    nums.add(_Num(v, kind, m.start, m.end));
  }
  buf.write(text.substring(last));
  return (nums: nums, rest: buf.toString());
}

/* ---------------------------------------------------------------------------
 * 종목 찾기
 * ------------------------------------------------------------------------ */

/// 종목 이름이 아닌 말 — 걷어냅니다.
const _fillers = {
  '그리고', '다음', '다음에', '그다음', '또', '어', '음', '으음', '네', '예', '응', '자',
  '했어', '했음', '했다', '했습니다', '했어요', '함', '완료', '끝', '기록', '추가', '넣어', '넣어줘',
  '세트완료', '오늘', '방금', '지금', '한번더', '더', '하고', '랑', '이랑', '에', '에서', '으로', '로',
  '이거', '그거', '요', '좀', '해줘', '해', '했', '개', '회', '번', '키로', '킬로', '세트',
};

/// 조사 떼기 — '벤치프레스를' → '벤치프레스'. 두 글자 이상 남을 때만.
String _stripParticle(String w) {
  for (final p in const ['으로', '에서', '이랑', '하고', '을', '를', '은', '는', '이', '가', '에', '로', '랑', '도', '요']) {
    if (w.length > p.length + 1 && w.endsWith(p)) return w.substring(0, w.length - p.length);
  }
  return w;
}

String _loose(String s) => s.replaceAll(RegExp(r'[\s\-_/·()]+'), '').toLowerCase();

/// 자모 분해 — 받아쓰기 오류는 대개 모음 · 받침 하나입니다. 글자 단위로 견주면 「밴치」 와
/// 「벤치」 가 전혀 다른 글자지만, 자모로 풀면 ㅂㅐㄴㅊㅣ 와 ㅂㅔㄴㅊㅣ — 한 자리 차이입니다.
List<String> _jamo(String s) {
  const cho = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];
  const jung = ['ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ', 'ㅙ', 'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ'];
  const jong = ['', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];
  final out = <String>[];
  for (final r in s.runes) {
    if (r >= 0xAC00 && r <= 0xD7A3) {
      final i = r - 0xAC00;
      out.add(cho[i ~/ 588]);
      out.add(jung[(i % 588) ~/ 28]);
      final j = jong[i % 28];
      if (j.isNotEmpty) out.add(j);
    } else {
      out.add(String.fromCharCode(r));
    }
  }
  return out;
}

int _levenshtein(List<String> a, List<String> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// 0(다름) ~ 1(같음). 자모 단위.
double spokenSimilarity(String a, String b) {
  final ja = _jamo(_loose(a)), jb = _jamo(_loose(b));
  if (ja.isEmpty || jb.isEmpty) return 0;
  final d = _levenshtein(ja, jb);
  final n = ja.length > jb.length ? ja.length : jb.length;
  return 1 - d / n;
}

/// 종목으로 들린 말 → 종목. [today] 는 오늘 목록의 이름(먼저 봅니다).
/// 순서: 오늘 목록(정확 → 포함 → 짧은 말 계열) → 짧은 말 표 → 사전 이름 · 별칭 → 자모 유사도.
Exercise? matchSpokenExercise(String spoken, {List<String> today = const []}) {
  final q = _loose(spoken);
  if (q.isEmpty) return null;
  final todayEx = [for (final n in today) exerciseByName(n) ?? Exercise(id: slugOf(n), name: n, group: 'full', equip: 'bodyweight', met: 3.5)];

  /* 1. 오늘 목록 — 글자 그대로 · 포함(「벤치」 ⊂ 「덤벨 벤치프레스」) · 별칭. */
  for (final e in todayEx) {
    if (_loose(e.name) == q) return e;
  }
  for (final e in todayEx) {
    if (_loose(e.name).contains(q) || e.aliases.any((a) => _loose(a) == q)) return e;
  }
  /* 2. 짧은 말 표 — 같은 계열이 오늘 목록에 있으면 그것(「벤치」 → 오늘의 스미스 벤치프레스). */
  final short = kSpokenShortNames[q];
  if (short != null) {
    final base = exerciseById(short);
    if (base != null) {
      for (final e in todayEx) {
        if (e.id == base.id) return e;
        if (e.group == base.group && e.pattern == base.pattern && _loose(e.name).contains(_coreWord(q))) return e;
      }
      return base;
    }
  }
  /* 3. 사전 — 이름 · 별칭. 부분 일치는 짧은 쪽이 여럿에 걸리므로 가장 짧은 이름을 고릅니다. */
  final exact = exerciseByAlias(spoken);
  if (exact != null) return exact;
  final hits = searchExercises(spoken);
  if (hits.isNotEmpty) {
    hits.sort((a, b) => a.name.length.compareTo(b.name.length));
    return hits.first;
  }
  /* 4. 자모 유사도 — 오늘 목록은 조금 낮아도(0.6) 받고, 사전은 더 가까워야(0.72) 받습니다. */
  Exercise? best;
  var bestScore = 0.0;
  void consider(Exercise e, String name, double floor) {
    final s = spokenSimilarity(q, name);
    if (s >= floor && s > bestScore) {
      best = e;
      bestScore = s;
    }
  }
  for (final e in todayEx) {
    consider(e, e.name, 0.6);
    for (final a in e.aliases) {
      consider(e, a, 0.6);
    }
  }
  if (best != null) return best;
  for (final k in kSpokenShortNames.keys) {
    final e = exerciseById(kSpokenShortNames[k]!);
    if (e != null) consider(e, k, 0.72);
  }
  for (final e in kExerciseLibrary) {
    consider(e, e.name, 0.72);
    for (final a in e.aliases) {
      consider(e, a, 0.72);
    }
  }
  return best;
}

/// 짧은 말의 알맹이 — '벤치프레스' · '밴치' → '벤치'. 오늘 목록에서 같은 계열을 찾을 때 씁니다.
String _coreWord(String q) {
  for (final w in const ['벤치', '스쿼트', '데드', '풀다운', '로우', '숄더', '프레스', '컬', '런지', '레이즈']) {
    if (q.contains(w)) return w;
  }
  return q.length > 2 ? q.substring(0, 2) : q;
}

/* ---------------------------------------------------------------------------
 * 전체 — 말 한 마디 → 세트들
 * ------------------------------------------------------------------------ */

/// [text] 를 풉니다. [today] 는 오늘 목록의 종목 이름. [weightless] 는 종목이 맨몸 · 밴드인지
/// 판단하는 함수(없으면 사전의 기구로 봅니다) — 단위 없는 숫자를 횟수로 볼지 정합니다.
SpokenEntry parseSpokenSets(String text, {List<String> today = const [], bool Function(Exercise)? weightless}) {
  final raw = text.trim();
  /* Dart 의 replaceAll 은 '$1' 을 글자 그대로 넣습니다 — 묶음을 쓰려면 replaceAllMapped. */
  final norm = raw
      .replaceAll(RegExp(r'[，、]'), ',')
      .replaceAllMapped(RegExp(r'(\d)\s*,\s*(\d{3})\b'), (m) => '${m[1]}${m[2]}')   // 1,000 → 1000
      .replaceAllMapped(RegExp(r'(\d)\s*\.\s*(\d)'), (m) => '${m[1]}.${m[2]}')
      .replaceAll(RegExp(r'[×xX*]'), ' ')                                              // '80x5' → '80 5'
      .replaceAll(RegExp(r'\bkg\b', caseSensitive: false), '키로 ')
      .replaceAllMapped(RegExp(r'(\d)\s*k\b', caseSensitive: false), (m) => '${m[1]}키로 ');
  final tk = _tokenize(norm);

  /* 종목으로 들린 말. 조사는 떼지 않은 채로 먼저 찾고(「플라이」 의 「이」 는 조사가 아닙니다),
     못 찾으면 뗀 것으로 다시 찾습니다(「벤치프레스를」). */
  final rawWords = <String>[], stripped = <String>[];
  for (final w in tk.rest.split(RegExp(r'[\s,.!?~]+'))) {
    if (w.isEmpty) continue;
    final s = _stripParticle(w);
    if (_fillers.contains(s) || _fillers.contains(w)) continue;
    if (RegExp(r'^[^가-힣a-zA-Z]+$').hasMatch(s)) continue;
    rawWords.add(w);
    stripped.add(s);
  }
  final spokenName = rawWords.join(' ').trim();
  final strippedName = stripped.join(' ').trim();
  final ex = spokenName.isEmpty
      ? null
      : matchSpokenExercise(spokenName, today: today) ??
          (strippedName == spokenName ? null : matchSpokenExercise(strippedName, today: today));
  bool noKg(Exercise? e) {
    if (e == null) return false;
    if (weightless != null) return weightless(e);
    return e.equip == 'bodyweight' || e.equip == 'band';
  }

  /* 숫자 → 세트. 단위 있는 것부터 자리를 잡고, 단위 없는 것은 빈 칸에. */
  final sets = <SpokenSet>[];
  SpokenSet cur = SpokenSet(exercise: ex, spokenName: spokenName);
  void push() {
    if (cur.hasNumbers || cur.count > 1) sets.add(cur);
    cur = SpokenSet(exercise: ex, spokenName: spokenName, kg: cur.kg);
  }
  final bare = <_Num>[];
  var lastKind = _Kind.bare;
  for (final n in tk.nums) {
    switch (n.kind) {
      case _Kind.kg:
        /* 무게가 또 오면 새 세트 — 「80키로 5개 85키로 3개」. 횟수 없이 무게만 둘이면(「80키로 85키로」)
           앞 것을 버리지 않고 각각 한 세트로 둡니다. */
        if (cur.kg != null && (cur.reps != null || lastKind == _Kind.kg)) push();
        cur.kg = n.value;
      case _Kind.rep:
        if (cur.reps != null) {
          push();
        }
        cur.reps = n.value.round();
      case _Kind.set:
        cur.count = n.value.round().clamp(1, 20);
      case _Kind.bare:
        bare.add(n);
    }
    lastKind = n.kind;
  }
  if (cur.hasNumbers || cur.count > 1) sets.add(cur);

  /* 단위 없는 숫자. 맨몸 · 밴드면 전부 횟수. 아니면 소수점 → 무게, 그 밖은 빈 칸에 무게 → 횟수 순. */
  if (bare.isNotEmpty) {
    if (sets.isEmpty) sets.add(SpokenSet(exercise: ex, spokenName: spokenName));
    final isBw = noKg(ex);
    for (final n in bare) {
      var target = sets.last;
      final v = n.value;
      final decimal = v != v.roundToDouble();
      if (isBw) {
        if (target.reps != null) {
          target = SpokenSet(exercise: ex, spokenName: spokenName);
          sets.add(target);
        }
        target.reps = v.round();
      } else if (target.kg == null && (decimal || v >= 10 || target.reps != null)) {
        target.kg = v;
      } else if (target.reps == null && !decimal) {
        target.reps = v.round();
      } else {
        /* 두 칸이 다 찼으면 새 세트 — 「80 5 5 5」 → 80kg 세 세트. */
        final next = SpokenSet(exercise: ex, spokenName: spokenName, kg: decimal ? v : target.kg);
        if (!decimal) next.reps = v.round();
        sets.add(next);
      }
    }
  }

  /* 무게 없이 횟수만 있는 뒤 세트는 앞 세트의 무게를 이어받습니다(「80키로 5개 5개」). */
  double? carry;
  for (final s in sets) {
    if (s.kg != null) {
      carry = s.kg;
    } else if (carry != null && !noKg(s.exercise)) {
      s.kg = carry;
    }
  }
  /* 숫자가 없는데 종목만 들렸으면 한 줄로 남깁니다 — 확인 시트가 무게 · 횟수를 묻습니다. */
  if (sets.isEmpty && ex != null) sets.add(SpokenSet(exercise: ex, spokenName: spokenName));
  /* 말이 안 되는 값은 비웁니다 — 1,000kg · 500회는 받아쓰기가 숫자를 붙인 것입니다. */
  for (final s in sets) {
    if (s.kg != null && (s.kg! <= 0 || s.kg! > 500)) s.kg = null;
    if (s.reps != null && (s.reps! <= 0 || s.reps! > 200)) s.reps = null;
  }
  return SpokenEntry(transcript: raw, sets: sets);
}
