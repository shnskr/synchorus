import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 호스트에서 모든 게스트의 drift 데이터를 CSV로 기록하는 로거.
/// 게스트는 drift-report P2P 메시지로 데이터를 전송, 호스트가 통합 기록.
class SyncMeasurementLogger {
  IOSink? _sink;
  File? _logFile;
  bool _isActive = false;
  int _nextSeq = 0;

  bool get isActive => _isActive;
  String? get logFilePath => _logFile?.path;

  Future<void> start() async {
    await stop();
    // Android: `getApplicationDocumentsDirectory()`가 Samsung Secure Folder 등의
    // multi-user 공간(`/data/user/95/...`)으로 떨어지면 `run-as` 접근이 막혀
    // 실측 csv를 뽑지 못하는 문제가 있었다(HISTORY.md (30)). 외부 앱 전용 저장소
    // (`/sdcard/Android/data/<pkg>/files/`)는 `adb pull` 직접 가능하고 앱 uninstall 시
    // 자동 정리된다. null 반환(접근 불가) 시 documents로 fallback.
    // iOS는 `getExternalStorageDirectory()` 자체가 UnsupportedError.
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
    }
    dir ??= await getApplicationDocumentsDirectory();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    _logFile = File('${dir.path}/sync_log_$ts.csv');
    _sink = _logFile!.openWrite();
    // wall_ms: 호스트가 row 기록한 시각 (host_recv_wall로 통일 — 두 기기 시계
    // mix 회피, 단조 증가 보장). guest_wall: 게스트 보고의 원본 wallMs (TCP lag
    // + clock offset 분석용, 호스트 이벤트엔 0). seq: csv 자체 단조 시퀀스 —
    // 빠른 연타 시 같은 wallMs 이벤트 정렬용.
    // v0.0.52 진단 컬럼: outputLatency 비대칭 분석용.
    // out_lat_host_raw: 호스트가 broadcast한 obs.hostOutputLatencyMs (호스트 OS 보고)
    // out_lat_guest_raw: 게스트 ts.safeOutputLatencyMs (게스트 OS 보고)
    // out_lat_delta_current: guest_raw - host_raw (매 poll 측정 순간차이)
    // out_lat_delta_anchored: anchor 시점 베이크인된 _anchoredOutLatDeltaMs
    //                        (보정 기준값 — 매 poll 변화 시 dynLatDelta로만 보정)
    // 4개 추가하면 vfDiff 잔재가 어디서 왔는지 직접 분해 가능.
    // v0.0.56 진단 컬럼: anchor_reset_offset_drift root cause 분해용.
    // raw_offset_ms: 가장 최근 ping/pong sample의 raw offset (EMA 적용 전)
    // win_min_raw_offset_ms: window 내 min-RTT sample raw offset (실제 EMA 입력)
    // last_rtt_ms / win_min_rtt_ms: 최근/window-min RTT — RTT outlier 추적
    // §G step 1 진단 컬럼 (2026-05-11): G-3 EMA 캘리브레이션 데이터 사전 확보용.
    // decode_load_ms: native loadFile 소요 시간 (ms)
    // decode_total_frames: loadFile 직후 totalFrames (없으면 0)
    // decode_throughput_fpms: decode_total_frames / decode_load_ms (frames per ms)
    // event='decode_load' row만 의미, 다른 row는 모두 0.
    // v0.0.85 진단 컬럼 (2026-05-17 (100) 후속): 호스트 빠른 seek 연타 시 게스트 sync
    // 누락 root cause 좁힘용. host_seek event에서 ++한 단조 카운터를 seek-notify
    // p2p 메시지에 동봉 → 게스트 anchor_reset_seek_notify event row에 같은 값 기록.
    // csv 안에서 송수신 1:1 매칭으로 메시지 손실 vs handler 자체 발화 누락 분리.
    // host_seek 이외 row는 0.
    // v0.0.124 진단 컬럼 (PLAN ②): 무음(underrun) 누적 카운터. 호스트/게스트 각자
    // native 엔진의 누적값(monotonic) — 두 row의 delta로 구간 무음량 분석.
    // *_decode_under_frames: ring decode 못 따라온 frame(vf>=ringHead) 누적
    // *_st_under_frames: SoundTouch out-ring 부족 silence padding frame 누적
    // *_*_events: 그런 콜백 횟수(끊김 횟수). frames/SR*1000 = 총 무음 ms.
    // iOS는 -1(AVAudioEngine 내부 버퍼라 동일 카운트 불가).
    _sink!.writeln(
      'seq,wall_ms,guest_wall,guest_id,drift_ms,vf_diff_ms,host_obs_wall,offset_ms,host_vf,guest_vf,seek_count,out_lat_host_raw,out_lat_guest_raw,out_lat_delta_current,out_lat_delta_anchored,raw_offset_ms,win_min_raw_offset_ms,last_rtt_ms,win_min_rtt_ms,decode_load_ms,decode_total_frames,decode_throughput_fpms,seek_msg_seq,guest_decode_under_frames,guest_decode_under_events,guest_st_under_frames,guest_st_under_events,host_decode_under_frames,host_decode_under_events,host_st_under_frames,host_st_under_events,event',
    );
    _nextSeq = 0;
    _isActive = true;
    debugPrint('[MEASURE] started: ${_logFile!.path}');
  }

  void log({
    required int wallMs,
    int guestWall = 0,
    required String guestId,
    required double driftMs,
    required double vfDiffMs,
    required int hostObsWall,
    required double offsetMs,
    required int hostVf,
    required int guestVf,
    required int seekCount,
    double outLatHostRaw = 0,
    double outLatGuestRaw = 0,
    double outLatDeltaCurrent = 0,
    double outLatDeltaAnchored = 0,
    double rawOffsetMs = 0,
    double winMinRawOffsetMs = 0,
    int lastRttMs = 0,
    int winMinRttMs = 0,
    int decodeLoadMs = 0,
    int decodeTotalFrames = 0,
    double decodeThroughputFpms = 0,
    int seekMsgSeq = 0,
    // v0.0.124: 무음(underrun) 누적 카운터. -1=미지원(iOS).
    int guestDecodeUnderFrames = 0,
    int guestDecodeUnderEvents = 0,
    int guestStUnderFrames = 0,
    int guestStUnderEvents = 0,
    int hostDecodeUnderFrames = 0,
    int hostDecodeUnderEvents = 0,
    int hostStUnderFrames = 0,
    int hostStUnderEvents = 0,
    String event = 'drift',
  }) {
    if (!_isActive) return;
    final seq = _nextSeq++;
    _sink?.writeln(
      '$seq,$wallMs,$guestWall,$guestId,${driftMs.toStringAsFixed(2)},${vfDiffMs.toStringAsFixed(2)},$hostObsWall,${offsetMs.toStringAsFixed(1)},$hostVf,$guestVf,$seekCount,${outLatHostRaw.toStringAsFixed(2)},${outLatGuestRaw.toStringAsFixed(2)},${outLatDeltaCurrent.toStringAsFixed(2)},${outLatDeltaAnchored.toStringAsFixed(2)},${rawOffsetMs.toStringAsFixed(1)},${winMinRawOffsetMs.toStringAsFixed(1)},$lastRttMs,$winMinRttMs,$decodeLoadMs,$decodeTotalFrames,${decodeThroughputFpms.toStringAsFixed(2)},$seekMsgSeq,$guestDecodeUnderFrames,$guestDecodeUnderEvents,$guestStUnderFrames,$guestStUnderEvents,$hostDecodeUnderFrames,$hostDecodeUnderEvents,$hostStUnderFrames,$hostStUnderEvents,$event',
    );
  }

  Future<String?> stop() async {
    if (!_isActive) return null;
    _isActive = false;
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    debugPrint('[MEASURE] stopped: ${_logFile?.path}');
    return _logFile?.path;
  }

  Future<void> dispose() async {
    await stop();
  }
}
