import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/peer.dart';

class P2PService {
  static const int defaultPort = 41235;
  static const int _heartbeatIntervalSec = 3;
  // 대용량 다운로드 중 게스트 이벤트 루프가 바쁘면 heartbeat-ack 처리가 지연되어
  // 9초(3회 miss) 안에 못 돌아오는 경우가 잦아 연결이 끊겼음. 5회 miss(15초)로 완화.
  static const int _heartbeatTimeoutMs = 15000;

  ServerSocket? _serverSocket;
  Socket? _hostSocket;
  String? _connectedHostIp;
  String? _roomCode;
  Timer? _heartbeatTimer;
  final List<Peer> _peers = [];
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _peerJoinController = StreamController<Peer>.broadcast();
  final _peerLeaveController = StreamController<String>.broadcast();
  final _disconnectedController = StreamController<void>.broadcast();
  final _proLimitController = StreamController<void>.broadcast();

  // 수익화: 호스트 프로 여부. 무료면 동시 2대(호스트+게스트1)까지만 허용,
  // 프로면 무제한. proProvider 변경 시 setProStatus로 주입(앱 루트 ref.listen).
  bool _isPro = false;

  /// 메시지 수신 스트림
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  /// 참가자 입장 스트림
  Stream<Peer> get onPeerJoin => _peerJoinController.stream;

  /// 참가자 퇴장 스트림
  Stream<String> get onPeerLeave => _peerLeaveController.stream;

  /// 호스트 연결 끊김 스트림 (게스트용)
  Stream<void> get onDisconnected => _disconnectedController.stream;

  /// 무료 호스트가 기기 제한(2대)에 막혀 게스트를 거절했을 때 발화 (호스트용).
  /// PlayerScreen이 구독해 "프로 업그레이드" 유도 팝업을 띄운다.
  Stream<void> get onProLimitReached => _proLimitController.stream;

  /// 호스트 프로 여부 주입. 프로면 게스트 무제한.
  void setProStatus(bool value) => _isPro = value;

  /// 연결된 참가자 목록
  List<Peer> get peers => List.unmodifiable(_peers);

  /// 호스트인지 여부
  bool get isHost => _serverSocket != null;
  String? get connectedHostIp => _connectedHostIp;

  /// 4자리 방 코드 생성
  String generateRoomCode() {
    final random = Random();
    _roomCode = (1000 + random.nextInt(9000)).toString();
    return _roomCode!;
  }

  /// 호스트 존재만 빠르게 확인. raw TCP connect → 즉시 close (코드 검증 없음).
  /// 연결 성공 = 해당 IP:port에 호스트가 listen 중. 실패(timeout/refused 등) = false.
  /// 호스트 측에선 join 메시지 없는 connect를 onDone 분기에서 무시 (peer 추가 안 함).
  Future<bool> pingHost(String ip, int port) async {
    try {
      final s = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 2),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 호스트: TCP 서버 시작
  Future<int> startHost() async {
    await disconnect();
    _serverSocket = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      defaultPort,
      shared: true,
    );

    _serverSocket!.listen(
      (socket) {
        _handleNewPeer(socket);
      },
      onError: (error) {
        debugPrint('Server error: $error');
      },
    );

    _startHeartbeat();
    return _serverSocket!.port;
  }

  /// 호스트: heartbeat 시작 (죽은 피어 감지)
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: _heartbeatIntervalSec), (
      _,
    ) {
      _removeDeadPeers();
      broadcastToAll({'type': 'heartbeat'});
    });
  }

  /// 호스트: paused 진입 시 heartbeat 정지 + host-paused 알림.
  /// background로 가면 Timer가 억제돼서 어차피 안 돌지만,
  /// 복귀(resumed) 직후 stale lastSeen으로 dead 판정되는 걸 막기 위해 명시적으로 cancel.
  void pauseHeartbeat() {
    debugPrint('[P2P] pauseHeartbeat peers=${_peers.length}');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    broadcastToAll({'type': 'host-paused'});
    // paused 진입 전 OS 소켓 버퍼로 강제 flush (짧은 시간 여유 내)
    for (final peer in _peers) {
      try {
        peer.socket.flush();
      } catch (_) {}
    }
  }

  /// 호스트: resumed 시 모든 peer의 lastSeen을 지금 시각으로 리셋한 뒤 heartbeat 재개.
  /// 리셋 안 하면 paused 기간이 lastSeen에 누적돼 바로 dead 판정될 수 있음.
  void resumeHeartbeat() {
    debugPrint('[P2P] resumeHeartbeat peers=${_peers.length}');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final peer in _peers) {
      peer.lastSeen = now;
    }
    broadcastToAll({'type': 'host-resumed'});
    _startHeartbeat();
  }

  /// 호스트: 정식으로 방 종료. 게스트들에게 먼저 알린 뒤 disconnect.
  Future<void> closeRoom() async {
    debugPrint('[P2P] closeRoom peers=${_peers.length}');
    broadcastToAll({'type': 'host-closed'});
    // 메시지가 소켓 버퍼로 flush될 시간 확보
    for (final peer in _peers) {
      try {
        await peer.socket.flush();
      } catch (_) {}
    }
    await Future.delayed(const Duration(milliseconds: 100));
    await disconnect();
  }

  /// 호스트: detached(앱 종료 직전) 콜백에서 호출. await 없이 best-effort로
  /// host-closed를 브로드캐스트 + flush 트리거만 한다. Dart isolate가 곧
  /// 사라질 수 있어서 await을 기대할 수 없음. 메시지가 OS 소켓 버퍼까지
  /// 내려가면 커널이 프로세스 종료 시 마저 보낸다(best-effort).
  void broadcastHostClosedBestEffort() {
    debugPrint('[P2P] broadcastHostClosedBestEffort peers=${_peers.length}');
    broadcastToAll({'type': 'host-closed'});
    for (final peer in _peers) {
      try {
        // flush()는 Future지만 await 안 함 — 호출로 "send" 유도만
        // ignore: discarded_futures
        peer.socket.flush();
      } catch (_) {}
    }
  }

  /// 호스트: 응답 없는 피어 제거
  void _removeDeadPeers() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final deadPeers = _peers
        .where((p) => now - p.lastSeen > _heartbeatTimeoutMs)
        .toList();
    for (final peer in deadPeers) {
      debugPrint('Heartbeat timeout: ${peer.id}');
      peer.socket.destroy();
      _peers.remove(peer);
      _peerLeaveController.add(peer.id);
      broadcastToAll({
        'type': 'peer-left',
        'data': {'peerId': peer.id, 'peerCount': _peers.length},
      });
    }
  }

  int? _lastHostPort;
  String? _lastMyName;
  String? _lastMyDeviceId;
  String? _lastRoomCode;

  /// 마지막 reconnect 시도에서 잡힌 SocketException의 errno (없으면 null).
  /// 호출부가 errno=111(refused) 같은 값으로 빠른 포기 판정에 사용.
  int? _lastReconnectErrno;
  int? get lastReconnectErrno => _lastReconnectErrno;

  /// 참가자: 호스트에 TCP 연결
  ///
  /// [deviceId]는 SharedPreferences에 영속된 UUID v4 hex (`home_screen.dart`의
  /// `_resolveDeviceId()`). 호스트의 stale peer 정리(_handleNewPeer)가 이 값으로
  /// 같은 디바이스의 재접속을 식별하므로 같은 모델 충돌이 0이 됨. (v0.0.73)
  ///
  /// [roomCode] 호스트 입장 코드. 호스트 `_handleNewPeer`에서 비교 → 안 맞으면
  /// `join-rejected` 응답 후 socket.destroy. 재연결 시 `_lastRoomCode` 사용.
  Future<void> connectToHost(
    String ip,
    int port,
    String myName, {
    required String deviceId,
    required String roomCode,
  }) async {
    _hostSocket = await Socket.connect(
      ip,
      port,
      timeout: const Duration(seconds: 2),
    );
    _connectedHostIp = ip;
    _lastHostPort = port;
    _lastMyName = myName;
    _lastMyDeviceId = deviceId;
    _lastRoomCode = roomCode;

    // 입장 메시지 전송
    _sendTo(_hostSocket!, {
      'type': 'join',
      'data': {'name': myName, 'deviceId': deviceId, 'roomCode': roomCode},
    });

    // 호스트로부터 메시지 수신
    _listenToSocket(_hostSocket!, 'host');
  }

  /// 참가자: 호스트에 재연결 시도 (최대 retries회)
  Future<bool> reconnectToHost({int retries = 3}) async {
    final ip = _connectedHostIp;
    final port = _lastHostPort;
    final name = _lastMyName;
    final deviceId = _lastMyDeviceId;
    final roomCode = _lastRoomCode;
    if (ip == null ||
        port == null ||
        name == null ||
        deviceId == null ||
        roomCode == null) {
      return false;
    }

    _hostSocket?.destroy();
    _hostSocket = null;
    _lastReconnectErrno = null;

    for (int i = 0; i < retries; i++) {
      try {
        debugPrint('Reconnect attempt ${i + 1}/$retries to $ip:$port');
        await Future.delayed(Duration(seconds: i + 1)); // 1, 2, 3초 대기
        _hostSocket = await Socket.connect(
          ip,
          port,
          timeout: const Duration(seconds: 2),
        );
        _sendTo(_hostSocket!, {
          'type': 'join',
          'data': {'name': name, 'deviceId': deviceId, 'roomCode': roomCode},
        });
        _listenToSocket(_hostSocket!, 'host');
        debugPrint('Reconnected successfully');
        _lastReconnectErrno = null;
        return true;
      } catch (e) {
        debugPrint('Reconnect attempt ${i + 1} failed: $e');
        if (e is SocketException) {
          _lastReconnectErrno = e.osError?.errorCode;
        } else {
          _lastReconnectErrno = null;
        }
        _hostSocket?.destroy();
        _hostSocket = null;
      }
    }
    return false;
  }

  /// 호스트: 새 참가자 처리
  /// 현재 접속 중인 **고유 기기 수** (joining deviceId 제외). 2대 제한 판정용.
  /// deviceId 비어 있는 peer는 셀 수 없으니 제외. 같은 deviceId(재접속)는 stale
  /// 교체라 카운트하면 안 됨 → joining deviceId와 같은 건 빼고 distinct 집계.
  int _distinctOtherDeviceCount(String joiningDeviceId) {
    final ids = <String>{};
    for (final p in _peers) {
      if (p.deviceId.isEmpty) continue;
      if (joiningDeviceId.isNotEmpty && p.deviceId == joiningDeviceId) continue;
      ids.add(p.deviceId);
    }
    return ids.length;
  }

  void _handleNewPeer(Socket socket) {
    final peerId = '${socket.remoteAddress.address}:${socket.remotePort}';
    String peerName = 'Unknown';
    String peerDeviceId = '';

    _listenToSocket(
      socket,
      peerId,
      onFirstMessage: (message) {
        if (message['type'] != 'join') {
          debugPrint('Invalid first message from $peerId: ${message['type']}');
          socket.destroy();
          return;
        }

        // 입장 코드 검증. 게스트가 보낸 roomCode가 호스트 _roomCode와 일치해야 입장.
        // 누락(빈 문자열 / null)도 reject. join-rejected 메시지로 reason 전달 후 destroy.
        final claimedCode = message['data']['roomCode'] as String? ?? '';
        if (_roomCode == null || claimedCode != _roomCode) {
          debugPrint(
            'Join rejected from $peerId: code=$claimedCode (expected=$_roomCode)',
          );
          _sendTo(socket, {
            'type': 'join-rejected',
            'data': {'reason': 'invalid-code'},
          });
          // flush 시간 확보 후 destroy. socket.flush()는 Future이지만 즉시 destroy 시
          // 게스트가 메시지 못 받을 수 있어 짧은 delay.
          Future.delayed(const Duration(milliseconds: 100), () {
            try {
              socket.destroy();
            } catch (_) {}
          });
          return;
        }

        peerName = message['data']['name'] ?? 'Unknown';
        peerDeviceId = message['data']['deviceId'] ?? '';

        // 수익화: 무료(비프로) 호스트는 동시 2대(호스트+게스트1)까지만. 이미 다른
        // 게스트가 1대 이상 붙어 있으면 새 게스트 거절. 같은 deviceId 재접속은 아래
        // stale 정리로 교체되는 케이스라 카운트에서 제외(_distinctOtherDeviceCount).
        // 호스트가 프로면 무제한이라 통과.
        if (!_isPro && _distinctOtherDeviceCount(peerDeviceId) >= 1) {
          debugPrint('[P2P] Join rejected (pro-required) from $peerId');
          _sendTo(socket, {
            'type': 'join-rejected',
            'data': {'reason': 'pro-required'},
          });
          _proLimitController.add(null); // 호스트 UI에 업그레이드 유도
          Future.delayed(const Duration(milliseconds: 100), () {
            try {
              socket.destroy();
            } catch (_) {}
          });
          return;
        }

        // 재접속 케이스: peer.id는 "ip:port"라 게스트가 새 socket으로 오면 다른 ID로
        // 보인다. 같은 디바이스의 stale peer들이 heartbeat timeout(15초) 전까지 남아
        // 카운트 누적을 일으키는 문제 방지.
        //
        // v0.0.32: name만 비교 → 1:N 환경에서 다른 디바이스(같은 'Guest' 이름)를 stale로
        //          오인해 무한 ping-pong (HISTORY (51)).
        // v0.0.54: name + remoteAddress 비교로 보강. 단 같은 모델 디바이스 2대가 같은
        //          microsecond에 join하면 hex suffix가 충돌하는 1/65536 코너 잔존.
        // v0.0.73: deviceId(SharedPreferences 영속 UUID v4) 단독 비교로 교체. deviceId가
        //          비어 있으면(누락 메시지) stale 정리 자체를 건너뜀 — 기존 peer를 잘못
        //          destroy하는 것보다 일시적 중복이 안전.
        final stalePeers = peerDeviceId.isEmpty
            ? <Peer>[]
            : _peers.where((p) => p.deviceId == peerDeviceId).toList();
        for (final stale in stalePeers) {
          debugPrint(
            '[P2P] stale peer 정리 (deviceId=$peerDeviceId, name=$peerName): ${stale.id}',
          );
          try {
            stale.socket.destroy();
          } catch (_) {}
          _peers.remove(stale);
          _peerLeaveController.add(stale.id);
          broadcastToAll({
            'type': 'peer-left',
            'data': {'peerId': stale.id, 'peerCount': _peers.length},
          });
        }

        final peer = Peer(
          id: peerId,
          name: peerName,
          deviceId: peerDeviceId,
          socket: socket,
        );
        _peers.add(peer);
        _peerJoinController.add(peer);

        // 입장 승인
        _sendTo(socket, {
          'type': 'welcome',
          'data': {
            'peerId': peerId,
            'peerCount': _peers.length,
            'roomCode': _roomCode,
          },
        });

        // 다른 참가자들에게 알림 (peerCount 포함 — 게스트가 매번 절대값으로 재설정)
        broadcastToAll({
          'type': 'peer-joined',
          'data': {
            'peerId': peerId,
            'name': peerName,
            'peerCount': _peers.length,
          },
        }, exclude: peerId);
      },
    );

    // socket.done은 정상/에러 둘 다 종료 신호. 두 분기 모두 broadcast 필요 —
    // iPhone 등 게스트 강제 종료 시 TCP RST로 done이 catchError 분기에 빠지면
    // 다른 게스트에게 peer-left 알림 누락 → 다른 게스트 peerCount 갱신 안 됨
    // (HISTORY (81) 1-B). 통합 처리로 fix.
    void onDone() {
      if (!_peers.any((p) => p.id == peerId)) return;
      _peers.removeWhere((p) => p.id == peerId);
      _peerLeaveController.add(peerId);
      broadcastToAll({
        'type': 'peer-left',
        'data': {'peerId': peerId, 'peerCount': _peers.length},
      });
    }

    socket.done.then((_) => onDone()).catchError((_) => onDone());
  }

  /// 소켓에서 메시지 수신 리스너
  void _listenToSocket(
    Socket socket,
    String sourceId, {
    Function(Map<String, dynamic>)? onFirstMessage,
  }) {
    // v0.0.107: TCP Nagle off (tcpNoDelay). broadcast(audio-tempo/obs/seek)는 응답
    // 없는 단방향이라 Nagle + 수신자 delayed-ACK 상호작용으로 ~200ms+ 지연됨
    // (실측: audio-tempo 전파 256ms vs ping RTT 11ms). 모든 소켓(peer + host)이
    // 거치는 공통 진입점이라 여기서 한 번 설정 → 전 broadcast 경로 지연 제거.
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (e) {
      debugPrint('tcpNoDelay 설정 실패: $e');
    }
    bool isFirst = true;
    // 누적 버퍼 + 라인 시작 오프셋: O(n²) 회피 (#9)
    // List.removeRange 대신 lineStart만 전진시키고, 임계치를 넘으면 한 번에 잘라냄
    var buffer = <int>[];
    int lineStart = 0;
    const newLine = 0x0A; // '\n'

    void processMessage(Map<String, dynamic> message) {
      // 게스트: heartbeat 수신 → 자동 응답
      if (message['type'] == 'heartbeat' && sourceId == 'host') {
        _sendTo(socket, {'type': 'heartbeat-ack'});
        return;
      }
      // 호스트: 게스트 leave 수신 → 즉시 퇴장 처리
      if (message['type'] == 'leave' && sourceId != 'host') {
        final peer = _peers.cast<Peer?>().firstWhere(
          (p) => p!.id == sourceId,
          orElse: () => null,
        );
        if (peer != null) {
          peer.socket.destroy();
          _peers.remove(peer);
          _peerLeaveController.add(peer.id);
          broadcastToAll({
            'type': 'peer-left',
            'data': {'peerId': peer.id, 'peerCount': _peers.length},
          });
        }
        return;
      }
      // 호스트: heartbeat-ack 수신 → lastSeen 갱신
      if (message['type'] == 'heartbeat-ack') {
        final peer = _peers.cast<Peer?>().firstWhere(
          (p) => p!.id == sourceId,
          orElse: () => null,
        );
        if (peer != null) {
          peer.lastSeen = DateTime.now().millisecondsSinceEpoch;
        }
        return;
      }

      if (isFirst && onFirstMessage != null) {
        onFirstMessage(message);
        isFirst = false;
      } else {
        _messageController.add(message);
      }
    }

    socket.listen(
      (data) {
        buffer.addAll(data);
        for (int i = lineStart; i < buffer.length; i++) {
          if (buffer[i] == newLine) {
            final lineBytes = buffer.sublist(lineStart, i);
            lineStart = i + 1;
            try {
              final line = utf8.decode(lineBytes);
              final message = jsonDecode(line) as Map<String, dynamic>;
              message['_from'] = sourceId;
              processMessage(message);
            } catch (e) {
              debugPrint('Parse error: $e');
            }
          }
        }
        // 처리된 부분 잘라내기 (lineStart가 일정 크기 이상 누적됐을 때만)
        if (lineStart > 4096) {
          buffer = buffer.sublist(lineStart);
          lineStart = 0;
        }
      },
      onError: (error) {
        debugPrint('Socket error from $sourceId: $error');
      },
      onDone: () {
        debugPrint('Connection closed: $sourceId');
        if (sourceId == 'host') {
          // 이 콜백 소유의 socket이 이미 재연결로 교체된 old socket이면 무시.
          // 아니면 두 재연결 경로(_handleDisconnected + _waitForWifiAndReconnect)가
          // race로 번갈아 성공·파괴하면서 old onDone이 새 _hostSocket까지 destroy하고
          // disconnect 이벤트를 재발화 → 무한 재연결 루프 발생.
          if (!identical(_hostSocket, socket)) {
            debugPrint('Stale host onDone ignored (socket replaced)');
            return;
          }
          _hostSocket = null;
          // dispose() 후 지연 도착하는 Socket.onDone 가드 (closed controller에 add하면 예외)
          if (!_disconnectedController.isClosed) {
            _disconnectedController.add(null);
          }
        }
      },
    );
  }

  /// 호스트: 모든 참가자에게 메시지 전송
  void broadcastToAll(Map<String, dynamic> message, {String? exclude}) {
    // 전송 중 peer 리스트가 변경될 수 있으므로 스냅샷 순회
    final snapshot = List<Peer>.from(_peers);
    for (final peer in snapshot) {
      if (peer.id != exclude) {
        _sendToPeerSafe(peer, message);
      }
    }
  }

  /// 호스트: 특정 참가자에게 메시지 전송
  void sendToPeer(String peerId, Map<String, dynamic> message) {
    final peer = _peers.cast<Peer?>().firstWhere(
      (p) => p!.id == peerId,
      orElse: () => null,
    );
    if (peer != null) {
      _sendToPeerSafe(peer, message);
    }
  }

  /// 참가자: 호스트에게 메시지 전송
  void sendToHost(Map<String, dynamic> message) {
    final socket = _hostSocket;
    if (socket == null) return;
    try {
      socket.add(utf8.encode('${jsonEncode(message)}\n'));
    } catch (e) {
      debugPrint('Send to host error: $e');
      // 호스트 소켓이 깨진 상태 → 정리 + 재연결 트리거
      _hostSocket?.destroy();
      _hostSocket = null;
      if (!_disconnectedController.isClosed) {
        _disconnectedController.add(null);
      }
    }
  }

  /// 호스트: peer 객체로 안전 전송. 실패 시 즉시 peer 제거 (#15)
  void _sendToPeerSafe(Peer peer, Map<String, dynamic> message) {
    try {
      peer.socket.add(utf8.encode('${jsonEncode(message)}\n'));
    } catch (e) {
      debugPrint('Send error to ${peer.id}: $e');
      try {
        peer.socket.destroy();
      } catch (_) {}
      if (_peers.remove(peer)) {
        _peerLeaveController.add(peer.id);
        // 다른 피어들에게도 알림 (재귀 호출이지만 해당 peer는 이미 _peers에서 빠졌으므로 안전)
        broadcastToAll({
          'type': 'peer-left',
          'data': {'peerId': peer.id, 'peerCount': _peers.length},
        });
      }
    }
  }

  /// 소켓에 JSON 메시지 전송 (줄바꿈 구분) - 일반 socket용
  void _sendTo(Socket socket, Map<String, dynamic> message) {
    try {
      socket.add(utf8.encode('${jsonEncode(message)}\n'));
    } catch (e) {
      debugPrint('Send error: $e');
    }
  }

  /// 연결 종료
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // 게스트: 호스트에게 leave 메시지 전송 후 소켓 종료
    if (_hostSocket != null) {
      _sendTo(_hostSocket!, {'type': 'leave'});
    }

    for (final peer in _peers) {
      peer.socket.destroy();
    }
    _peers.clear();
    _hostSocket?.destroy();
    _hostSocket = null;
    _connectedHostIp = null;
    await _serverSocket?.close();
    _serverSocket = null;
  }

  Future<void> dispose() async {
    await disconnect();
    _messageController.close();
    _peerJoinController.close();
    _peerLeaveController.close();
    _disconnectedController.close();
    _proLimitController.close();
  }
}
