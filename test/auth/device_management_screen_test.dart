import 'package:aphrodite/auth/screens/device_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the protected demo-state without loading devices',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DeviceManagementScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('设备管理'), findsOneWidget);
    expect(find.text('使用真实账号登录后可管理设备'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });
}
