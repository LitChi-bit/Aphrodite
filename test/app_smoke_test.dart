import 'package:aphrodite/app/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts at login and opens conversations', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(const ProviderScope(child: App()));
      await tester.pump();

      expect(find.text('欢迎回来'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '账号'),
        'example-user',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '密码'),
        'example-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Aphrodite'), findsOneWidget);
      expect(find.text('产品设计组'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
