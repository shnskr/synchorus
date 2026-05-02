import 'dart:async';

import 'package:flutter/foundation.dart';

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
}

// EMA 파라미터 (PoC Phase 3 검증 완료, 초기 수렴 가속 추가)
const double _emaAlphaFast = 0.5; // 초기 수렴용 (처음 10 샘플)
const double _emaAlphaSlow = 0.1; // 안정 후 (new 0.1)
const int _fastPhaseCount = 10; // 빠른 수렴 샘플 수
const int _windowSize = 10; // sliding window 크기 (v0.0.24: 5→10, min-RTT 표본 확장으로 outlier 영향 감소)
const double _stableThresholdMs = 2.0; // offset 안정 판정 기준 (ms)
const int _stableRequiredCount = 5; // 연속 안정 횟수

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

  /// 주기 단계 EMA 업데이트 횟수 (빠른/느린 alpha 전환용)
  int _periodicSampleCount = 0;

  /// offset 안정성 추적
  double _prevFilteredOffset = 0.0;
  int _stableCount = 0;

  /// offset이 안정화되었는지 여부. drift 보정은 이 값이 true일 때만 활성화.
  bool get isOffsetStable => _stableCount >= _stableRequiredCount;

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
    _periodicSampleCount = 0;
    _prevFilteredOffset = 0.0;
    _stableCount = 0;
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

    // 로컬 변수로 listener를 관리하여 다른 호출과의 경합 방지
    late final StreamSubscription sub;
    sub = _p2p.onMessage.listen((message) {
      if (message['type'] != 'sync-pong') return;
      // requestId 불일치 (다른 호출의 pong 또는 stale) → 무시
      final pongRid = message['data']?['rid'] as int?;
      if (pongRid != requestId) return;

      final t1 = message['data']['t1'] as int;
      final hostTime = message['data']['hostTime'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      final rtt = now - t1;
      final offset = hostTime - (t1 + rtt ~/ 2);

      if (rtt < roundBestRtt) {
        roundBestRtt = rtt;
        roundOffset = offset;
      }

      completed++;
      if (completed >= count && !completer.isCompleted) {
        _offsetMs = roundOffset;
        _bestRtt = roundBestRtt;
        _filteredOffsetMs = roundOffset.toDouble();
        _synced = true;
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
          't1': DateTime.now().millisecondsSinceEpoch,
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
          _synced = true;
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
  void startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicPongSub?.cancel();
    _recentWindow.clear();
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
      final t3 = DateTime.now().millisecondsSinceEpoch;

      final sample = _SyncSample(t1: t1, t2: t2, t3: t3);

      // sliding window 관리
      _recentWindow.add(sample);
      if (_recentWindow.length > _windowSize) {
        _recentWindow.removeAt(0);
      }

      // window 내 min-RTT 샘플의 offset을 EMA로 혼합
      final minSample =
          _recentWindow.reduce((a, b) => a.rttMs < b.rttMs ? a : b);

      // v0.0.56 진단: raw 값 노출 (EMA lag/outlier 분해용)
      _lastRawOffsetMs = sample.rawOffsetMs.toDouble();
      _winMinRawOffsetMs = minSample.rawOffsetMs.toDouble();
      _lastRttMs = sample.rttMs;
      _winMinRttMs = minSample.rttMs;

      // 초기 10샘플은 alpha=0.3 (빠른 수렴), 이후 0.1 (안정 유지)
      _periodicSampleCount++;
      final alpha = _periodicSampleCount <= _fastPhaseCount
          ? _emaAlphaFast
          : _emaAlphaSlow;
      _filteredOffsetMs = _filteredOffsetMs * (1 - alpha) +
          minSample.rawOffsetMs * alpha;
      _offsetMs = _filteredOffsetMs.round();
      _bestRtt = minSample.rttMs;

      // offset 안정성 추적 — fast phase 동안은 수렴 중이므로 카운트 안 함
      // v0.0.63 §D-2 fix: AND 조합. step 변화량(EMA 진동 작음) + winMinRaw 일치
      // (EMA가 진짜 값에 가까움) 둘 다 만족해야 stable. (60) 진단으로
      // step 단독은 EMA convergence lag 시 false positive 발생 확정.
      final delta = (_filteredOffsetMs - _prevFilteredOffset).abs();
      _prevFilteredOffset = _filteredOffsetMs;
      if (_periodicSampleCount <= _fastPhaseCount) {
        _stableCount = 0; // fast convergence 중에는 안정 판정 금지
      } else if (delta < _stableThresholdMs &&
          (_filteredOffsetMs - _winMinRawOffsetMs).abs() < _stableThresholdMs) {
        _stableCount++;
      } else {
        _stableCount = 0;
      }

      debugPrint('Periodic sync: offset=${_filteredOffsetMs.toStringAsFixed(1)}ms, '
          'RTT=${minSample.rttMs}ms, window=${_recentWindow.length}, '
          'stable=$_stableCount, alpha=${alpha.toStringAsFixed(1)}');
    });

    // 1초 주기 ping
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final rid = --_syncRequestSeq; // 음수 rid로 주기 단계 구분
      final t1 = DateTime.now().millisecondsSinceEpoch;
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
              'hostTime': DateTime.now().millisecondsSinceEpoch,
            },
          });
        }
      }
    });
  }

  /// 호스트 시간을 로컬 시간으로 변환
  int hostTimeToLocal(int hostTimeMs) {
    return hostTimeMs - _offsetMs;
  }

  /// 로컬 시간을 호스트 시간으로 변환
  int localTimeToHost(int localTimeMs) {
    return localTimeMs + _offsetMs;
  }

  /// 동기화된 "지금" 시간 (호스트 기준)
  int get nowAsHostTime {
    return DateTime.now().millisecondsSinceEpoch + _offsetMs;
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
