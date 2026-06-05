import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 두 기기 정렬용 monotonic 시계 (BOOTTIME 계열 — deep sleep 포함 + NTP 점프 면역).
///
/// `DateTime.now()`(wall clock)를 대체한다. wall은 NTP 보정에 점프해 clock offset과
/// 정렬이 흔들린다(측정3 root cause). BOOTTIME 계열은 단조 증가 + deep sleep 포함이라
/// 두 기기 offset이 점프 없이 천천히 drift만 한다. 상세: docs/SYNC_REDESIGN.md (130).
///
/// 플랫폼별 (1차 소스 검증, SYNC_REDESIGN (130) 매핑 표):
/// - Android: `clock_gettime(CLOCK_BOOTTIME)` — bionic, deep sleep 포함. (CLOCK_BOOTTIME=7)
/// - iOS: `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` — mach_continuous_time 도메인,
///   deep sleep 포함. (Darwin `CLOCK_MONOTONIC`은 REALTIME offset이라 NTP에 점프 → 금지,
///   RAW 사용.)
///
/// **도메인 일치 제약**: 여기서 읽는 값과 native getTimestamp가 보고하는 mono@framePos가
/// 같은 clock domain이어야 offset/anchor 외삽이 성립한다. Android는 양쪽 다 CLOCK_BOOTTIME,
/// iOS는 native가 AVAudioTime.hostTime(mach_absolute)을 continuous로 변환해 보고하므로 일치.
class MonotonicClock {
  MonotonicClock._();

  // clock id (Android bionic CLOCK_BOOTTIME=7 / Darwin <sys/_clock_id.h> MONOTONIC_RAW=4).
  // 값이 틀리면 함수가 0 반환(iOS)/비0 반환(Android) → nowNs가 wall fallback.
  // 실측(task #6)에서 isNative + 값 단조성으로 확인.
  static const int _clockBoottime = 7; // Linux/Android
  static const int _clockMonotonicRaw = 4; // Darwin (iOS/macOS)

  static final _ClockGettimeDart? _clockGettime = _lookupClockGettime();
  static final _ClockGettimeNsecNpDart? _clockGettimeNsecNp = _lookupNsecNp();

  // Android timespec 재사용 버퍼. Dart는 single isolate event loop라 재사용 안전
  // (동시 호출 없음). iOS는 alloc 불필요(uint64 직접)라 미사용.
  static final Pointer<_Timespec> _ts =
      Platform.isAndroid ? calloc<_Timespec>() : nullptr;

  /// FFI 경로가 살아있는지 (실측 진단용). false면 nowNs가 wall로 graceful degrade —
  /// 이 경우 두 기기 도메인이 섞일 수 있으므로 로그/csv로 모니터해야 한다.
  static bool get isNative =>
      (Platform.isIOS && _clockGettimeNsecNp != null) ||
      (Platform.isAndroid && _clockGettime != null && _ts != nullptr);

  /// monotonic 현재 시각 (ns). 부팅 후 경과 기준 (wall epoch 아님).
  static int nowNs() {
    if (Platform.isIOS) {
      final f = _clockGettimeNsecNp;
      if (f != null) {
        final v = f(_clockMonotonicRaw);
        if (v != 0) return v;
      }
    } else if (Platform.isAndroid) {
      final f = _clockGettime;
      if (f != null && _ts != nullptr) {
        if (f(_clockBoottime, _ts) == 0) {
          final r = _ts.ref;
          return r.tvSec * 1000000000 + r.tvNsec;
        }
      }
    }
    // fallback: wall (FFI 미지원/실패 시에만. 도메인 섞임 위험 → isNative로 모니터).
    return DateTime.now().microsecondsSinceEpoch * 1000;
  }

  /// monotonic 현재 시각 (ms). 기존 ms 기반 clock sync 로직 1:1 치환용.
  static int nowMs() => nowNs() ~/ 1000000;

  static _ClockGettimeDart? _lookupClockGettime() {
    if (!Platform.isAndroid) return null;
    try {
      return DynamicLibrary.process()
          .lookupFunction<_ClockGettimeNative, _ClockGettimeDart>(
              'clock_gettime');
    } catch (_) {
      return null;
    }
  }

  static _ClockGettimeNsecNpDart? _lookupNsecNp() {
    if (!Platform.isIOS) return null;
    try {
      return DynamicLibrary.process()
          .lookupFunction<_ClockGettimeNsecNpNative, _ClockGettimeNsecNpDart>(
              'clock_gettime_nsec_np');
    } catch (_) {
      return null;
    }
  }
}

// struct timespec { time_t tv_sec; long tv_nsec; } — arm64 전제(둘 다 64bit).
// 우리 타겟(S22/A7 Lite/iPhone 12)은 모두 arm64. 32bit ABI 미지원.
final class _Timespec extends Struct {
  @Int64()
  external int tvSec;

  @Int64()
  external int tvNsec;
}

typedef _ClockGettimeNative = Int32 Function(Int32, Pointer<_Timespec>);
typedef _ClockGettimeDart = int Function(int, Pointer<_Timespec>);

typedef _ClockGettimeNsecNpNative = Uint64 Function(Int32);
typedef _ClockGettimeNsecNpDart = int Function(int);
