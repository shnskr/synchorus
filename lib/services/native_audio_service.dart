import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// loadFile 반환값.
class LoadResult {
  final bool ok;
  final int? totalFrames;
  final double? sampleRate;
  const LoadResult({required this.ok, this.totalFrames, this.sampleRate});
}

/// 네이티브 getTimestamp 결과를 담는 불변 객체.
class NativeTimestamp {
  final int framePos;
  final int timeNs;
  final int wallAtFramePosNs;
  final int virtualFrame;
  final int sampleRate;
  final int totalFrames;
  final bool ok;

  /// 출력 라우트 latency (ms). 디코더 출력 → DAC/transducer까지 OS 추정값.
  /// 내장 스피커는 5~30ms, BT는 150~300ms (코덱·기기 의존, 워밍업 직후 50~60ms
  /// 과소보고 / 분 단위 ±30~70ms 변동 가능). drift 공식에서 호스트·게스트
  /// 양쪽이 빼주면 비대칭(특히 한쪽 BT)이 줄어듦.
  /// null = 미지원/측정 불가 (Dart 측에서 0 fallback).
  final double? outputLatencyMs;

  /// v0.0.124: 무음(underrun) 누적 카운터 (측정 보고서용, PLAN ②). monotonic 증가 →
  /// csv에서 두 시점 delta로 구간 무음량 분석. decode=ring decode 못 따라옴(vf>=ringHead),
  /// st=SoundTouch out-ring 부족 silence padding. frames=총 무음 frame, events=끊김 횟수.
  /// -1 = 미지원 (iOS는 AVAudioEngine 내부 버퍼라 동일 카운트 불가).
  final int decodeUnderrunFrames;
  final int decodeUnderrunEvents;
  final int stUnderrunFrames;
  final int stUnderrunEvents;

  const NativeTimestamp({
    required this.framePos,
    required this.timeNs,
    required this.wallAtFramePosNs,
    required this.virtualFrame,
    required this.sampleRate,
    required this.totalFrames,
    required this.ok,
    this.outputLatencyMs,
    this.decodeUnderrunFrames = 0,
    this.decodeUnderrunEvents = 0,
    this.stUnderrunFrames = 0,
    this.stUnderrunEvents = 0,
  });

  /// wallAtFramePosNs를 밀리초로 변환. v0.0.115: 검증 대조용으로만 유지(정렬엔 monoMs).
  int get wallMs => wallAtFramePosNs ~/ 1000000;

  /// timeNs(BOOTTIME ns @ framePos)를 ms로. v0.0.115 monotonic 전환 — 정렬 외삽용.
  /// ⚠️ ts.ok=false(timeNs=-1) 시 0이 되므로 정렬은 ok 가드 통과 후만 사용. 상대시간
  /// (cooldown 등)엔 monoMs 대신 MonotonicClock.nowMs()(현재 시각) 직접 사용.
  int get monoMs => timeNs ~/ 1000000;

  /// drift 공식에 적용할 안전한 값. null/음수/700ms 초과는 0으로 무시.
  /// (OS 보고 비정상 시 보정 자체가 노이즈가 되지 않도록 차단.)
  /// v0.0.112: 상한 500→700. transpose/speed ON일 때 native가 SoundTouch 파이프라인
  /// latency(~수백ms)를 HAL latency에 더해 보고하므로(SYNC_REDESIGN 결함 B),
  /// 정상값이 500을 넘을 수 있어 상향. 700 초과는 여전히 outlier로 차단.
  double get safeOutputLatencyMs {
    final v = outputLatencyMs;
    if (v == null || v < 0 || v > 700) return 0.0;
    return v;
  }

  factory NativeTimestamp.fromMap(Map<String, dynamic> m) => NativeTimestamp(
        framePos: (m['framePos'] as num?)?.toInt() ?? 0,
        timeNs: (m['timeNs'] as num?)?.toInt() ?? 0,
        wallAtFramePosNs: (m['wallAtFramePosNs'] as num?)?.toInt() ?? 0,
        virtualFrame: (m['virtualFrame'] as num?)?.toInt() ?? 0,
        sampleRate: (m['sampleRate'] as num?)?.toInt() ?? 0,
        totalFrames: (m['totalFrames'] as num?)?.toInt() ?? 0,
        ok: m['ok'] as bool? ?? false,
        outputLatencyMs: (m['outputLatencyMs'] as num?)?.toDouble(),
        // v0.0.124: 키 없으면 0 (구버전 native), iOS는 -1(미지원) 명시 보고.
        decodeUnderrunFrames: (m['decodeUnderrunFrames'] as num?)?.toInt() ?? 0,
        decodeUnderrunEvents: (m['decodeUnderrunEvents'] as num?)?.toInt() ?? 0,
        stUnderrunFrames: (m['stUnderrunFrames'] as num?)?.toInt() ?? 0,
        stUnderrunEvents: (m['stUnderrunEvents'] as num?)?.toInt() ?? 0,
      );
}

/// v3 네이티브 오디오 엔진 Dart 래퍼.
/// Android: Oboe (C++) + NDK MediaCodec 디코딩
/// iOS: AVAudioEngine + AVAudioPlayerNode
/// MethodChannel: com.synchorus/native_audio
class NativeAudioService {
  static const _channel = MethodChannel('com.synchorus/native_audio');

  Timer? _pollTimer;
  final _timestampController = StreamController<NativeTimestamp>.broadcast();
  NativeTimestamp? _latest;

  /// 최신 타임스탬프 (폴링 중일 때만 갱신).
  NativeTimestamp? get latest => _latest;

  /// 타임스탬프 폴링 결과 스트림.
  Stream<NativeTimestamp> get timestampStream => _timestampController.stream;

  /// 오디오 파일 로드 (디코딩). path는 로컬 파일 절대경로.
  /// 성공 시 {ok, totalFrames, sampleRate} 반환, 실패 시 PlatformException throw.
  Future<LoadResult> loadFile(String path) async {
    final result = await _channel.invokeMethod('loadFile', path);
    // Android: Map (§G step 1부터, 이전 bool fallback 호환 유지), iOS: Map
    if (result is bool) {
      return LoadResult(ok: result);
    } else if (result is Map) {
      final m = Map<String, dynamic>.from(result);
      return LoadResult(
        ok: m['ok'] as bool? ?? false,
        totalFrames: (m['totalFrames'] as num?)?.toInt(),
        sampleRate: (m['sampleRate'] as num?)?.toDouble(),
      );
    }
    return LoadResult(ok: false);
  }

  /// 네이티브 에러 코드를 사용자 메시지로 변환.
  static String errorToMessage(String code) {
    if (code.startsWith('TOO_LONG:')) {
      final minutes = code.split(':').last;
      return '파일이 너무 깁니다 (약 $minutes분, 최대 약 14분)';
    }
    switch (code) {
      case 'FILE_OPEN_FAILED':
        return '파일을 열 수 없습니다';
      case 'UNSUPPORTED_FORMAT':
        return '지원하지 않는 파일 형식입니다';
      case 'NO_AUDIO_TRACK':
        return '오디오 트랙이 없는 파일입니다';
      case 'UNSUPPORTED_CODEC':
        return '지원하지 않는 오디오 코덱입니다';
      default:
        return '파일 로드 실패: $code';
    }
  }

  /// 엔진 사전 워밍업 (오디오 세션 활성화 + 엔진 가동, PCM 송신 0).
  /// loadFile 직후 호출하면 BT codec/AVAudioSession 워밍업 + outputLatency 안정화가
  /// 미리 끝나, 다음 start() 지연이 100~500ms → 수십 ms로 단축. (v0.0.44)
  Future<bool> prewarm() async {
    return await _channel.invokeMethod<bool>('prewarm') ?? false;
  }

  /// prewarm 효과 해제 (엔진/세션 내림). audioFile 보존, 다음 prewarm/start 시
  /// 디코딩 재사용. iOS는 setActive(false)로 다른 앱 오디오 풀어줌. (v0.0.44)
  Future<bool> coolDown() async {
    return await _channel.invokeMethod<bool>('coolDown') ?? false;
  }

  /// 엔진 시작 (오디오 세션 활성화 + 재생 시작).
  /// loadFile 호출 후 사용. prewarm 됐으면 그 효과 활용.
  Future<bool> start() async {
    return await _channel.invokeMethod<bool>('start') ?? false;
  }

  /// 엔진 정지.
  Future<bool> stop() async {
    return await _channel.invokeMethod<bool>('stop') ?? false;
  }

  /// 타임스탬프 조회 (sync용).
  Future<NativeTimestamp?> getTimestamp() async {
    final result = await _channel.invokeMethod<Map>('getTimestamp');
    if (result == null) return null;
    return NativeTimestamp.fromMap(Map<String, dynamic>.from(result));
  }

  /// 재생 위치 점프 (프레임 단위, 파일 샘플레이트 기준).
  Future<bool> seekToFrame(int frame) async {
    return await _channel.invokeMethod<bool>('seekToFrame', frame) ?? false;
  }

  /// 현재 콘텐츠 위치 조회 (프레임 단위).
  Future<int> getVirtualFrame() async {
    return await _channel.invokeMethod<int>('getVirtualFrame') ?? 0;
  }

  /// 음소거 설정.
  Future<void> setMuted(bool muted) async {
    await _channel.invokeMethod('setMuted', muted);
  }

  /// 음소거 상태 조회.
  Future<bool> isMuted() async {
    return await _channel.invokeMethod<bool>('isMuted') ?? false;
  }

  /// PCM 버퍼 및 파일 상태 해제 (방 나가기/앱 종료 시).
  Future<bool> unload() async {
    return await _channel.invokeMethod<bool>('unload') ?? false;
  }

  /// v0.0.134 (HISTORY (162) T2): stuck 스트림(Started인데 콜백 사망) 자동복구.
  /// 출력 스트림만 close→reopen. vf·디코드·파일 보존(현재 위치 재개). **Android 전용**
  /// — iOS는 reopenStream 미구현(route/interruption 시 rebuildEngineAndResume 반응형
  /// 복구 보유)이라 watchdog 호출부에서 Platform.isAndroid 게이트 필요.
  Future<bool> reopenStream() async {
    return await _channel.invokeMethod<bool>('reopenStream') ?? false;
  }

  /// v0.0.134 디버그 전용: watchdog 검증용 강제 stuck (vf 동결). kDebugMode UI에서만 호출.
  Future<void> setDebugForceStuck(bool stuck) async {
    await _channel.invokeMethod('setDebugForceStuck', stuck);
  }

  /// §H Transpose pitch (cents 단위, 1 semitone = 100 cents). 범위 ±2400.
  Future<void> setSemitoneCents(int cents) async {
    await _channel.invokeMethod('setSemitoneCents', cents);
  }

  Future<int> getSemitoneCents() async {
    return await _channel.invokeMethod<int>('getSemitoneCents') ?? 0;
  }

  /// §I 속도. speedX1000 정수 (500~2000 = 0.5x~2.0x). pitch 유지.
  Future<void> setPlaybackSpeedX1000(int speedX1000) async {
    await _channel.invokeMethod('setPlaybackSpeedX1000', speedX1000);
  }

  Future<int> getPlaybackSpeedX1000() async {
    return await _channel.invokeMethod<int>('getPlaybackSpeedX1000') ?? 1000;
  }

  /// 주기적 타임스탬프 폴링 시작.
  void startPolling({Duration interval = const Duration(milliseconds: 100)}) {
    stopPolling();
    _pollTimer = Timer.periodic(interval, (_) => _pollOnce());
  }

  /// 폴링 중지.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce() async {
    try {
      final ts = await getTimestamp();
      if (ts != null) {
        _latest = ts;
        _timestampController.add(ts);
      }
    } catch (e) {
      debugPrint('NativeAudioService poll error: $e');
    }
  }

  Future<void> dispose() async {
    stopPolling();
    await stop();
    await _timestampController.close();
  }
}
