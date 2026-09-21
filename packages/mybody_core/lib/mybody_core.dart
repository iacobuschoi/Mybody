/* =============================================================================
 * mybody_core.dart — 한 군데서 전부 내보냅니다.
 *
 * 화면 쪽에서 `crosscheck.dart` · `engine.dart` 를 하나하나 import 하면
 * 이름이 겹치는 자리(r1 · toISODate · search)에서 조용히 다른 것을
 * 부르게 됩니다. 여기서 한 번에 열어 두고, 겹치는 것은 접두어를 답니다.
 * ========================================================================== */
library;

export 'crosscheck.dart' show run;
export 'data.dart';
export 'engine.dart'
    hide snapshot, lerp, modeLookup;
export 'fooddb.dart' hide search, scaled, byCat, byName;
export 'js_date.dart';
export 'js_num.dart';
export 'modes.dart' hide fill, select, whyNot, alternativesFor, byId, forDisplay;
export 'schedule.dart' hide typeOf, labelOf, indexOf, isKept;
export 'store.dart';
export 'suggest.dart' hide density, portionText, summaryText;

import 'engine.dart' as _engine;
import 'fooddb.dart' as _fooddb;
import 'modes.dart' as _modes;
import 'suggest.dart' as _suggest;

/// 엔진이 modes 를 느슨하게 부르는 고리 (원본의 `global.MB_MODES` 자리).
set engineModeLookup(Map<String, Object?>? Function(Object? id)? fn) =>
    _engine.modeLookup = fn;

/// 겹치는 이름은 접두어를 달아 다시 엽니다 — 어느 쪽을 부르는지 보이게.
/// (`search` 는 음식에도 친구에도 있고, `scaled` 는 음식에만 있지만 짧아서
///  화면 코드에서 무엇을 부르는지 안 보입니다.)
final modeById = _modes.byId;
final modeSelect = _modes.select;
final modeWhyNot = _modes.whyNot;
final modeForDisplay = _modes.forDisplay;
final modeFill = _modes.fill;

final foodSearch = _fooddb.search;
final foodByCat = _fooddb.byCat;
final foodByName = _fooddb.byName;
final foodScaled = _fooddb.scaled;

final suggestSummaryText = _suggest.summaryText;
final suggestPortionText = _suggest.portionText;
final suggestDensity = _suggest.density;
