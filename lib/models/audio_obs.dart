import 'dart:convert';

/// v3 audio-obs 메시지 페이로드.
/// 호스트가 500ms 주기 + play/stop 이벤트 시 브로드캐스트.
/// 게스트는 이 값으로 drift를 계산하고 seek 보정을 수행.
class AudioObs {
  final int seq;

  /// framePos가 측정된 시각 (호스트 wall clock, ms since epoch).
  /// 네이티브에서 원자적으로 캡처된 wallAtFramePosNs를 ms로 변환한 값.
  final int hostTimeMs;

  /// HAL frame position (하드웨어 출력 프레임 카운터, 단조 증가).
  /// seek에 영향 없음 — rate drift 추적용.
  final int framePos;

  /// CLOCK_MONOTONIC 기준 timeNs (framePos와 쌍).
  final int timeNs;

  /// 호스트의 virtual playhead (seek 반영).
  /// HAL framePos와 달리 seekToFrame 시 즉시 점프.
  /// 게스트는 이 값으로 콘텐츠 정렬(어떤 음을 재생 중인지)을 확인.
  final int virtualFrame;

  /// 호스트의 엔진 sampleRate (Hz). 게스트가 호스트 frame 외삽 시 사용.
  final int sampleRate;

  /// 호스트 재생 상태.
  final bool playing;

  const AudioObs({
    required this.seq,
    required this.hostTimeMs,
    required this.framePos,
    required this.timeNs,
    required this.virtualFrame,
    required this.sampleRate,
    required this.playing,
  });

  Map<String, dynamic> toJson() => {
        'type': 'audio-obs',
        'seq': seq,
        'hostTimeMs': hostTimeMs,
        'framePos': framePos,
        'timeNs': timeNs,
        'virtualFrame': virtualFrame,
        'sampleRate': sampleRate,
        'playing': playing,
      };

  factory AudioObs.fromJson(Map<String, dynamic> m) => AudioObs(
        seq: (m['seq'] as num).toInt(),
        hostTimeMs: (m['hostTimeMs'] as num).toInt(),
        framePos: (m['framePos'] as num).toInt(),
        timeNs: (m['timeNs'] as num).toInt(),
        virtualFrame: (m['virtualFrame'] as num).toInt(),
        sampleRate: (m['sampleRate'] as num?)?.toInt() ?? 0,
        playing: m['playing'] as bool,
      );

  String encodeLine() => '${jsonEncode(toJson())}\n';
}
