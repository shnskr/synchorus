import 'package:flutter/services.dart';

/// v3 네이티브 오디오 엔진 Dart 래퍼.
/// Android: Oboe (C++) + NDK MediaCodec 디코딩
/// iOS: AVAudioEngine + AVAudioPlayerNode
/// MethodChannel: com.synchorus/native_audio
class NativeAudioService {
  static const _channel = MethodChannel('com.synchorus/native_audio');

  /// 오디오 파일 로드 (디코딩). path는 로컬 파일 절대경로.
  Future<bool> loadFile(String path) async {
    return await _channel.invokeMethod<bool>('loadFile', path) ?? false;
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
  /// Returns: {framePos, timeNs, wallAtFramePosNs, ok, virtualFrame,
  ///           sampleRate, totalFrames, ...}
  Future<Map<String, dynamic>> getTimestamp() async {
    final result = await _channel.invokeMethod<Map>('getTimestamp');
    return result != null ? Map<String, dynamic>.from(result) : {'ok': false};
  }

  /// 재생 위치 점프 (프레임 단위, 파일 샘플레이트 기준).
  Future<bool> seekToFrame(int frame) async {
    return await _channel.invokeMethod<bool>('seekToFrame', frame) ?? false;
  }

  /// 현재 콘텐츠 위치 조회 (프레임 단위).
  Future<int> getVirtualFrame() async {
    return await _channel.invokeMethod<int>('getVirtualFrame') ?? 0;
  }

  Future<void> dispose() async {
    await stop();
  }
}
