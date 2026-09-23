/* =============================================================================
 * photos.dart — 결과지 사진을 이 기기에 둡니다
 *
 * **서버로 안 보냅니다.** 자동 판독을 직접 켠 경우에만, 그때 한 장이
 * 판독을 거쳐 갑니다 (그리고 서버는 그걸 보관하지 않습니다).
 *
 * 왜 파일인가: 결과지 한 장이 base64 로 수백 KB 입니다. 설정 저장소
 * (SharedPreferences)는 작은 값을 담는 곳이라, 사진을 거기 넣으면 앱이
 * 켜질 때마다 그걸 전부 메모리로 끌어올립니다. 사진은 파일로 두고,
 * 상태에는 **이름만** 남깁니다.
 * ========================================================================== */
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:mybody_core/mybody_core.dart' as core;
import 'package:path_provider/path_provider.dart';

class FilePhotos implements core.PhotoHost {
  FilePhotos._(this._dir, this._index);

  final Directory _dir;
  /// id → 확장자. 목록을 낼 때 디스크를 훑지 않으려고 들고 있습니다.
  final Map<String, String> _index;

  /// 시험·스크린샷용: 플랫폼 플러그인 없이 아무 폴더에나 엽니다(빈 목록으로).
  @visibleForTesting
  static FilePhotos at(Directory dir) {
    dir.createSync(recursive: true);
    return FilePhotos._(dir, <String, String>{});
  }

  static Future<FilePhotos> open() async {
    /* 폴더 위치는 플랫폼 플러그인이 알려 줍니다. 그게 대답을 안 하면
     * (시험 환경, 혹은 플러그인이 깨진 기기) 이 await 는 영영 안 끝납니다 —
     * 그래서 앱은 이걸 **기다리지 않고** 뜹니다 (`AppState.boot`). */
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/inbody-photos');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final index = <String, String>{};
    for (final f in dir.listSync()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot > 0) index[name.substring(0, dot)] = name.substring(dot + 1);
    }
    return FilePhotos._(dir, index);
  }

  File _fileOf(String id) => File('${_dir.path}/$id.${_index[id] ?? 'jpg'}');

  /// 코어는 **어떤 사진이 있는지만** 알면 됩니다. 알맹이는 화면이 읽습니다.
  @override
  Map<String, Object?> list() => {for (final id in _index.keys) id: true};

  @override
  void remove(String id) {
    final f = _fileOf(id);
    if (f.existsSync()) f.deleteSync();
    _index.remove(id);
  }

  @override
  void clearAll() {
    for (final id in _index.keys.toList()) {
      remove(id);
    }
  }

  bool has(String id) => _index.containsKey(id);

  File? fileOf(String id) {
    if (!_index.containsKey(id)) return null;
    final f = _fileOf(id);
    return f.existsSync() ? f : null;
  }

  /// 새 사진을 넣고 붙여 둘 이름을 돌려줍니다.
  Future<String> save(List<int> bytes, {String ext = 'jpg'}) async {
    final id = 'p${DateTime.now().millisecondsSinceEpoch}';
    await File('${_dir.path}/$id.$ext').writeAsBytes(bytes);
    _index[id] = ext;
    return id;
  }

  /// 판독에 보낼 때 쓰는 꼴. 서버는 `{mediaType, data}` 를 받습니다.
  static String mediaTypeOf(String ext) =>
      ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');

  ({String mediaType, String data})? payloadOf(String id) {
    final f = fileOf(id);
    if (f == null) return null;
    return (mediaType: mediaTypeOf(_index[id] ?? 'jpg'),
            data: base64Encode(f.readAsBytesSync()));
  }
}
