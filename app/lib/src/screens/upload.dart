/* =============================================================================
 * upload.dart — P03 인바디 넣기 + P04 판독 검수
 *
 * 판독은 3층입니다. 이 화면은 0층과 2층의 입구입니다.
 *
 *   0층  숫자 세 개를 손으로 넣는다              ← 바닥. **항상 됩니다.**
 *   1층  넣은 값을 결과지 안의 다른 값과 검산한다 ← crosscheck
 *   2층  서버에 사진을 보내 초안을 받는다         ← 켜야만 돕니다
 *
 * 왜 0층이 기본인가: 플래너가 실제로 쓰는 숫자는 세 개뿐입니다 — 체중,
 * 골격근량, 체지방률. 사진을 보며 세 칸을 채우는 데 15초쯤 걸립니다.
 * 그리고 2층이 아무리 좋아져도 0층은 남습니다. 서버가 죽어도, 비행기
 * 안이어도, 결과지가 처음 보는 양식이어도 숫자는 들어가야 하니까요.
 * ========================================================================== */
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';

import 'package:mybody_core/mybody_core.dart' as core;

import '../scope.dart';
import '../ui/fmt.dart';
import '../ui/widgets.dart';
import 'review.dart';

/* 0층이 묻는 세 칸. 결과지에서 순서대로 붙어 있는 칸들이라 눈이 위에서
   아래로 한 번만 내려가면 됩니다. */
const _quick = [
  (key: 'weightKg', label: '체중', unit: 'kg', hint: '골격근·지방분석 맨 윗줄'),
  (key: 'smmKg', label: '골격근량', unit: 'kg', hint: '그 아래, SMM'),
  /* 체지방은 **률(%)** 로 받습니다. 사람은 "23%" 로 기억하지 "20.0kg" 으로
     기억하지 않습니다. 저장은 kg 도 같이 — 엔진과 검산이 보는 것. */
  (key: 'pbfPct', label: '체지방률', unit: '%', hint: '그 아래, PBF — kg가 아니라 %'),
];

/// 체중과 체지방률로 체지방량(kg). 결과지에 인쇄된 kg 가 있고 그 값이 이
/// 계산과 반올림 안에서 같으면 인쇄값을 씁니다 — 계산은 0.1 이 흔들립니다.
double bfmFrom(double weightKg, double pbfPct, {Object? printed}) {
  final calc = core.r1(weightKg * pbfPct / 100);
  if (printed is num && (printed.toDouble() - calc).abs() <= 0.15) return printed.toDouble();
  return calc;
}

/// 2층이 읽어 준 나머지 칸(체지방률·BMI·기초대사량…)을 초안에 싣습니다.
///
/// **핵심 세 칸은 사용자가 이깁니다** — 초안에 이미 있는 값은 안 건드립니다.
/// 세 칸만 넘기면 검수 화면이 나머지를 세 칸에서 *계산해* 채우고, 검산은
/// 결과지 값끼리가 아니라 계산값끼리 대조해서 언제나 통과합니다. 원본
/// 웹 앱이 하던 대로 결과지가 준 값을 그대로 싣습니다.
Map<String, Object?> mergeOcrExtras(Map<String, Object?> draft, Map<String, dynamic>? extra) {
  if (extra == null) return draft;
  final out = Map<String, Object?>.of(draft);
  for (final k in reviewFieldKeys) {
    final v = extra[k];
    if (out[k] == null && v is num) out[k] = v;
  }
  out['source'] = 'ocr';
  return out;
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _ctrl = <String, TextEditingController>{
    for (final q in _quick) q.key: TextEditingController(),
  };
  late DateTime _measuredAt = DateTime.now();

  /* 결과지 사진. **이 기기에만** 남습니다. */
  String? _photoId;
  File? _photoFile;
  bool _reading = false;
  String? _ocrNote;
  /// 2층이 읽어 준 **나머지** 칸들. 검수 화면으로 그대로 넘어갑니다.
  Map<String, dynamic>? _serverExtra;
  /// 결과지에 인쇄된 시각(있을 때만). 날짜 칸은 날짜만 받으니 따로 듭니다.
  String? _serverAt;

  Future<void> _pick(ImageSource src) async {
    final picked = await ImagePicker().pickImage(
      source: src,
      // 결과지는 글자만 읽으면 되므로 원본 해상도가 필요 없습니다.
      // 줄여서 넣어야 폰 저장소도, 판독에 보내는 용량도 감당됩니다.
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final photos = Scope.of(context).photos;
    if (photos == null) {
      // 보관소는 앱이 뜬 뒤에 따로 열립니다 — 아주 드물게 아직일 수 있습니다.
      toast(context, '사진을 둘 곳을 아직 못 열었습니다. 한 번 더 눌러 보세요.');
      return;
    }
    final ext = picked.path.split('.').last.toLowerCase();
    final id = await photos.save(await picked.readAsBytes(),
        ext: (ext == 'png' || ext == 'webp') ? ext : 'jpg');
    if (!mounted) return;
    setState(() {
      _photoId = id;
      _photoFile = photos.fileOf(id);
      _ocrNote = null;
      _serverExtra = null;
      _serverAt = null;
    });
  }

  /* 2층. **직접 눌러야 돕니다.** 이게 몸 사진이 기기 밖으로 나가는 단
     하나의 길이라, 사진을 넣었다는 이유만으로 보내지 않습니다. */
  Future<void> _read() async {
    final photos = Scope.of(context).photos;
    final api = Scope.apiOf(context);
    final id = _photoId;
    if (photos == null || id == null) return;
    final payload = photos.payloadOf(id);
    if (payload == null) return;

    setState(() { _reading = true; _ocrNote = null; });
    final r = await api.ocr(mediaType: payload.mediaType, data: payload.data);
    if (!mounted) return;

    if (!r.ok) {
      setState(() { _reading = false; _ocrNote = r.reason; });
      return;
    }
    if (r.body['notInBody'] == true) {
      setState(() {
        _reading = false;
        _ocrNote = '인바디 결과지로 보이지 않습니다 — 다른 사진인지 확인해 주세요.';
      });
      return;
    }
    final fields = (r.body['fields'] as Map?)?.cast<String, dynamic>() ?? {};
    var filled = 0;
    for (final q in _quick) {
      final v = fields[q.key];
      if (v is num) { _ctrl[q.key]!.text = core.jsNumToString(v.toDouble()); filled++; }
    }
    /* 결과지에 %가 없고 kg만 읽혔으면 %로 바꿔 채웁니다. */
    if (_ctrl['pbfPct']!.text.isEmpty && fields['bfmKg'] is num && fields['weightKg'] is num) {
      final w = (fields['weightKg'] as num).toDouble();
      if (w > 0) {
        _ctrl['pbfPct']!.text =
            core.jsNumToString(core.r1((fields['bfmKg'] as num) / w * 100));
        filled++;
      }
    }
    final at = fields['measuredAt'];
    if (at is String) {
      final d = DateTime.tryParse(at);
      if (d != null) _measuredAt = d.toLocal();
      /* 결과지 머리글의 시각을 통째로 둡니다. 날짜만 남기면 저장할 때
         9시가 박히는데, 그건 결과지에 인쇄된 시각이 아닙니다 — 같은 날
         두 번 잰 순서도 잃습니다. */
      _serverAt = RegExp(r'\d{2}:\d{2}').hasMatch(at) ? at : null;
    }
    _serverExtra = fields;
    setState(() {
      _reading = false;
      _ocrNote = filled == _quick.length
          ? '읽었습니다 — **맞는지 보고** 넘어가 주세요.'
          : '$filled칸만 읽었습니다. 나머지는 손으로 넣어 주세요.';
    });
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready => _quick.every((q) {
        final v = double.tryParse(_ctrl[q.key]!.text.trim());
        return v != null && v > 0 && (q.key != 'pbfPct' || v < 100);
      });

  /// 결과지에 인쇄된 시각이 있고 날짜 칸을 안 고쳤으면 그 시각. 없으면 —
  /// 오늘이면 **지금**, 지난 날이면 9시. 오늘 것을 9시로 박으면 같은 날 다른
  /// 기기에서 오후에 넣은 측정보다 앞 순서가 돼 "최신" 이 뒤바뀝니다.
  String measuredAtIso({DateTime? now}) {
    final at = _serverAt == null ? null : DateTime.tryParse(_serverAt!);
    if (at != null) {
      final l = at.toLocal();
      if (l.year == _measuredAt.year && l.month == _measuredAt.month && l.day == _measuredAt.day) {
        return at.toUtc().toIso8601String();
      }
    }
    final n = now ?? DateTime.now();
    if (n.year == _measuredAt.year && n.month == _measuredAt.month && n.day == _measuredAt.day) {
      return n.toUtc().toIso8601String();
    }
    return DateTime(_measuredAt.year, _measuredAt.month, _measuredAt.day, 9)
        .toUtc()
        .toIso8601String();
  }

  void _next() {
    final scan = <String, Object?>{
      'id': 'scan-${DateTime.now().millisecondsSinceEpoch}',
      'measuredAt': measuredAtIso(),
      for (final q in _quick) q.key: double.tryParse(_ctrl[q.key]!.text.trim()),
      // 사진은 이름만 붙여 둡니다. 알맹이는 파일에 있습니다.
      if (_photoId != null) 'photoId': _photoId,
    };
    final w = scan['weightKg'] as double?;
    final pbf = scan['pbfPct'] as double?;
    if (w != null && pbf != null) {
      scan['bfmKg'] = bfmFrom(w, pbf, printed: _serverExtra?['bfmKg']);
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ReviewScreen(draft: mergeOcrExtras(scan, _serverExtra))));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('인바디 올리기')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Note(
          text: '결과지를 보면서 숫자 세 개만 넣으면 됩니다. 나머지는 다음 화면에서 '
              '채우거나, 비워 두면 이 셋에서 계산합니다.',
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('결과지 사진'),
            if (_photoFile != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(_photoFile!,
                    height: 190, width: double.infinity, fit: BoxFit.cover),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _reading ? null : () => _pick(ImageSource.camera),
                icon: const Icon(LucideIcons.camera, size: 18),
                label: const Text('찍기'),
              ),
              OutlinedButton.icon(
                onPressed: _reading ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(LucideIcons.image, size: 18),
                label: const Text('앨범에서'),
              ),
              if (_photoId != null)
                FilledButton.icon(
                  onPressed: _reading ? null : _read,
                  icon: _reading
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.wand2, size: 18),
                  label: Text(_reading ? '읽는 중…' : '사진에서 읽기'),
                ),
            ]),
            if (_ocrNote != null) ...[
              const SizedBox(height: 10),
              RichishText(_ocrNote!,
                  style: t.textTheme.bodySmall?.copyWith(height: 1.5)),
            ],
          ]),
        ),
        MbCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('측정일'),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _measuredAt,
                  firstDate: DateTime(2015),
                  lastDate: DateTime.now(),
                  helpText: '결과지에 찍힌 날짜',
                );
                if (picked != null) setState(() => _measuredAt = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(dateK(_measuredAt.toIso8601String())),
                  const Icon(LucideIcons.calendar, size: 18),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            for (final q in _quick) ...[
              TextField(
                controller: _ctrl[q.key],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: q.label,
                  suffixText: q.unit,
                  helperText: q.hint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ]),
        ),
        FilledButton(
          onPressed: _ready ? _next : null,
          child: const Text('다음 — 검산하기'),
        ),
        const SizedBox(height: 8),
        /* 사진이 어디로 가는지 **먼저** 말합니다. 사진을 넣은 다음에
           알려 주면 늦습니다. */
        Text(
          '사진은 이 기기에만 남습니다. 「사진에서 읽기」를 누를 때만 서버를 거쳐 '
          '판독되고, 서버는 그 사진을 보관하지 않습니다.',
          style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, height: 1.5),
        ),
      ]),
    );
  }
}
