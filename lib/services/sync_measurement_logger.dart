import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 호스트에서 모든 게스트의 drift 데이터를 CSV로 기록하는 로거.
/// 게스트는 drift-report P2P 메시지로 데이터를 전송, 호스트가 통합 기록.
class SyncMeasurementLogger {
  IOSink? _sink;
  File? _logFile;
  bool _isActive = false;

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
    _sink!.writeln(
      'wall_ms,guest_id,drift_ms,offset_ms,host_vf,guest_vf,seek_count,event',
    );
    _isActive = true;
    debugPrint('[MEASURE] started: ${_logFile!.path}');
  }

  void log({
    required int wallMs,
    required String guestId,
    required double driftMs,
    required double offsetMs,
    required int hostVf,
    required int guestVf,
    required int seekCount,
    String event = 'drift',
  }) {
    if (!_isActive) return;
    _sink?.writeln(
      '$wallMs,$guestId,${driftMs.toStringAsFixed(2)},${offsetMs.toStringAsFixed(1)},$hostVf,$guestVf,$seekCount,$event',
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
