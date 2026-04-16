import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 네이티브 getTimestamp 결과를 담는 불변 객체.
class NativeTimestamp {
  final int framePos;
  final int timeNs;
  final int wallAtFramePosNs;
  final int virtualFrame;
  final int sampleRate;
  final int totalFrames;
  final bool ok;

  const NativeTimestamp({
    required this.framePos,
    required this.timeNs,
    required this.wallAtFramePosNs,
    required this.virtualFrame,
    required this.sampleRate,
    required this.totalFrames,
    required this.ok,
  });

  /// wallAtFramePosNs를 밀리초로 변환.
  int get wallMs => wallAtFramePosNs ~/ 1000000;

  factory NativeTimestamp.fromMap(Map<String, dynamic> m) => NativeTimestamp(
        framePos: (m['framePos'] as num?)?.toInt() ?? 0,
        timeNs: (m['timeNs'] as num?)?.toInt() ?? 0,
        wallAtFramePosNs: (m['wallAtFramePosNs'] as num?)?.toInt() ?? 0,
        virtualFrame: (m['virtualFrame'] as num?)?.toInt() ?? 0,
        sampleRate: (m['sampleRate'] as num?)?.toInt() ?? 0,
        totalFrames: (m['totalFrames'] as num?)?.toInt() ?? 0,
        ok: m['ok'] as bool? ?? false,
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
  /// 성공 시 true, 실패 시 PlatformException throw (message에 에러 코드).
  Future<bool> loadFile(String path) async {
    return await _channel.invokeMethod<bool>('loadFile', path) ?? false;
  }

  /// 네이티브 에러 코드를 사용자 메시지로 변환.
  static String errorToMessage(String code) {
    if (code.startsWith('TOO_LONG:')) {
      final minutes = code.split(':').last;
      return '파일이 너무 깁니다 (약 ${minutes}분, 최대 약 14분)';
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

  /// 엔진 시작 (오디오 세션 활성화 + 재생 시작).
  /// loadFile 호출 후 사용.
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
