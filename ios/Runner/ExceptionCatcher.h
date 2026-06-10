//
//  ExceptionCatcher.h
//  Runner
//
//  AVAudioPlayerNode.play() 등이 던지는 Objective-C NSException을 Swift에서 잡기
//  위한 헬퍼. Swift의 do-catch는 Swift Error만 잡고 ObjC NSException은 못 잡으므로,
//  @try/@catch로 감싼 static inline 함수를 bridging header로 노출한다.
//
//  "player did not see an IO cycle"은 play() 호출 전 상태 체크로 100% 못 막는
//  TOCTOU race(체크와 play() 사이에 route change가 끼어듦 — Apple DTS forum 129207
//  / AudioKit #2910에서 notification 핸들러를 다 구현해도 production crash 잔존
//  확인)라, 던져진 예외를 잡는 게 크래시(SIGABRT 앱 종료) 방지의 유일한 확실한 방법.
//

#ifndef ExceptionCatcher_h
#define ExceptionCatcher_h

#import <Foundation/Foundation.h>

/// block 실행 중 던져진 NSException을 잡아 반환한다. 예외 없으면 nil.
NS_INLINE NSException * _Nullable objcTryCatch(void (^_Nonnull block)(void)) {
    @try {
        block();
        return nil;
    }
    @catch (NSException *exception) {
        return exception;
    }
}

#endif /* ExceptionCatcher_h */
