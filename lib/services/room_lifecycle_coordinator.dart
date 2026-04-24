import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'p2p_service.dart';

/// Room 화면의 **라이프사이클·연결 복구** 로직을 한곳에 모은 코디네이터.
///
/// `room_screen.dart`에 흩어져 있던 다음 책임을 흡수한다:
/// - 호스트: `AppLifecycleState` (paused/resumed/detached) → host-paused/resumed/closed broadcast + heartbeat pause/resume
/// - 게스트: 호스트 라이프사이클 메시지(`host-paused`/`resumed`/`closed`) 수신 처리
/// - 게스트: TCP 끊김 → 분기 (호스트 종료 / hostAway watchdog / 일반 reconnect)
/// - 게스트: WiFi 끊김 → `_waitForWifiAndReconnect`
/// - 호스트: WiFi 끊김 → leave 요청
/// - away reconnect watchdog (errno=111 빠른 포기, errno=113/101 분기 포함)
///
/// UI(`room_screen`)는 상태 두 개(`hostAway`, `hostClosed`)를 구독하고, 액션
/// (`onLeaveRequested`, `onReconnectSyncRequested`)과 UX(`onLog`, `onSnackbar`)
/// 콜백만 처리하면 된다.
///
/// **역할 × 라이프사이클 매트릭스** (`docs/LIFECYCLE.md` 참조):
/// |             | paused                  | resumed                | detached         | TCP 끊김                | WiFi 끊김           |
/// |-------------|-------------------------|------------------------|------------------|-------------------------|---------------------|
/// | 호스트      | host-paused + pauseHB   | host-resumed + resumeHB| host-closed BE   | (게스트 측 처리)         | leave 요청          |
/// | 게스트      | (메시지 수신만)          | (메시지 수신만)         | (해당 없음)       | reconnect/awayLoop 분기 | waitForWifi 복구    |
class RoomLifecycleCoordinator {
  final P2PService p2p;
  final bool isHost;

  /// "방에서 나가야 함" 신호. UI는 cleanup + Navigator.pop 처리.
  final void Function() onLeaveRequested;

  /// "재접속 성공 → 재동기화 필요" 신호. UI는 sync.reset() + 동기화 재시작.
  final Future<void> Function() onReconnectSyncRequested;

  /// 로그 한 줄 추가.
  final void Function(String) onLog;

  /// 사용자 알림 (SnackBar 등).
  final void Function(String) onSnackbar;

  /// 게스트 측 호스트 자리비움 상태. UI는 ValueListenableBuilder로 배너 표시.
  final ValueNotifier<bool> hostAway = ValueNotifier(false);

  /// 호스트가 방을 종료한 상태. UI는 leave 흐름에서 closeRoom vs disconnect 분기에 사용.
  final ValueNotifier<bool> hostClosed = ValueNotifier(false);

  bool _leaving = false;
  bool _disposed = false;

  /// 두 재연결 경로(`_handleDisconnected` + `_waitForWifiAndReconnect`) 직렬화.
  /// WiFi off/on 시 connectivity 이벤트와 TCP onDone이 거의 동시에 도착 → 두 경로가
  /// 각자 `reconnectToHost` + `onReconnectSyncRequested` 호출 → 재동기화 중복으로
  /// 하나는 실패 보고. 먼저 진입한 경로가 끝날 때까지 다른 경로는 skip.
  bool _reconnectInProgress = false;

  Timer? _awayReconnectTimer;
  bool _awayReconnecting = false;
  int _awayReconnectAttempts = 0;
  int _consecutiveRefused = 0;

  /// 약 60초 (5초 주기 × 12). errno 기반 빠른 포기 분기가 먼저 종료시킬 수 있음.
  static const int _awayReconnectMaxAttempts = 12;

  /// `ECONNREFUSED` errno 연속 N회 시 watchdog 안 기다리고 즉시 포기.
  static const int _refusedFastGiveupThreshold = 2;

  /// `ECONNREFUSED` 의 POSIX errno. Linux=111, Darwin(iOS/macOS)=61.
  /// 호스트 프로세스 종료 거의 확정 신호.
  static const Set<int> _refusedErrnos = {111, 61};

  /// `EHOSTUNREACH`(경로 없음) / `ENETUNREACH`(네트워크 사용 불가) POSIX errno.
  /// Linux=113/101, Darwin=65/51. 내 WiFi 끊김 또는 호스트가 다른 AP로 이동한 경우.
  static const Set<int> _networkUnreachableErrnos = {113, 101, 65, 51};

  StreamSubscription? _disconnectSub;
  StreamSubscription? _connectivitySub;
  StreamSubscription? _messageSub;

  RoomLifecycleCoordinator({
    required this.p2p,
    required this.isHost,
    required this.onLeaveRequested,
    required this.onReconnectSyncRequested,
    required this.onLog,
    required this.onSnackbar,
  });

  /// 구독 시작. `room_screen.initState`에서 1회 호출.
  void start() {
    if (!isHost) {
      _disconnectSub = p2p.onDisconnected.listen((_) => _handleDisconnected());
      _messageSub = p2p.onMessage.listen(_handleMessage);
    }
    _connectivitySub = Connectivity().onConnectivityChanged.listen(_handleConnectivity);
  }

  /// 호스트 측 `WidgetsBindingObserver.didChangeAppLifecycleState`에서 위임.
  /// 게스트는 메시지 기반 처리이므로 호출해도 무시됨.
  void handleAppLifecycleState(AppLifecycleState state) {
    debugPrint('[LIFECYCLE] state=$state isHost=$isHost leaving=$_leaving closed=${hostClosed.value}');
    if (!isHost) return;
    if (_leaving || hostClosed.value) return;
    if (state == AppLifecycleState.paused) {
      debugPrint('[LIFECYCLE] HOST paused → pauseHeartbeat + broadcast host-paused');
      onLog('[라이프사이클] paused — heartbeat 정지 + host-paused broadcast');
      p2p.pauseHeartbeat();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[LIFECYCLE] HOST resumed → broadcast host-resumed + resumeHeartbeat');
      onLog('[라이프사이클] resumed — host-resumed broadcast + heartbeat 재개');
      p2p.resumeHeartbeat();
    } else if (state == AppLifecycleState.detached) {
      // 재생 중 호스트 종료 케이스: foreground service 덕에 detached까지 Dart
      // 코드 도달 가능 → 게스트가 watchdog 2분 대신 즉시 홈 화면으로 돌아갈
      // 수 있도록 best-effort로 host-closed 전송. iOS 강제 종료처럼 detached
      // 자체가 도달 못 하는 경우에는 기존 watchdog이 받아준다.
      debugPrint('[LIFECYCLE] HOST detached → broadcast host-closed (best-effort)');
      onLog('[라이프사이클] detached — host-closed best-effort 전송');
      hostClosed.value = true;
      p2p.broadcastHostClosedBestEffort();
    }
  }

  /// `_leaveRoom` 진입 시 1회 호출. 이후 모든 watchdog/리스너 액션 무시.
  void notifyLeaving() {
    _leaving = true;
    _cancelAwayReconnectLoop();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _disconnectSub?.cancel();
    await _connectivitySub?.cancel();
    await _messageSub?.cancel();
    _cancelAwayReconnectLoop();
    hostAway.dispose();
    hostClosed.dispose();
  }

  // ───────── 내부 핸들러 ─────────

  void _handleMessage(Map<String, dynamic> message) {
    if (_disposed) return;
    final type = message['type'] as String?;
    if (type == 'host-paused') {
      debugPrint('[LIFECYCLE-GUEST] received host-paused');
      hostAway.value = true;
      onLog('호스트 일시 자리비움');
    } else if (type == 'host-resumed') {
      debugPrint('[LIFECYCLE-GUEST] received host-resumed');
      _cancelAwayReconnectLoop();
      hostAway.value = false;
      onLog('호스트 복귀');
    } else if (type == 'host-closed') {
      debugPrint('[LIFECYCLE-GUEST] received host-closed');
      hostClosed.value = true;
      onLog('호스트가 방을 종료했습니다.');
      onSnackbar('호스트가 방을 종료했습니다');
      onLeaveRequested();
    }
  }

  Future<void> _handleDisconnected() async {
    if (_disposed || _leaving) return;
    // host-closed 수신 후 정식 종료 중이면 재연결 시도하지 않고 바로 정리
    if (hostClosed.value) {
      onLog('호스트가 방을 종료했습니다.');
      onLeaveRequested();
      return;
    }
    // 호스트 자리비움 중 TCP 끊김: host-resumed는 이미 죽은 소켓이라 도달 불가.
    // TCP 재접속 성공 자체를 "호스트 복귀 신호"로 삼아 주기적으로 조용히 시도.
    if (hostAway.value) {
      onLog('호스트 자리비움 중 TCP 끊김 → 주기적 재접속 시도 시작');
      _startAwayReconnectLoop();
      return;
    }
    if (_reconnectInProgress) {
      debugPrint('[RECONNECT] _handleDisconnected skip (이미 진행 중)');
      return;
    }
    _reconnectInProgress = true;
    // errno 분기(`_maybeHandleNetworkErrno` → `_waitForWifiAndReconnect`)가
    // flag를 이어받아야 하므로 try 블록은 **재연결 본 흐름**만 감싼다.
    // finally 진입 시점에 flag를 해제 → fall-through로 errno 분기 진입 시
    // `_waitForWifiAndReconnect`가 자체 관리로 다시 잡음. 예외(`onReconnectSyncRequested`
    // 내부 throw 등)가 발생해도 flag 해제가 보장된다.
    try {
      onLog('호스트와 연결이 끊어졌습니다. 재연결 시도 중...');
      onSnackbar('연결이 끊어졌습니다. 재연결 시도 중...');

      final reconnected = await p2p.reconnectToHost();
      if (_disposed || _leaving) return;

      if (reconnected) {
        onLog('재연결 성공!');
        onSnackbar('재연결되었습니다');
        await onReconnectSyncRequested();
        return;
      }
    } finally {
      _reconnectInProgress = false;
    }
    if (await _maybeHandleNetworkErrno(p2p.lastReconnectErrno)) {
      return;
    }
    if (_disposed || _leaving) return;
    onLog('재연결 실패. 방을 나갑니다.');
    onSnackbar('호스트에 재연결할 수 없습니다');
    onLeaveRequested();
  }

  Future<void> _handleConnectivity(List<ConnectivityResult> result) async {
    if (_disposed || _leaving) return;
    if (result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet) ||
        result.contains(ConnectivityResult.other)) {
      return;
    }
    debugPrint('[CONNECTIVITY] non-local event $result (isHost=$isHost) — 1s 재확인');
    // 잠시 대기 후 실제 상태 재확인 (stale/일시적 이벤트 방지)
    await Future.delayed(const Duration(seconds: 1));
    if (_disposed || _leaving) return;
    final current = await Connectivity().checkConnectivity();
    final hasLocal = current.contains(ConnectivityResult.wifi) ||
        current.contains(ConnectivityResult.ethernet) ||
        current.contains(ConnectivityResult.other);
    if (hasLocal) {
      debugPrint('[CONNECTIVITY] 재확인 결과 local 살아있음 → 무시');
      return;
    }
    if (_disposed || _leaving) return;
    if (isHost) {
      // 호스트: WiFi 끊기면 방 유지 불가
      debugPrint('[CONNECTIVITY] HOST WiFi off 확정 → leaveRoom');
      onLog('WiFi 연결이 끊어졌습니다');
      onSnackbar('WiFi 연결이 끊어졌습니다. 방을 나갑니다.');
      onLeaveRequested();
    } else {
      // 게스트: WiFi 복구 대기 후 재연결 시도
      debugPrint('[CONNECTIVITY] GUEST WiFi off 확정 → _waitForWifiAndReconnect');
      onLog('WiFi 연결이 끊어졌습니다. 복구 대기 중...');
      onSnackbar('WiFi 연결이 끊어졌습니다. 복구 대기 중...');
      await _waitForWifiAndReconnect();
    }
  }

  /// 게스트: `hostAway=true` 상태에서 TCP 끊김 감지 시 주기적 재접속.
  /// host-resumed 메시지는 이미 죽은 소켓이라 도달 불가 → 재접속 성공 자체가 복귀 신호.
  /// 5초 간격, 실패해도 계속 시도 (조용히). 방 나가기/호스트 종료/재접속 성공 시 취소.
  void _startAwayReconnectLoop() {
    _awayReconnectTimer?.cancel();
    _awayReconnectAttempts = 0;
    _consecutiveRefused = 0;
    _awayReconnectTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      if (_disposed || !hostAway.value || _leaving || hostClosed.value) {
        t.cancel();
        return;
      }
      if (_awayReconnecting) return; // 이전 시도가 아직 진행 중
      _awayReconnecting = true;
      try {
        final reconnected = await p2p.reconnectToHost(retries: 1);
        if (_disposed || _leaving) return;
        if (reconnected) {
          debugPrint('[AWAY-RECONNECT] success — treating as host resumed');
          t.cancel();
          _awayReconnectTimer = null;
          _awayReconnectAttempts = 0;
          _consecutiveRefused = 0;
          hostAway.value = false;
          onLog('호스트 복귀 감지 (TCP 재접속 성공) — 재동기화');
          onSnackbar('호스트 복귀');
          await onReconnectSyncRequested();
        } else {
          // ECONNREFUSED가 연속으로 잡히면 호스트 프로세스 종료 거의 확정.
          // detached에서 host-closed broadcast가 도달 못한 케이스(재생 전 종료 / iOS
          // 강제 종료) 복구를 watchdog 60초 대신 ~10초로 단축. (LIFECYCLE.md "errno 판정 트리")
          final errno = p2p.lastReconnectErrno;
          // EHOSTUNREACH/ENETUNREACH: 내 WiFi 끊김 가능성 → connectivity 즉시 확인 후 복구 루틴 위임
          if (await _maybeHandleNetworkErrno(errno)) {
            t.cancel();
            _awayReconnectTimer = null;
            return;
          }
          if (errno != null && _refusedErrnos.contains(errno)) {
            _consecutiveRefused++;
          } else {
            _consecutiveRefused = 0;
          }
          if (_consecutiveRefused >= _refusedFastGiveupThreshold) {
            t.cancel();
            _awayReconnectTimer = null;
            debugPrint(
              '[AWAY-RECONNECT] refused (errno=$errno) x$_consecutiveRefused → fast giveup',
            );
            onLog('호스트 종료 감지 (refused 연속). 방을 나갑니다.');
            onSnackbar('호스트가 종료되었습니다. 방을 나갑니다.');
            onLeaveRequested();
            return;
          }
          _awayReconnectAttempts++;
          debugPrint(
            '[AWAY-RECONNECT] attempt $_awayReconnectAttempts/$_awayReconnectMaxAttempts failed (errno=$errno)',
          );
          if (_awayReconnectAttempts >= _awayReconnectMaxAttempts) {
            t.cancel();
            _awayReconnectTimer = null;
            debugPrint(
              '[AWAY-RECONNECT] giving up after $_awayReconnectMaxAttempts attempts → leaveRoom',
            );
            onLog('호스트 복귀 없음 (약 60초 경과). 방을 나갑니다.');
            onSnackbar('호스트가 돌아오지 않습니다. 방을 나갑니다.');
            onLeaveRequested();
          }
        }
      } catch (e) {
        debugPrint('[AWAY-RECONNECT] attempt error: $e');
      } finally {
        _awayReconnecting = false;
      }
    });
  }

  void _cancelAwayReconnectLoop() {
    _awayReconnectTimer?.cancel();
    _awayReconnectTimer = null;
    _awayReconnecting = false;
    _awayReconnectAttempts = 0;
    _consecutiveRefused = 0;
  }

  /// `EHOSTUNREACH` / `ENETUNREACH` (Linux 113/101, Darwin 65/51)이면 connectivity_plus
  /// 이벤트를 기다리지 말고 즉시 내 WiFi 상태 확인 → 끊겨 있으면 `_waitForWifiAndReconnect()`
  /// 트리거. WiFi가 살아있으면 호스트 측 문제로 보고 false 반환 (호출자가 기존 흐름 유지).
  ///
  /// LIFECYCLE.md "errno 판정 트리"의 EHOSTUNREACH/ENETUNREACH 분기 구현. connectivity_plus
  /// 이벤트가 AP 변경/WiFi 변경 케이스에서 늦게 오거나 안 오는 경우의 앞당김 경로.
  Future<bool> _maybeHandleNetworkErrno(int? errno) async {
    if (errno == null || !_networkUnreachableErrnos.contains(errno)) return false;
    if (_disposed) return false;
    final current = await Connectivity().checkConnectivity();
    if (_disposed) return false;
    final hasLocal = current.contains(ConnectivityResult.wifi) ||
        current.contains(ConnectivityResult.ethernet) ||
        current.contains(ConnectivityResult.other);
    if (hasLocal) return false; // 내 WiFi 살아있음 → 호스트 측 문제 → 기존 흐름
    onLog('errno=$errno (network unreachable) + 내 WiFi 끊김 감지 → 복구 대기');
    // 비동기로 시작만 하고 return — 호출자는 기존 흐름 종료해야 함 (true 반환).
    unawaited(_waitForWifiAndReconnect());
    return true;
  }

  /// 게스트: WiFi 복구 대기 (최대 15초) 후 재연결
  Future<void> _waitForWifiAndReconnect() async {
    if (_reconnectInProgress) {
      debugPrint('[CONNECTIVITY] _waitForWifiAndReconnect skip (이미 진행 중)');
      return;
    }
    _reconnectInProgress = true;
    try {
      debugPrint('[CONNECTIVITY] _waitForWifiAndReconnect 시작 (최대 15초)');
      // 최대 15초간 WiFi 복구 대기 (3초 간격 체크)
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(seconds: 3));
        if (_disposed || _leaving) return;
        final current = await Connectivity().checkConnectivity();
        if (current.contains(ConnectivityResult.wifi)) {
          debugPrint('[CONNECTIVITY] WiFi 복구 감지 (check ${i + 1}/5) → reconnectToHost');
          onLog('WiFi 복구됨. 재연결 시도 중...');
          final reconnected = await p2p.reconnectToHost();
          if (_disposed || _leaving) return;
          if (reconnected) {
            debugPrint('[CONNECTIVITY] reconnectToHost OK → sync 재시작');
            onLog('재연결 성공!');
            onSnackbar('재연결되었습니다');
            await onReconnectSyncRequested();
            return;
          }
          debugPrint('[CONNECTIVITY] reconnectToHost 실패 (errno=${p2p.lastReconnectErrno}) — WiFi는 돌아왔지만 호스트 연결 불가');
          break; // WiFi는 복구됐지만 호스트 연결 실패
        }
      }
      if (_disposed || _leaving) return;
      debugPrint('[CONNECTIVITY] WiFi 복구 실패 또는 호스트 연결 불가 → leaveRoom');
      onLog('재연결 실패. 방을 나갑니다.');
      onSnackbar('재연결할 수 없습니다');
      onLeaveRequested();
    } finally {
      _reconnectInProgress = false;
    }
  }
}
