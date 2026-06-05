import 'dart:async';

import 'package:flutter/foundation.dart';

import 'monotonic_clock.dart';
import 'p2p_service.dart';

class SyncResult {
  final int offsetMs;
  final int rttMs;
  final int sampleCount;

  SyncResult({
    required this.offsetMs,
    required this.rttMs,
    required this.sampleCount,
  });
}

/// clock sync ping/pong 한 쌍. RTT + raw offset 계산.
class _SyncSample {
  final int t1; // 게스트 송신 시각
  final int t2; // 호스트 수신 시각
  final int t3; // 게스트 수신 시각

  const _SyncSample({required this.t1, required this.t2, required this.t3});

  int get rttMs => t3 - t1;
  int get rawOffsetMs => t2 - ((t1 + t3) ~/ 2);
  // v0.0.80: age limit용 sample 도착 시각. t3가 게스트 pong 수신 시각이므로 그대로 사용.
  int get arrivalMs => t3;
}

// EMA 파라미터 (v0.0.74: fast phase 제거 — carry over로 출발점 안정 + §D-2 gap 보호)
const double _emaAlpha = 0.1; // 단일 alpha (이전 _emaAlphaSlow 값 유지)
const int _windowSize = 10; // sliding window 크기 (v0.0.24: 5→10, min-RTT 표본 확장으로 outlier 영향 감소)
// v0.0.120 stable 판정 재설계 (#1 isOffsetStable jitter fix, SYNC_REDESIGN):
// 기존 "offset 값 안정성(filtered vs winMinRaw 2ms 비교)"은 RTT 노이즈(±RTT/2, RTT10이면
// ±5ms > 2ms)에 깨져 안정 상황에서도 stable이 막혔다(fallback 지배). → "RTT가 충분히
// 작은(≤_stableGoodRttMs) 샘플이 _stableTimeoutMs 내 들어왔는가"로 전환. offset 정확도는
// EMA filtered가 담당(역할 분리). 혼잡(RTT 큼) 시 good 샘플이 안 와 자연히 unstable → fallback.
const int _stableGoodRttMs = 20;   // 이 이하 RTT = 정밀 anchor 박을 만한 샘플
const int _stableTimeoutMs = 5000; // 마지막 good 샘플 후 이 시간 지나면 unstable

// v0.0.74: 초기 핸드셰이크 early termination 조건
// (single raw RTT ≤ _earlyTermRttThresholdMs) sample이 _earlyTermSampleCount개 모이면 즉시 종료.
// 못 모으면 30개 cap fallback. v0.0.80: 임계 10→20 완화 (jitter 환경에서도 early term 도달).
const int _earlyTermRttThresholdMs = 20;
const int _earlyTermSampleCount = 10;

// v0.0.80: periodic sync outlier rejection.
// raw RTT > _rejectThresholdMs sample은 window 추가 안 함. 이유: RTT 클수록 ping/pong
// 비대칭 노이즈도 비례 증가 → rawOffset 부정확. 30ms 기준 = RTT/2 노이즈 최대 ±15ms
// (청감 임계 ±20ms 안전 영역).
const int _rejectThresholdMs = 30;
// window 안 sample 60초 지나면 expire. stale offset 박힘 차단.
const int _sampleAgeLimitMs = 60000;

class SyncService {
  final P2PService _p2p;

  /// 호스트 시간과의 offset (밀리초). localTime + offset = hostTime
  int _offsetMs = 0;
  int _bestRtt = 999999;
  bool _synced = false;

  /// EMA 필터링된 offset (double 정밀도, v3 drift 계산용)
  double _filteredOffsetMs = 0.0;

  /// v0.0.56 진단: 가장 최근 sample의 raw offset (EMA 적용 전, single ping/pong)
  double _lastRawOffsetMs = 0.0;
  /// v0.0.56 진단: window 내 min-RTT sample의 raw offset (EMA 입력값)
  double _winMinRawOffsetMs = 0.0;
  int _lastRttMs = 0;
  int _winMinRttMs = 0;

  /// 호출별 고유 sync request id: periodic/manual 동시 호출 시 pong 매칭
  int _syncRequestSeq = 0;

  int get offsetMs => _offsetMs;
  int get bestRtt => _bestRtt;
  bool get isSynced => _synced;

  /// EMA 필터링된 offset (double). drift 계산에서 이 값을 사용.
  double get filteredOffsetMs => _filteredOffsetMs;

  /// v0.0.56 진단 getter — anchor_reset_offset_drift root cause 분해용.
  /// raw_offset_ms 단일 sample 변동성과 EMA lag 직접 추적.
  double get lastRawOffsetMs => _lastRawOffsetMs;
  double get winMinRawOffsetMs => _winMinRawOffsetMs;
  int get lastRttMs => _lastRttMs;
  int get winMinRttMs => _winMinRttMs;

  StreamSubscription? _messageSub;
  Timer? _periodicSyncTimer;

  /// 진행 중인 syncWithHost 호출의 로컬 listener (경합 방지)
  StreamSubscription? _activeSyncSub;

  /// 주기 단계 sliding window (최근 _windowSize개)
  final List<_SyncSample> _recentWindow = [];

  /// 주기 단계 pong 수신 listener
  StreamSubscription? _periodicPongSub;

  /// 주기 단계에서 보낸 ping의 t1 보관 (pong 매칭용)
  final Map<int, int> _pendingPingT1 = {};

  /// offset 안정성 추적 (v0.0.120 재설계): RTT가 충분히 작은(≤_stableGoodRttMs) 샘플을
  /// 마지막으로 받은 monotonic 시각. _stableTimeoutMs 내 그런 샘플이 있으면 stable.
  /// 기존 _stableCount(winMinRaw 2ms 비교)를 대체 — #1 root(RTT 노이즈에 깨짐) 제거.
  int _lastGoodSampleMs = 0;

  /// isOffsetStable 토글 추적 (logging용)
  bool _prevIsStable = false;

  /// offset이 안정화되었는지 여부. drift 보정/anchor는 이 값이 true일 때만 활성화.
  /// v0.0.120 재설계: "RTT 작은 샘플이 최근 _stableTimeoutMs 내 들어왔는가". offset
  /// 값 정확도는 EMA filtered가 담당(역할 분리) → window 크기 가드 불필요(초기 (c)
  /// stable이 carry over 1개로도 성립해야 하므로 제거). 혼잡 시 false → fallback.
  bool get isOffsetStable =>
      _lastGoodSampleMs > 0 &&
      MonotonicClock.nowMs() - _lastGoodSampleMs <= _stableTimeoutMs;

  SyncService(this._p2p);

  /// 상태 초기화 (방 나가기 시 호출)
  void reset() {
    _offsetMs = 0;
    _filteredOffsetMs = 0.0;
    _lastRawOffsetMs = 0.0;
    _winMinRawOffsetMs = 0.0;
    _lastRttMs = 0;
    _winMinRttMs = 0;
    _bestRtt = 999999;
    _synced = false;
    _messageSub?.cancel();
    _messageSub = null;
    _activeSyncSub?.cancel();
    _activeSyncSub = null;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _periodicPongSub?.cancel();
    _periodicPongSub = null;
    _recentWindow.clear();
    _pendingPingT1.clear();
    _lastGoodSampleMs = 0;
  }

  /// 참가자: 호스트와 시간 동기화 시작
  /// ping을 [count]회 보내서 가장 RTT가 작은 샘플로 offset 확정
  Future<SyncResult> syncWithHost({int count = 30}) async {
    // 이전 진행 중인 sync가 있으면 취소
    _activeSyncSub?.cancel();
    _activeSyncSub = null;

    // 이번 호출의 고유 id (pong 필터링용)
    final requestId = ++_syncRequestSeq;

    final completer = Completer<SyncResult>();
    int completed = 0;

    // 매 라운드마다 리셋 (클럭 드리프트 보정을 위해)
    int roundBestRtt = 999999;
    int roundOffset = _offsetMs;
    // v0.0.74: best sample 추적 (carry over용 — 종료 시 _recentWindow 맨 뒤에 추가)
    _SyncSample? bestSample;
    // v0.0.74: early termination — 임계 이하 RTT sample 카운터
    int rttUnderThresholdCount = 0;

    // 로컬 변수로 listener를 관리하여 다른 호출과의 경합 방지
    late final StreamSubscription sub;
    sub = _p2p.onMessage.listen((message) {
      if (message['type'] != 'sync-pong') return;
      // requestId 불일치 (다른 호출의 pong 또는 stale) → 무시
      final pongRid = message['data']?['rid'] as int?;
      if (pongRid != requestId) return;

      final t1 = message['data']['t1'] as int;
      final hostTime = message['data']['hostTime'] as int;
      final t3 = MonotonicClock.nowMs();

      final sample = _SyncSample(t1: t1, t2: hostTime, t3: t3);
      final rtt = sample.rttMs;
      final offset = sample.rawOffsetMs;

      if (rtt < roundBestRtt) {
        roundBestRtt = rtt;
        roundOffset = offset;
        bestSample = sample;
      }

      // v0.0.74 early termination 카운트
      if (rtt <= _earlyTermRttThresholdMs) {
        rttUnderThresholdCount++;
      }

      completed++;
      // 종료 조건: (a) 임계 이하 sample N개 모임 OR (b) count 다 받음
      final shouldComplete = (rttUnderThresholdCount >= _earlyTermSampleCount) ||
          (completed >= count);
      if (shouldComplete && !completer.isCompleted) {
        _offsetMs = roundOffset;
        _bestRtt = roundBestRtt;
        _filteredOffsetMs = roundOffset.toDouble();
        // v0.0.120 (c) 조항: 초기 동기화에서 RTT≤_stableGoodRttMs 샘플이 있었으면
        // (roundBestRtt) 즉시 stable — anchor를 시작 직후 박을 수 있게(시작 공백 제거).
        if (roundBestRtt <= _stableGoodRttMs) {
          _lastGoodSampleMs = MonotonicClock.nowMs();
        }
        _synced = true;
        // v0.0.74 B: best 1개를 _recentWindow 맨 뒤에 carry over.
        // sliding window는 인덱스 0(가장 앞)에서 빠지므로 맨 뒤에 박으면 9개 새 sample이
        // 들어올 때까지 안 빠짐 → 9초 동안 minSample 안전망 보장.
        // startPeriodicSync 진입 시 _recentWindow.clear() 안 하므로 보존됨.
        if (bestSample != null) {
          _recentWindow.add(bestSample!);
          // window 사이즈 초과 가드 (이전 _recentWindow 남아있을 가능성 대비)
          while (_recentWindow.length > _windowSize) {
            _recentWindow.removeAt(0);
          }
        }
        sub.cancel();
        if (_activeSyncSub == sub) _activeSyncSub = null;
        completer.complete(SyncResult(
          offsetMs: _offsetMs,
          rttMs: _bestRtt,
          sampleCount: completed,
        ));
      }
    });
    _activeSyncSub = sub;

    // ping을 간격을 두고 전송
    for (int i = 0; i < count; i++) {
      // 이 sync가 취소되었으면 중단
      if (_activeSyncSub != sub) break;
      _p2p.sendToHost({
        'type': 'sync-ping',
        'data': {
          't1': MonotonicClock.nowMs(),
          'rid': requestId,
        },
      });
      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        sub.cancel();
        if (_activeSyncSub == sub) _activeSyncSub = null;
        if (completed > 0) {
          _offsetMs = roundOffset;
          _bestRtt = roundBestRtt;
          _filteredOffsetMs = roundOffset.toDouble();
          // v0.0.120 (c): timeout 케이스도 RTT≤_stableGoodRttMs 샘플 있었으면 즉시 stable
          if (roundBestRtt <= _stableGoodRttMs) {
            _lastGoodSampleMs = MonotonicClock.nowMs();
          }
          _synced = true;
          // v0.0.74 B: timeout 케이스도 best 1개 carry over (부분 sample 받았으면)
          if (bestSample != null) {
            _recentWindow.add(bestSample!);
            while (_recentWindow.length > _windowSize) {
              _recentWindow.removeAt(0);
            }
          }
          return SyncResult(
            offsetMs: _offsetMs,
            rttMs: _bestRtt,
            sampleCount: completed,
          );
        }
        throw TimeoutException('시간 동기화 실패: 응답 없음');
      },
    );
  }

  /// 참가자: 1초 주기 EMA 동기화 시작.
  /// 매 1초 단일 ping → pong 수신 시 sliding window에 추가 →
  /// window 내 min-RTT 샘플의 offset을 EMA로 기존 filtered와 혼합.
  ///
  /// v0.0.74: fast phase 제거. carry over로 출발점 안정 + §D-2 gap 보호 전제.
  /// _recentWindow는 syncWithHost가 best 1개를 carry over했으므로 clear 안 함.
  void startPeriodicSync() {
    // v0.0.115 검증: FFI monotonic 동작 + 도메인 확인. isNative=false면 wall fallback
    // (도메인 섞임 위험). boot(부팅후 경과, 작은 값) vs wall(epoch, 큰 값) 확연히 다르면 정상.
    debugPrint('[MONOTONIC] guest isNative=${MonotonicClock.isNative} '
        'boot=${MonotonicClock.nowMs()} wall=${DateTime.now().millisecondsSinceEpoch}');
    _periodicSyncTimer?.cancel();
    _periodicPongSub?.cancel();
    // v0.0.74 B: _recentWindow.clear() 제거 — syncWithHost가 best 1개 carry over함.
    _pendingPingT1.clear();

    // pong 수신 listener
    _periodicPongSub = _p2p.onMessage.listen((message) {
      if (message['type'] != 'sync-pong') return;
      // rid 필터: 주기 단계 ping은 rid를 음수(-)로 사용하여 초기 핸드셰이크와 구분
      final pongRid = message['data']?['rid'] as int?;
      if (pongRid == null || pongRid >= 0) return; // 초기 핸드셰이크 pong은 무시

      final t1 = _pendingPingT1.remove(pongRid);
      if (t1 == null) return; // orphan
      final t2 = message['data']['hostTime'] as int;
      final t3 = MonotonicClock.nowMs();

      final sample = _SyncSample(t1: t1, t2: t2, t3: t3);

      // v0.0.80: outlier rejection — raw RTT 30ms 초과면 폐기.
      // 비대칭 노이즈 비례 증가로 rawOffset 부정확. window/EMA/stable 모두 변화 0.
      if (sample.rttMs > _rejectThresholdMs) {
        debugPrint('Raw sample REJECTED: rttMs=${sample.rttMs}, rawOffset=${sample.rawOffsetMs.toStringAsFixed(1)}');
        return;
      }

      // sliding window 관리
      _recentWindow.add(sample);
      if (_recentWindow.length > _windowSize) {
        _recentWindow.removeAt(0);
      }

      // v0.0.80: age limit — 60초 지난 sample 제거. stale offset 박힘 차단.
      // 방금 추가한 sample은 t3=nowMs라 expire 안 됨. 다만 안전상 isEmpty 가드.
      final nowMs = MonotonicClock.nowMs();
      _recentWindow.removeWhere((s) => nowMs - s.arrivalMs > _sampleAgeLimitMs);
      if (_recentWindow.isEmpty) {
        debugPrint('Raw sample: rttMs=${sample.rttMs}, rawOffset=${sample.rawOffsetMs.toStringAsFixed(1)} (window empty after age limit, filtered frozen)');
        return;
      }

      // window 내 min-RTT 샘플의 offset을 EMA로 혼합
      final minSample =
          _recentWindow.reduce((a, b) => a.rttMs < b.rttMs ? a : b);

      // v0.0.56 진단: raw 값 노출 (EMA lag/outlier 분해용)
      _lastRawOffsetMs = sample.rawOffsetMs.toDouble();
      _winMinRawOffsetMs = minSample.rawOffsetMs.toDouble();
      _lastRttMs = sample.rttMs;
      _winMinRttMs = minSample.rttMs;

      // v0.0.74: fast phase 제거 — 단일 alpha (0.1) 즉시 적용.
      // carry over로 _filteredOffsetMs와 minSample이 이미 진짜 offset에 가까운 상태에서 시작.
      _filteredOffsetMs = _filteredOffsetMs * (1 - _emaAlpha) +
          minSample.rawOffsetMs * _emaAlpha;
      _offsetMs = _filteredOffsetMs.round();
      _bestRtt = minSample.rttMs;

      // v0.0.120 stable 재설계 (#1 fix): RTT가 충분히 작으면(정밀 anchor 가능) good
      // 샘플 시각 갱신. isOffsetStable getter가 이 시각 기준 _stableTimeoutMs 윈도우로 판정.
      // (sample은 reject(>30) 통과분 → RTT≤_stableGoodRttMs면 노이즈 ±RTT/2 작아 신뢰.)
      // 기존 winMinRaw 2ms 비교는 RTT 노이즈에 깨져 안정 상황도 unstable 만들던 root였음.
      if (sample.rttMs <= _stableGoodRttMs) {
        _lastGoodSampleMs = MonotonicClock.nowMs();
      }

      debugPrint('Raw sample: rttMs=${sample.rttMs}, rawOffset=${sample.rawOffsetMs.toStringAsFixed(1)}');
      debugPrint('Periodic sync: offset=${_filteredOffsetMs.toStringAsFixed(1)}ms, '
          'RTT=${minSample.rttMs}ms, window=${_recentWindow.length}, '
          'stable=$isOffsetStable');

      // v0.0.80: isOffsetStable 토글 시점 명시
      final isStableNow = isOffsetStable;
      if (isStableNow != _prevIsStable) {
        debugPrint('[STABLE TOGGLE] $_prevIsStable → $isStableNow '
            '(window=${_recentWindow.length})');
        _prevIsStable = isStableNow;
      }
    });

    // 1초 주기 ping
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final rid = --_syncRequestSeq; // 음수 rid로 주기 단계 구분
      final t1 = MonotonicClock.nowMs();
      _pendingPingT1[rid] = t1;
      _p2p.sendToHost({
        'type': 'sync-ping',
        'data': {
          't1': t1,
          'rid': rid,
        },
      });
      // stale ping 정리 (5초 이상 된 것)
      _pendingPingT1.removeWhere((_, sentT1) => t1 - sentT1 > 5000);
    });
  }

  /// 참가자: 주기적 재동기화 중지
  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _periodicPongSub?.cancel();
    _periodicPongSub = null;
    _recentWindow.clear();
    _pendingPingT1.clear();
  }

  /// 호스트: sync-ping 메시지를 처리하여 pong 응답
  void startHostHandler() {
    debugPrint('[MONOTONIC] host isNative=${MonotonicClock.isNative} '
        'boot=${MonotonicClock.nowMs()} wall=${DateTime.now().millisecondsSinceEpoch}');
    _synced = true; // 호스트는 기준 시간이므로 항상 synced
    _offsetMs = 0;
    _filteredOffsetMs = 0.0;

    _messageSub?.cancel();
    _messageSub = _p2p.onMessage.listen((message) {
      if (message['type'] == 'sync-ping') {
        final t1 = message['data']['t1'] as int;
        final rid = message['data']['rid']; // null이면 그대로 전달
        final fromId = message['_from'] as String?;
        if (fromId != null) {
          _p2p.sendToPeer(fromId, {
            'type': 'sync-pong',
            'data': {
              't1': t1,
              'rid': rid,
              'hostTime': MonotonicClock.nowMs(),
            },
          });
        }
      }
    });
  }

  void dispose() {
    _messageSub?.cancel();
    _messageSub = null;
    _activeSyncSub?.cancel();
    _activeSyncSub = null;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _periodicPongSub?.cancel();
    _periodicPongSub = null;
  }
}
