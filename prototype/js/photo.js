/* =============================================================================
 * photo.js — 결과지 사진 (판독 파이프라인 0층의 바닥)
 *
 * 하는 일
 *   1. 고른 사진을 캔버스로 줄여서 데이터 URL 로 만든다
 *   2. 그걸 localStorage 에 따로 보관한다 (상태와 분리)
 *   3. 화면에 다시 띄워 준다 — 숫자를 손으로 넣는 동안 원본을 보면서
 *
 * 왜 줄이는가
 *   (가) 요즘 폰 사진은 4~8MB 입니다. localStorage 는 보통 5MB 가
 *        한도라 원본 한 장이 저장소를 통째로 먹습니다.
 *   (나) 2층(서버 판독)으로 보낼 때 base64 가 4/3 배로 부풀고,
 *        server.js 는 본문 2,000,000 바이트에서 req.destroy() 합니다.
 *        브라우저에는 413 이 아니라 "Failed to fetch" 로 보입니다.
 *        그래서 줄이는 건 선택이 아니라 전제입니다.
 *
 * 사진은 기기 밖으로 나가지 않습니다 — 2층을 사용자가 직접 켜기 전까지는.
 * ========================================================================== */
(function (global) {
  'use strict';

  var KEY = 'mybody.photos.v1';
  var MAX_EDGE = 1600;          // 긴 변 기준. 결과지 숫자는 이 정도면 읽힙니다.
  var KEEP = 6;                 // 최근 몇 장까지 들고 있을지
  var TARGET_BYTES = 900 * 1024; // 데이터 URL 기준 목표 크기 (2층 한도의 절반 이하)

  /* --- 저장소 ------------------------------------------------------------ */
  function load() {
    try { return JSON.parse(localStorage.getItem(KEY)) || {}; }
    catch (e) { return {}; }
  }

  function persist(map) {
    try { localStorage.setItem(KEY, JSON.stringify(map)); return true; }
    catch (e) {
      /* 용량 초과. 사진 때문에 앱 전체가 저장 불가가 되면 안 되므로
         가장 오래된 것부터 버리고 다시 시도합니다. 그래도 안 되면
         사진을 포기합니다 — 숫자는 이미 따로 저장돼 있습니다. */
      var ids = Object.keys(map).sort(function (a, b) {
        return (map[a].at || '') < (map[b].at || '') ? -1 : 1;
      });
      while (ids.length) {
        delete map[ids.shift()];
        try { localStorage.setItem(KEY, JSON.stringify(map)); return true; }
        catch (e2) { /* 계속 버립니다 */ }
      }
      try { localStorage.removeItem(KEY); } catch (e3) {}
      return false;
    }
  }

  function save(id, dataUrl, meta) {
    if (!id || !dataUrl) return false;
    var map = load();
    map[id] = {
      dataUrl: dataUrl, at: new Date().toISOString(),
      w: (meta && meta.w) || 0, h: (meta && meta.h) || 0,
      bytes: dataUrl.length, name: (meta && meta.name) || ''
    };
    // 오래된 것부터 잘라 냅니다
    var ids = Object.keys(map).sort(function (a, b) {
      return (map[a].at || '') < (map[b].at || '') ? 1 : -1;
    });
    ids.slice(KEEP).forEach(function (k) { delete map[k]; });
    return persist(map);
  }

  function get(id) { return id ? (load()[id] || null) : null; }

  function remove(id) {
    var map = load();
    if (!map[id]) return false;
    delete map[id];
    persist(map);
    return true;
  }

  function clearAll() { try { localStorage.removeItem(KEY); } catch (e) {} }

  function usedBytes() {
    var map = load(), n = 0;
    Object.keys(map).forEach(function (k) { n += (map[k].dataUrl || '').length; });
    return n;
  }

  /* --- 줄이기 ------------------------------------------------------------ */

  /**
   * 파일 → 줄인 데이터 URL.
   * @param {File} file
   * @param {function(err, {dataUrl,w,h,bytes,name})} cb
   */
  function fromFile(file, cb) {
    if (!file) return cb(new Error('사진이 없습니다.'));
    var reader = new FileReader();
    reader.onerror = function () { cb(new Error('사진을 읽지 못했습니다.')); };
    reader.onload = function () {
      var src = String(reader.result);
      // 찍은 시각은 원본에서만 나옵니다 — 캔버스를 거치면 EXIF 가 날아갑니다.
      var at = null;
      try { at = exifDate(src); } catch (e) { at = null; }
      fromDataUrl(src, file.name || '', function (err, out) {
        if (out) out.exifAt = at;
        cb(err, out);
      });
    };
    try { reader.readAsDataURL(file); }
    catch (e) { cb(new Error('사진을 읽지 못했습니다.')); }
  }

  function fromDataUrl(src, name, cb) {
    var img = new Image();
    img.onerror = function () {
      /* HEIC/HEIF 는 브라우저가 canvas 로 못 엽니다 (사파리 빼고).
         이 실패는 사용자 잘못이 아니라서, 무엇을 하라는 말까지 같이
         돌려줍니다. */
      cb(new Error('이 형식은 브라우저가 열지 못합니다. ' +
                   '아이폰이면 설정 → 카메라 → 포맷을 "높은 호환성"으로 바꾸거나, ' +
                   'JPG 로 저장해서 올려 주세요.'));
    };
    img.onload = function () {
      var w = img.naturalWidth || img.width, h = img.naturalHeight || img.height;
      if (!(w > 0 && h > 0)) return cb(new Error('사진의 크기를 알 수 없습니다.'));
      var scale = Math.min(1, MAX_EDGE / Math.max(w, h));
      var cw = Math.max(1, Math.round(w * scale)), ch = Math.max(1, Math.round(h * scale));
      var canvas = document.createElement('canvas');
      canvas.width = cw; canvas.height = ch;
      var ctx = canvas.getContext('2d');
      if (!ctx) return cb(new Error('이 브라우저에서는 사진을 줄일 수 없습니다.'));
      ctx.drawImage(img, 0, 0, cw, ch);

      /* 목표 크기에 들어올 때까지 화질을 낮춥니다. 결과지는 글자라
         화질을 꽤 낮춰도 숫자는 남습니다. */
      var q = 0.82, out;
      try { out = canvas.toDataURL('image/jpeg', q); }
      catch (e) { return cb(new Error('사진을 변환하지 못했습니다.')); }
      while (out.length > TARGET_BYTES && q > 0.42) {
        q = Math.round((q - 0.1) * 100) / 100;
        out = canvas.toDataURL('image/jpeg', q);
      }
      cb(null, { dataUrl: out, w: cw, h: ch, bytes: out.length, name: name || '', quality: q });
    };
    img.src = src;
  }

  /* --- 프로필 사진 --------------------------------------------------------
   *
   * 결과지 사진과 다른 점이 두 가지입니다.
   *   (가) 이건 서버로 갑니다. 친구가 봐야 하니까요. 결과지 사진은
   *        기기에만 있습니다. 그래서 크기 한도가 훨씬 빡빡합니다.
   *   (나) 얼굴 사진입니다. 그래서 정사각으로 가운데를 자릅니다 —
   *        원형 틀에 넣었을 때 얼굴이 잘리지 않게.
   *
   * 캔버스에 다시 그리면 EXIF 가 통째로 사라집니다. 그건 부작용이 아니라
   * 여기서 노리는 것입니다: 폰 사진에는 대개 찍은 위치(GPS)와 기기
   * 모델과 시각이 들어 있고, 그게 프로필 사진에 붙어서 친구의 서버로
   * 가면 안 됩니다. 이 함수를 지나온 사진에는 화소만 남습니다.
   */
  var AV_EDGE = 192;              // 원형 프로필에 쓰기 충분합니다
  var AV_BYTES = 24 * 1024;       // 데이터 URL 기준. 서버도 같은 값으로 막습니다.

  function avatarFromFile(file, cb) {
    if (!file) return cb(new Error('사진을 고르지 않았습니다.'));
    if (file.size > 25 * 1024 * 1024) {
      return cb(new Error('사진이 너무 큽니다 (25MB 넘음).'));
    }
    var reader = new FileReader();
    reader.onerror = function () { cb(new Error('사진을 읽지 못했습니다.')); };
    reader.onload = function () { avatarFromDataUrl(String(reader.result || ''), cb); };
    try { reader.readAsDataURL(file); }
    catch (e) { cb(new Error('사진을 읽지 못했습니다.')); }
  }

  function avatarFromDataUrl(src, cb) {
    var img = new Image();
    img.onerror = function () {
      cb(new Error('이 형식은 브라우저가 열지 못합니다. ' +
                   '아이폰이면 설정 → 카메라 → 포맷을 "높은 호환성"으로 바꾸거나, ' +
                   'JPG 로 저장해서 올려 주세요.'));
    };
    img.onload = function () {
      var w = img.naturalWidth || img.width, h = img.naturalHeight || img.height;
      if (!(w > 0 && h > 0)) return cb(new Error('사진의 크기를 알 수 없습니다.'));
      var side = Math.min(w, h);
      var sx = Math.round((w - side) / 2), sy = Math.round((h - side) / 2);
      var canvas = document.createElement('canvas');
      canvas.width = AV_EDGE; canvas.height = AV_EDGE;
      var ctx = canvas.getContext('2d');
      if (!ctx) return cb(new Error('이 브라우저에서는 사진을 줄일 수 없습니다.'));
      ctx.drawImage(img, sx, sy, side, side, 0, 0, AV_EDGE, AV_EDGE);

      var q = 0.8, out;
      try { out = canvas.toDataURL('image/jpeg', q); }
      catch (e) { return cb(new Error('사진을 변환하지 못했습니다.')); }
      while (out.length > AV_BYTES && q > 0.3) {
        q = Math.round((q - 0.1) * 100) / 100;
        out = canvas.toDataURL('image/jpeg', q);
      }
      /* 0.3 까지 낮춰도 안 들어가는 일은 192×192 에서는 사실상 없지만,
         넘은 채로 보내면 서버가 거절합니다. 그럴 때는 여기서 말합니다 —
         서버가 400 을 뱉고 화면이 "알 수 없는 오류"를 띄우는 것보다 낫습니다. */
      if (out.length > AV_BYTES) return cb(new Error('사진을 충분히 줄이지 못했습니다.'));
      cb(null, { dataUrl: out, bytes: out.length, quality: q });
    };
    img.src = src;
  }

  /* --- EXIF 촬영일시 ------------------------------------------------------
   *
   * 측정일은 시계열의 뼈대입니다. 틀리면 "지난 측정과 비교" 가 통째로
   * 어긋나고, 그건 화면 어디에도 안 보이는 종류의 오류입니다.
   * 그런데 사용자에게 날짜를 손으로 넣으라고 하면 대충 오늘로 둡니다.
   *
   * 사진에는 대개 찍은 시각이 들어 있습니다. 그걸 꺼내서 "이 날짜
   * 맞나요?" 라고 묻는 편이, 빈칸을 주고 채우라는 것보다 정확합니다.
   * 결과지를 받은 자리에서 찍는 게 보통이라 촬영일 = 측정일인 경우가
   * 대부분이고, 아니면 사용자가 고치면 됩니다. 자동 확정은 안 합니다.
   *
   * 라이브러리 없이 APP1(Exif) 세그먼트만 직접 읽습니다.
   * ---------------------------------------------------------------------- */

  /** 데이터 URL 앞부분만 디코드해서 바이트로. EXIF 는 파일 맨 앞에 있습니다. */
  function headBytes(dataUrl, maxBytes) {
    var comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    var b64 = dataUrl.slice(comma + 1);
    var take = Math.min(b64.length, Math.floor((maxBytes || 256 * 1024) * 4 / 3));
    take -= take % 4;                        // base64 는 4글자가 3바이트
    try {
      var bin = atob(b64.slice(0, take));
      var u8 = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
      return u8;
    } catch (e) { return null; }
  }

  /**
   * JPEG 데이터 URL → 촬영일시 ISO 문자열 (없으면 null).
   * DateTimeOriginal(0x9003) 을 먼저 보고, 없으면 DateTime(0x0132).
   */
  function exifDate(dataUrl) {
    var u8 = headBytes(dataUrl, 256 * 1024);
    if (!u8 || u8.length < 8 || u8[0] !== 0xFF || u8[1] !== 0xD8) return null;  // SOI 아님

    // APP1 세그먼트 찾기
    var p = 2, app1 = -1, len = 0;
    while (p + 4 <= u8.length) {
      if (u8[p] !== 0xFF) break;
      var marker = u8[p + 1];
      if (marker === 0xD8 || marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) { p += 2; continue; }
      if (marker === 0xDA || marker === 0xD9) break;           // 이미지 데이터 시작
      len = (u8[p + 2] << 8) | u8[p + 3];
      if (marker === 0xE1) { app1 = p + 4; break; }
      p += 2 + len;
    }
    if (app1 < 0 || app1 + 14 > u8.length) return null;
    // "Exif\0\0"
    if (!(u8[app1] === 0x45 && u8[app1 + 1] === 0x78 &&
          u8[app1 + 2] === 0x69 && u8[app1 + 3] === 0x66)) return null;

    var tiff = app1 + 6;
    if (tiff + 8 > u8.length) return null;
    var le = (u8[tiff] === 0x49 && u8[tiff + 1] === 0x49);      // II = little endian
    function u16(o) { return le ? (u8[o] | (u8[o + 1] << 8)) : ((u8[o] << 8) | u8[o + 1]); }
    function u32(o) {
      return le ? ((u8[o] | (u8[o + 1] << 8) | (u8[o + 2] << 16) | (u8[o + 3] << 24)) >>> 0)
                : (((u8[o] << 24) | (u8[o + 1] << 16) | (u8[o + 2] << 8) | u8[o + 3]) >>> 0);
    }
    if (u16(tiff + 2) !== 42) return null;

    var found = { 0x9003: null, 0x0132: null };

    function walkIFD(off, depth) {
      if (depth > 2 || off + 2 > u8.length) return;
      var count = u16(off);
      if (count > 512) return;                                  // 망가진 파일 방어
      for (var i = 0; i < count; i++) {
        var e = off + 2 + i * 12;
        if (e + 12 > u8.length) return;
        var tag = u16(e), type = u16(e + 2), num = u32(e + 4);
        if (tag === 0x8769 || tag === 0xA005) {                  // Exif / Interop IFD 포인터
          walkIFD(tiff + u32(e + 8), depth + 1);
          continue;
        }
        if (found.hasOwnProperty(tag) && type === 2 && num >= 19) {
          var vo = (num > 4) ? tiff + u32(e + 8) : e + 8;
          if (vo + 19 > u8.length) continue;
          var str = '';
          for (var j = 0; j < 19; j++) str += String.fromCharCode(u8[vo + j]);
          found[tag] = str;
        }
      }
    }
    walkIFD(tiff + u32(tiff + 4), 0);

    var raw = found[0x9003] || found[0x0132];
    if (!raw) return null;
    // "2026:09:19 11:09:33"
    var m = /^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/.exec(raw);
    if (!m) return null;
    var y = +m[1], mo = +m[2], d = +m[3];
    if (!(y >= 1990 && y <= 2100 && mo >= 1 && mo <= 12 && d >= 1 && d <= 31)) return null;
    var dt = new Date(y, mo - 1, d, +m[4], +m[5], +m[6]);
    if (isNaN(dt.getTime())) return null;
    // 미래 사진은 시계가 틀린 것입니다 — 믿지 않습니다.
    if (dt.getTime() > Date.now() + 86400000) return null;

    /* EXIF 의 시각에는 시간대가 없습니다. 카메라가 있던 곳의 벽시계
       시각일 뿐입니다. 그걸 toISOString() 으로 바꾸면 UTC 로 밀리고,
       한국에서 아침 7시 36분에 찍은 사진이 2026-09-18 이 됩니다 —
       하루 전입니다.
       인바디는 아침에 재는 것이 정석이라, 제대로 재는 사람일수록
       모든 측정이 하루씩 밀립니다. 그러면 "지난 측정과 며칠 차이"
       와 주간 창이 전부 어긋납니다.
       그래서 시간대를 붙이지 않은 현지 시각 그대로 돌려줍니다.
       앱의 다른 곳(quickISO)도 같은 모양을 씁니다. */
    function two(x) { return String(x).padStart(2, '0'); }
    return y + '-' + two(mo) + '-' + two(d) + 'T' +
           two(+m[4]) + ':' + two(+m[5]) + ':' + two(+m[6]);
  }

  global.MB_PHOTO = {
    fromFile: fromFile, fromDataUrl: fromDataUrl,
    save: save, get: get, remove: remove, clearAll: clearAll,
    usedBytes: usedBytes, list: load, exifDate: exifDate,
    MAX_EDGE: MAX_EDGE, TARGET_BYTES: TARGET_BYTES, KEEP: KEEP,
    AV_EDGE: AV_EDGE, AV_BYTES: AV_BYTES,
    avatarFromFile: avatarFromFile, avatarFromDataUrl: avatarFromDataUrl
  };
})(window);
