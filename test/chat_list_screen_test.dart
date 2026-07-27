import 'package:aphrodite/chat/widgets/chat_list_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search opens, filters conversations, and closes cleanly', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ChatListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('产品设计组'), findsOneWidget);
      expect(find.text('家人'), findsOneWidget);
      expect(find.byType(SearchBar), findsNothing);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      expect(find.byType(SearchBar), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), '产品');
      await tester.pump();

      expect(find.text('产品设计组'), findsOneWidget);
      expect(find.text('家人'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.byType(SearchBar), findsNothing);
      expect(find.text('产品设计组'), findsOneWidget);
      expect(find.text('家人'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
