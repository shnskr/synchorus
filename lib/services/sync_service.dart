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

class SyncService {
  final P2PService _p2p;

  /// 호스트 시간과의 offset (밀리초). localTime + offset = hostTime
  int _offsetMs = 0;
  int _bestRtt = 999999;
  bool _synced = false;

  /// 호출별 고유 sync request id (#12): periodic/manual 동시 호출 시 pong 매칭
  int _syncRequestSeq = 0;

  int get offsetMs => _offsetMs;
  int get bestRtt => _bestRtt;
  bool get isSynced => _synced;

  StreamSubscription? _messageSub;
  Timer? _periodicSyncTimer;

  /// 진행 중인 syncWithHost 호출의 로컬 listener (경합 방지)
  StreamSubscription? _activeSyncSub;

  SyncService(this._p2p);

  /// 상태 초기화 (방 나가기 시 호출)
  void reset() {
    _offsetMs = 0;
    _bestRtt = 999999;
    _synced = false;
    _messageSub?.cancel();
    _messageSub = null;
    _activeSyncSub?.cancel();
    _activeSyncSub = null;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  /// 참가자: 호스트와 시간 동기화 시작
  /// ping을 [count]회 보내서 가장 RTT가 작은 샘플로 offset 확정
  Future<SyncResult> syncWithHost({int count = 10}) async {
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

  /// 참가자: 백그라운드 주기적 재동기화 시작
  void startPeriodicSync({Duration interval = const Duration(seconds: 30)}) {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(interval, (_) async {
      try {
        final result = await syncWithHost();
        debugPrint('Periodic sync: offset=${result.offsetMs}ms, RTT=${result.rttMs}ms');
      } catch (e) {
        debugPrint('Periodic sync failed: $e');
      }
    });
  }

  /// 참가자: 주기적 재동기화 중지
  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  /// 호스트: sync-ping 메시지를 처리하여 pong 응답
  void startHostHandler() {
    _synced = true; // 호스트는 기준 시간이므로 항상 synced
    _offsetMs = 0;

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
  }
}
