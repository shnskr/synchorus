// PoC Phase 2: 역할 선택 화면 smoke test.

import 'package:flutter_test/flutter_test.dart';

import 'package:native_audio_engine_android/main.dart';

void main() {
  testWidgets('RoleSelectionPage renders both role buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PocApp());
    expect(find.text('호스트 시작'), findsOneWidget);
    expect(find.text('게스트로 연결'), findsOneWidget);
  });
}
