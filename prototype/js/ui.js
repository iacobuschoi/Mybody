/* =============================================================================
 * ui.js — DOM 헬퍼 · 모달 · 차트 (라이브러리 없음, 순수 SVG)
 * ========================================================================== */
(function (global) {
  'use strict';

  /** h('div.card', {attrs}, children) — 아주 작은 hyperscript */
  function h(sel, attrs, children) {
    var m = /^([a-zA-Z0-9]+)?((?:[.#][\w-]+)*)$/.exec(sel) || [];
    var tag = m[1] || 'div';
    var el = document.createElement(tag);
    (m[2] || '').split(/(?=[.#])/).forEach(function (t) {
      if (!t) return;
      if (t[0] === '.') el.classList.add(t.slice(1));
      else if (t[0] === '#') el.id = t.slice(1);
    });
    if (attrs && (typeof attrs !== 'object' || Array.isArray(attrs) || attrs instanceof Node)) {
      children = attrs; attrs = null;
    }
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        var v = attrs[k];
        if (v == null || v === false) return;
        if (k === 'text') { el.textContent = v; }
        else if (k === 'html') { el.innerHTML = v; }
        else if (k === 'uid') { el.setAttribute('data-uid', v); }
        else if (k === 'uidLabel') { el.setAttribute('data-uid-label', v); }
        else if (k === 'style' && typeof v === 'object') { Object.assign(el.style, v); }
        else if (k.slice(0, 2) === 'on' && typeof v === 'function') {
          el.addEventListener(k.slice(2).toLowerCase(), v);
          // 핸들러는 addEventListener 로 붙어서 DOM 에 흔적이 없습니다.
          // 그래서 "누를 수 있는데 고유번호가 없는 요소"를 아무도 못 잡았습니다.
          el.setAttribute('data-clickable', '');
        } else { el.setAttribute(k, v === true ? '' : v); }
      });
    }
    append(el, children);
    return el;
  }
  function append(el, c) {
    if (c == null || c === false) return;
    if (Array.isArray(c)) { c.forEach(function (x) { append(el, x); }); return; }
    el.appendChild(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); return el; }

  /* --- 프로필 사진 --------------------------------------------------------
   *
   * 사진이 없을 때 회색 사람 모양 아이콘을 쓰지 않습니다. 목록에서 다섯
   * 명이 똑같이 생기면 그건 사진이 없는 게 아니라 구분이 없는 겁니다.
   * 대신 이름 첫 글자를, 그 사람 id 에서 뽑은 색 위에 놓습니다 — 같은
   * 사람은 언제나 같은 색이라, 사진이 없어도 목록에서 찾아집니다.
   */
  function firstChar(name) {
    var t = String(name || '').trim();
    if (!t) return '?';
    /* 한 글자만 잘라내는데 서러게이트 페어(이모지)를 반으로 자르면
       깨진 네모가 나옵니다. Array.from 은 코드포인트 단위로 자릅니다. */
    try { return Array.from(t)[0]; } catch (e) { return t.charAt(0); }
  }
  function tintOf(seed) {
    var t = String(seed || ''), n = 0;
    for (var i = 0; i < t.length; i++) n = (n * 31 + t.charCodeAt(i)) >>> 0;
    return n % 360;
  }
  /**
   * person: { displayName, avatar, id }
   * size:   픽셀 (기본 40)
   */
  function avatar(person, size) {
    var s = size || 40;
    var p = person || {};
    var el = h('div.avatar', {
      style: { width: s + 'px', height: s + 'px',
               fontSize: Math.round(s * 0.42) + 'px' },
      'aria-hidden': 'true'
    });
    if (p.avatar) {
      el.appendChild(h('img.avatar__img', { src: p.avatar, alt: '' }));
    } else {
      var hue = tintOf(p.id || p.displayName || '');
      el.classList.add('avatar--letter');
      el.style.setProperty('--av-h', String(hue));
      el.textContent = firstChar(p.displayName);
    }
    return el;
  }

  /* --- 포맷 --------------------------------------------------------------- */
  function n1(x) { return x == null ? '—' : (Math.round(x * 10) / 10).toFixed(1); }
  function n2(x) { return x == null ? '—' : (Math.round(x * 100) / 100).toFixed(2); }
  function n0(x) { return x == null ? '—' : String(Math.round(x)); }
  function sign(x, d) {
    if (x == null) return '—';
    var v = (d === 2 ? n2(Math.abs(x)) : n1(Math.abs(x)));
    return (x > 0 ? '+' : (x < 0 ? '−' : '')) + v;
  }
  function dateK(iso) {
    if (!iso) return '—';
    var d = new Date(iso.length <= 10 ? iso + 'T00:00:00' : iso);
    return d.getFullYear() + '. ' + (d.getMonth() + 1) + '. ' + d.getDate() + '.';
  }
  function dateShort(iso) {
    if (!iso) return '—';
    var d = new Date(iso.length <= 10 ? iso + 'T00:00:00' : iso);
    return (d.getMonth() + 1) + '/' + d.getDate();
  }
  function weeksToHuman(w) {
    if (w == null) return '—';
    var m = Math.floor(w / 4.345);
    var rest = Math.round(w - m * 4.345);
    if (m <= 0) return w + '주';
    return w + '주 (약 ' + m + '개월' + (rest > 0 ? ' ' + rest + '주' : '') + ')';
  }

  /* --- 모달 --------------------------------------------------------------- */
  var openModals = [];
  /**
   * openModal({uid, title, body, actions:[{label, uid, kind, onClick, close}], onClose})
   */
  function openModal(opts) {
    var backdrop = h('div.modal-backdrop');
    var modal = h('div.modal', { uid: opts.uid, uidLabel: opts.title, role: 'dialog', 'aria-modal': 'true' });

    /* closeButton: false 면 ✕ 를 아예 안 답니다.
       한 번만 보여주는 것(복구 코드)을 실수로 닫아 잃어버리지 않게 —
       그런 화면에서는 아래 버튼이 유일한 출구여야 합니다. */
    var head = h('div.modal__head', [
      h('div', [
        h('div.modal__title', { text: opts.title }),
        opts.sub ? h('div.card__sub', { text: opts.sub }) : null
      ]),
      opts.closeButton === false ? null : h('button.btn.btn--ghost.btn--sm', {
        text: '✕', 'aria-label': '닫기',
        uid: opts.uid + '-B99', uidLabel: '닫기',
        onClick: function () { close(); }
      })
    ]);
    modal.appendChild(head);

    var body = h('div.modal__body');
    append(body, typeof opts.body === 'function' ? opts.body(close) : opts.body);
    modal.appendChild(body);

    if (opts.actions && opts.actions.length) {
      var acts = h('div.modal__actions');
      opts.actions.forEach(function (a, i) {
        acts.appendChild(h('button.btn' + (a.kind === 'primary' ? '.btn--primary'
          : (a.kind === 'danger' ? '.btn--danger' : (a.kind === 'ghost' ? '.btn--ghost' : ''))), {
          text: a.label,
          uid: a.uid || (opts.uid + '-B' + String(i + 1).padStart(2, '0')),
          uidLabel: a.label,
          disabled: a.disabled,
          onClick: function () {
            var keep = a.onClick ? a.onClick(close) : undefined;
            if (a.close !== false && keep !== true) close();
          }
        }));
      });
      modal.appendChild(acts);
    }

    backdrop.appendChild(modal);
    backdrop.addEventListener('click', function (e) {
      if (e.target === backdrop && opts.dismissable !== false) close();
    });
    function onKey(e) { if (e.key === 'Escape' && opts.dismissable !== false) close(); }
    function close() {
      document.removeEventListener('keydown', onKey);
      backdrop.remove();
      openModals = openModals.filter(function (x) { return x !== backdrop; });
      if (opts.onClose) opts.onClose();
    }
    document.addEventListener('keydown', onKey);
    document.body.appendChild(backdrop);
    openModals.push(backdrop);
    if (global.MB_UID) global.MB_UID.scan(backdrop);
    return { close: close, el: modal, body: body };
  }
  function closeAllModals() { openModals.slice().forEach(function (b) { b.remove(); }); openModals = []; }

  /**
   * 짧은 말 + 접어둔 근거.
   * 이 앱의 신뢰는 "숫자를 밝힌다"에서 나오는데, 그렇다고 화면을 논문으로
   * 채우면 아무도 안 읽습니다. 평소엔 한 줄, 궁금하면 펼치게 합니다.
   */
  function plainNote(opts) {
    var wrap = h('div.note' + (opts.tone ? '.note--' + opts.tone : ''),
      { uid: opts.uid, uidLabel: opts.label });
    if (opts.title) wrap.appendChild(h('b', { text: opts.title + ' ' }));
    if (opts.text) append(wrap, opts.text);
    if (opts.evidence) {
      var open = false;
      var body = h('div', { style: { display: 'none', marginTop: '8px', paddingTop: '8px',
        borderTop: '1px solid color-mix(in srgb, currentColor 22%, transparent)',
        fontSize: '12px', opacity: '.88' }, text: opts.evidence });
      var btn = h('button', {
        text: '근거 ▸',
        style: { background: 'none', border: 'none', padding: '4px 0 0', cursor: 'pointer',
                 font: 'inherit', fontSize: '11.5px', fontWeight: '700', opacity: '.75',
                 color: 'inherit', textDecoration: 'underline', textUnderlineOffset: '2px' },
        onClick: function () {
          open = !open;
          body.style.display = open ? '' : 'none';
          btn.textContent = open ? '근거 ▾' : '근거 ▸';
        }
      });
      wrap.appendChild(h('div', [btn]));
      wrap.appendChild(body);
    }
    return wrap;
  }

  /* --- 라인 차트 (SVG) ----------------------------------------------------- */
  /**
   * lineChart({ uid, series:[{key,label,color,points:[{x,y}],dashed}], height,
   *             markers:[{x,label}], goal:[{y,color,label}], yLabel, xLabel, xTickFmt })
   */
  function lineChart(opts) {
    var W = 320, H = opts.height || 150;
    var padL = 34, padR = 12, padT = 12, padB = 22;
    var series = (opts.series || []).filter(function (s) { return s.points && s.points.length; });
    if (!series.length) return h('div.empty', { text: '표시할 데이터가 없습니다' });

    var xs = [], ys = [];
    series.forEach(function (s) { s.points.forEach(function (p) { xs.push(p.x); ys.push(p.y); }); });
    (opts.goal || []).forEach(function (g) { ys.push(g.y); });
    var xmin = Math.min.apply(null, xs), xmax = Math.max.apply(null, xs);
    var ymin = Math.min.apply(null, ys), ymax = Math.max.apply(null, ys);
    var yPad = (ymax - ymin) * 0.15 || 1;
    ymin -= yPad; ymax += yPad;
    if (xmax === xmin) xmax = xmin + 1;

    function sx(x) { return padL + (x - xmin) / (xmax - xmin) * (W - padL - padR); }
    function sy(y) { return padT + (1 - (y - ymin) / (ymax - ymin)) * (H - padT - padB); }

    var NS = 'http://www.w3.org/2000/svg';
    function svgEl(tag, attrs) {
      var e = document.createElementNS(NS, tag);
      Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); });
      return e;
    }
    var svg = svgEl('svg', { viewBox: '0 0 ' + W + ' ' + H, width: '100%', height: H,
                             preserveAspectRatio: 'none', role: 'img' });

    // y 격자 3줄
    for (var i = 0; i <= 3; i++) {
      var yv = ymin + (ymax - ymin) * i / 3;
      svg.appendChild(svgEl('line', { x1: padL, x2: W - padR, y1: sy(yv), y2: sy(yv),
        stroke: 'currentColor', 'stroke-opacity': .10, 'stroke-width': 1 }));
      var lab = svgEl('text', { x: 4, y: sy(yv) + 3, 'font-size': 8, fill: 'currentColor', 'fill-opacity': .5 });
      lab.textContent = (Math.round(yv * 10) / 10).toFixed(1);
      svg.appendChild(lab);
    }
    // 목표선
    (opts.goal || []).forEach(function (g) {
      svg.appendChild(svgEl('line', { x1: padL, x2: W - padR, y1: sy(g.y), y2: sy(g.y),
        stroke: g.color || 'currentColor', 'stroke-width': 1.2, 'stroke-dasharray': '4 3', 'stroke-opacity': .8 }));
      if (g.label) {
        var t = svgEl('text', { x: W - padR, y: sy(g.y) - 3, 'font-size': 8, 'text-anchor': 'end',
                                fill: g.color || 'currentColor' });
        t.textContent = g.label; svg.appendChild(t);
      }
    });
    // 구간 마커 (단계 전환)
    (opts.markers || []).forEach(function (m) {
      svg.appendChild(svgEl('line', { x1: sx(m.x), x2: sx(m.x), y1: padT, y2: H - padB,
        stroke: 'currentColor', 'stroke-opacity': .18, 'stroke-width': 1, 'stroke-dasharray': '2 3' }));
      if (m.label) {
        var mt = svgEl('text', { x: sx(m.x) + 2, y: padT + 8, 'font-size': 7.5,
                                 fill: 'currentColor', 'fill-opacity': .55 });
        mt.textContent = m.label; svg.appendChild(mt);
      }
    });
    // 라인
    series.forEach(function (s) {
      var d = s.points.map(function (p, i) { return (i ? 'L' : 'M') + sx(p.x).toFixed(1) + ' ' + sy(p.y).toFixed(1); }).join(' ');
      svg.appendChild(svgEl('path', { d: d, fill: 'none', stroke: s.color || 'currentColor',
        'stroke-width': s.width || 1.8, 'stroke-linejoin': 'round', 'stroke-linecap': 'round',
        'stroke-dasharray': s.dashed ? '4 3' : null }));
      if (s.dots !== false && s.points.length <= 24) {
        s.points.forEach(function (p) {
          svg.appendChild(svgEl('circle', { cx: sx(p.x), cy: sy(p.y), r: 2.4,
            fill: s.color || 'currentColor' }));
        });
      }
      var last = s.points[s.points.length - 1];
      svg.appendChild(svgEl('circle', { cx: sx(last.x), cy: sy(last.y), r: 3.2,
        fill: s.color || 'currentColor', stroke: 'var(--surface)', 'stroke-width': 1.5 }));
    });
    // x축 라벨
    var fmt = opts.xTickFmt || function (v) { return String(Math.round(v)); };
    [xmin, (xmin + xmax) / 2, xmax].forEach(function (xv, i) {
      var t = svgEl('text', { x: sx(xv), y: H - 6, 'font-size': 8, fill: 'currentColor',
        'fill-opacity': .5, 'text-anchor': i === 0 ? 'start' : (i === 2 ? 'end' : 'middle') });
      t.textContent = fmt(xv); svg.appendChild(t);
    });

    var wrap = h('div', { uid: opts.uid, uidLabel: opts.label || '차트',
                          style: { position: 'relative', color: 'var(--text)' } }, [svg]);
    if (opts.legend !== false) {
      wrap.appendChild(h('div', { style: { display: 'flex', gap: '12px', flexWrap: 'wrap',
        fontSize: '11px', marginTop: '4px', color: 'var(--text-3)', fontWeight: '600' } },
        series.map(function (s) {
          return h('span', { style: { display: 'flex', alignItems: 'center', gap: '4px' } }, [
            h('span', { style: { width: '10px', height: '2.5px', borderRadius: '2px',
                                 background: s.color || 'currentColor', display: 'inline-block' } }),
            s.label
          ]);
        })));
    }
    return wrap;
  }

  /** 스파크라인 (작은 추이선) */
  function sparkline(values, color, height) {
    var H = height || 28, W = 80;
    if (!values || values.length < 2) return h('div', { style: { height: H + 'px' } });
    var min = Math.min.apply(null, values), max = Math.max.apply(null, values);
    if (max === min) { max = min + 1; }
    var NS = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
    svg.setAttribute('width', '100%'); svg.setAttribute('height', H);
    svg.setAttribute('preserveAspectRatio', 'none');
    var d = values.map(function (v, i) {
      var x = i / (values.length - 1) * W;
      var y = H - 3 - (v - min) / (max - min) * (H - 6);
      return (i ? 'L' : 'M') + x.toFixed(1) + ' ' + y.toFixed(1);
    }).join(' ');
    var path = document.createElementNS(NS, 'path');
    path.setAttribute('d', d); path.setAttribute('fill', 'none');
    path.setAttribute('stroke', color || 'currentColor');
    path.setAttribute('stroke-width', '1.8');
    path.setAttribute('stroke-linejoin', 'round'); path.setAttribute('stroke-linecap', 'round');
    svg.appendChild(path);
    return svg;
  }

  /**
   * 타임라인 막대 — 시작 · 오늘 · 목표일(들)을 한 줄로.
   * 날짜 두 개를 표로 나열하면 "당겨졌다/밀렸다"가 머리로 계산해야 보인다.
   * 같은 축에 찍으면 눈으로 바로 보인다.
   */
  function timeline(opts) {
    var startISO = opts.start, todayISO = opts.today;
    var marks = (opts.marks || []).filter(function (m) { return m && m.date; });
    if (!marks.length) return h('div');
    var t0 = new Date(startISO + 'T00:00:00').getTime();
    var now = new Date(todayISO + 'T00:00:00').getTime();
    var ends = marks.map(function (m) { return new Date(m.date + 'T00:00:00').getTime(); });
    var t1 = Math.max.apply(null, ends.concat([now]));
    var span = Math.max(1, t1 - t0);
    function pct(t) { return Math.max(0, Math.min(100, (t - t0) / span * 100)); }

    var W = 320, H = 46, padX = 6;
    var NS = 'http://www.w3.org/2000/svg';
    function el(tag, a) {
      var e = document.createElementNS(NS, tag);
      Object.keys(a || {}).forEach(function (k) { e.setAttribute(k, a[k]); });
      return e;
    }
    var svg = el('svg', { viewBox: '0 0 ' + W + ' ' + H, width: '100%', height: H,
                          preserveAspectRatio: 'none', role: 'img' });
    function x(p) { return padX + p / 100 * (W - padX * 2); }
    var baseY = 26;

    svg.appendChild(el('rect', { x: padX, y: baseY - 3, width: W - padX * 2, height: 6, rx: 3,
                                 fill: 'currentColor', 'fill-opacity': .10 }));
    svg.appendChild(el('rect', { x: padX, y: baseY - 3, width: Math.max(2, x(pct(now)) - padX),
                                 height: 6, rx: 3, fill: 'var(--accent)', 'fill-opacity': .55 }));

    marks.forEach(function (m) {
      var mx = x(pct(new Date(m.date + 'T00:00:00').getTime()));
      svg.appendChild(el('line', { x1: mx, x2: mx, y1: baseY - 10, y2: baseY + 10,
                                   stroke: m.color || 'currentColor', 'stroke-width': 2,
                                   'stroke-dasharray': m.dashed ? '3 2' : null }));
      var tx = el('text', { x: mx, y: m.below ? baseY + 20 : baseY - 14, 'font-size': 8.5,
                            'font-weight': 700, fill: m.color || 'currentColor',
                            'text-anchor': mx > W * 0.8 ? 'end' : (mx < W * 0.2 ? 'start' : 'middle') });
      tx.textContent = m.label;
      svg.appendChild(tx);
    });

    var todayX = x(pct(now));
    svg.appendChild(el('circle', { cx: todayX, cy: baseY, r: 4,
                                   fill: 'var(--accent)', stroke: 'var(--surface)', 'stroke-width': 2 }));
    var tl = el('text', { x: todayX, y: baseY + 20, 'font-size': 8.5, 'font-weight': 700,
                          fill: 'var(--accent)',
                          'text-anchor': todayX > W * 0.8 ? 'end' : (todayX < W * 0.2 ? 'start' : 'middle') });
    tl.textContent = '오늘';
    svg.appendChild(tl);

    return h('div', { uid: opts.uid, uidLabel: opts.label || '타임라인',
                      style: { color: 'var(--text)' } }, [svg]);
  }

  /** 도넛 진행률 */
  function donut(pct, color, size) {
    var S = size || 56, r = (S - 7) / 2, c = 2 * Math.PI * r;
    var NS = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 ' + S + ' ' + S);
    svg.setAttribute('width', S); svg.setAttribute('height', S);
    function circ(stroke, dash, op) {
      var e = document.createElementNS(NS, 'circle');
      e.setAttribute('cx', S / 2); e.setAttribute('cy', S / 2); e.setAttribute('r', r);
      e.setAttribute('fill', 'none'); e.setAttribute('stroke', stroke);
      e.setAttribute('stroke-width', 5); e.setAttribute('stroke-linecap', 'round');
      if (dash != null) { e.setAttribute('stroke-dasharray', dash + ' ' + c); }
      if (op != null) e.setAttribute('stroke-opacity', op);
      e.setAttribute('transform', 'rotate(-90 ' + S / 2 + ' ' + S / 2 + ')');
      return e;
    }
    svg.appendChild(circ('currentColor', null, .12));
    svg.appendChild(circ(color || 'var(--accent)', Math.max(0, Math.min(1, pct / 100)) * c, null));
    var t = document.createElementNS(NS, 'text');
    t.setAttribute('x', S / 2); t.setAttribute('y', S / 2 + 4);
    t.setAttribute('text-anchor', 'middle'); t.setAttribute('font-size', 13);
    t.setAttribute('font-weight', '800'); t.setAttribute('fill', 'currentColor');
    t.textContent = Math.round(pct) + '%';
    svg.appendChild(t);
    return svg;
  }

  /* --- 복사 ----------------------------------------------------------------
   *
   * "복사했습니다" 라고 해 놓고 실제로는 안 된 자리가 셋 있었습니다.
   * 제일 아픈 곳이 초대 코드입니다 — 친구를 추가하는 유일한 길인데,
   * 복사됐다고 믿고 카톡에 붙여넣으면 엉뚱한 게 갑니다.
   *
   * 언제 안 되나
   *   · http 로 열었을 때 (같은 와이파이에서 192.168.x.x 로 들어오는 경우).
   *     브라우저가 navigator.clipboard 를 아예 안 줍니다 — 실제로 확인했습니다.
   *   · 사용자가 버튼을 누른 맥락이 아닐 때, 권한을 막아 뒀을 때.
   *
   * 그래서 세 단계로 갑니다: 진짜 복사 → 옛날 방식(execCommand) →
   * 그래도 안 되면 값을 골라 주고 "직접 복사하세요" 라고 말합니다.
   * 마지막 경우에 "복사했습니다" 라고 하면 그건 거짓말입니다.
   *
   * @param {string} text  복사할 값
   * @param {object} [o]   { el: 실패 시 선택해 줄 요소, ok: 성공 문구 }
   */
  function copyText(text, o) {
    o = o || {};
    var okMsg = o.ok || '복사했습니다';
    var toast = function (m) { if (global.MB_UID && global.MB_UID.toast) global.MB_UID.toast(m); };

    function legacy() {
      try {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed'; ta.style.top = '0'; ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.focus(); ta.select();
        var done = document.execCommand && document.execCommand('copy');
        document.body.removeChild(ta);
        return !!done;
      } catch (e) { return false; }
    }

    function giveUp() {
      /* 값을 골라 줍니다 — 폰에서는 길게 눌러 복사할 수 있습니다.
         고를 것도 없으면 그냥 안 된다고 말합니다. */
      var picked = false;
      if (o.el) {
        try {
          var r = document.createRange();
          r.selectNodeContents(o.el);
          var sel = window.getSelection();
          sel.removeAllRanges(); sel.addRange(r);
          picked = true;
        } catch (e) {}
      }
      toast(picked ? '길게 눌러 복사하세요' : '복사가 안 됩니다 — 직접 옮겨 적어 주세요');
      return false;
    }

    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        return navigator.clipboard.writeText(text)
          .then(function () { toast(okMsg); return true; })
          .catch(function () { return legacy() ? (toast(okMsg), true) : giveUp(); });
      }
    } catch (e) {}
    var r2 = legacy();
    if (r2) toast(okMsg);
    else giveUp();
    return Promise.resolve(r2);
  }

  /** 지금 이 화면이 보안 컨텍스트인가 — 아니면 설치·오프라인·복사가 안 됩니다. */
  function isSecure() {
    try { return window.isSecureContext !== false; } catch (e) { return true; }
  }

  global.MB_UI = {
    h: h, clear: clear, append: append, copyText: copyText, isSecure: isSecure,
    avatar: avatar, firstChar: firstChar, tintOf: tintOf,
    n0: n0, n1: n1, n2: n2, sign: sign, dateK: dateK, dateShort: dateShort, weeksToHuman: weeksToHuman,
    openModal: openModal, closeAllModals: closeAllModals, plainNote: plainNote,
    lineChart: lineChart, sparkline: sparkline, donut: donut, timeline: timeline
  };
})(window);
