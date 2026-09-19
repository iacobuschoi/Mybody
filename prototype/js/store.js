/* =============================================================================
 * store.js — localStorage 상태 저장소 (프로토타입용, 전부 로컬)
 * 서버 없음. 건강 데이터는 이 기기 밖으로 나가지 않는다.
 * ========================================================================== */
(function (global) {
  'use strict';
  var KEY = 'mybody.state.v1';
  var VERSION = 1;

  function blank() {
    return {
      version: VERSION,
      profile: null,
      scans: [],
      goal: null,
      comparison: null,
      plan: null,
      checkins: [],
      settings: { theme: 'auto', units: 'metric', checkinEveryWeeks: 1, defaultLevel: 'mid' },
      onboarded: false,
      disclaimerAccepted: false
    };
  }

  var state = blank();
  var listeners = [];

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        if (parsed && parsed.version === VERSION) state = Object.assign(blank(), parsed);
      }
    } catch (e) { /* 손상 시 초기 상태 */ }
    return state;
  }

  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {}
    listeners.forEach(function (f) { try { f(state); } catch (e) {} });
  }

  function get() { return state; }
  function set(patch) { Object.assign(state, patch); save(); return state; }
  function onChange(fn) { listeners.push(fn); }

  function reset() { state = blank(); save(); }

  /** 오너의 실제 인바디 데이터로 채운다 (프로토타입 검증용 한 방 버튼) */
  function seed() {
    var D = global.MB_DATA;
    state = blank();
    state.profile = JSON.parse(JSON.stringify(D.SEED_PROFILE));
    state.scans = JSON.parse(JSON.stringify(D.SEED_SCANS));
    state.onboarded = true;
    state.disclaimerAccepted = true;
    save();
    return state;
  }

  function latestScan() {
    if (!state.scans.length) return null;
    return state.scans.slice().sort(function (a, b) {
      return new Date(b.measuredAt) - new Date(a.measuredAt);
    })[0];
  }
  function sortedScans() {
    return state.scans.slice().sort(function (a, b) {
      return new Date(a.measuredAt) - new Date(b.measuredAt);
    });
  }
  function addScan(scan) {
    var i = state.scans.findIndex(function (s) { return s.id === scan.id; });
    if (i >= 0) state.scans[i] = scan; else state.scans.push(scan);
    save();
  }
  function removeScan(id) {
    state.scans = state.scans.filter(function (s) { return s.id !== id; });
    save();
  }
  function scanById(id) { return state.scans.find(function (s) { return s.id === id; }) || null; }

  function exportJSON() { return JSON.stringify(state, null, 2); }
  function importJSON(text) {
    var parsed = JSON.parse(text);
    if (!parsed || parsed.version !== VERSION) throw new Error('버전이 맞지 않는 데이터입니다');
    state = Object.assign(blank(), parsed);
    save();
  }

  global.MB_STORE = {
    load: load, save: save, get: get, set: set, reset: reset, seed: seed,
    onChange: onChange, latestScan: latestScan, sortedScans: sortedScans,
    addScan: addScan, removeScan: removeScan, scanById: scanById,
    exportJSON: exportJSON, importJSON: importJSON, blank: blank
  };
})(window);
