import 'dart:async';

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

  int get offsetMs => _offsetMs;
  bool get isSynced => _synced;

  StreamSubscription? _messageSub;

  SyncService(this._p2p);

  /// 참가자: 호스트와 시간 동기화 시작
  /// ping을 [count]회 보내서 가장 RTT가 작은 샘플로 offset 확정
  Future<SyncResult> syncWithHost({int count = 7}) async {
    final completer = Completer<SyncResult>();
    int completed = 0;

    _messageSub?.cancel();
    _messageSub = _p2p.onMessage.listen((message) {
      if (message['type'] == 'sync-pong') {
        final t1 = message['data']['t1'] as int;
        final hostTime = message['data']['hostTime'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;

        final rtt = now - t1;
        final offset = hostTime - (t1 + rtt ~/ 2);

        if (rtt < _bestRtt) {
          _bestRtt = rtt;
          _offsetMs = offset;
        }

        completed++;
        if (completed >= count) {
          _synced = true;
          _messageSub?.cancel();
          _messageSub = null;
          completer.complete(SyncResult(
            offsetMs: _offsetMs,
            rttMs: _bestRtt,
            sampleCount: completed,
          ));
        }
      }
    });

    // ping을 간격을 두고 전송
    for (int i = 0; i < count; i++) {
      _p2p.sendToHost({
        'type': 'sync-ping',
        'data': {'t1': DateTime.now().millisecondsSinceEpoch},
      });
      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _messageSub?.cancel();
        _messageSub = null;
        if (completed > 0) {
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

  /// 호스트: sync-ping 메시지를 처리하여 pong 응답
  void startHostHandler() {
    _synced = true; // 호스트는 기준 시간이므로 항상 synced
    _offsetMs = 0;

    _messageSub?.cancel();
    _messageSub = _p2p.onMessage.listen((message) {
      if (message['type'] == 'sync-ping') {
        final t1 = message['data']['t1'] as int;
        final fromId = message['_from'] as String?;
        if (fromId != null) {
          _p2p.sendToPeer(fromId, {
            'type': 'sync-pong',
            'data': {
              't1': t1,
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
  }
}