import 'package:flutter/material.dart';

import '../auth/screens/login_screen.dart';
import '../chat/models/conversation.dart';
import '../chat/widgets/call_screen.dart';
import '../chat/widgets/chat_list_screen.dart';
import '../chat/widgets/chat_room_screen.dart';

abstract final class AppRouter {
  static const String login = '/login';
  static const String home = '/';
  static const String chatRoom = '/chat';
  static const String call = '/call';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      login => _page(settings, const LoginScreen()),
      home => _page(settings, const ChatListScreen()),
      chatRoom when settings.arguments is Conversation => _page(
          settings,
          ChatRoomScreen(conversation: settings.arguments! as Conversation),
        ),
      call when settings.arguments is String => _page(
          settings,
          CallScreen(title: settings.arguments! as String),
          fullscreenDialog: true,
        ),
      _ => _page(settings, const _UnknownRouteScreen()),
    };
  }

  static MaterialPageRoute<void> _page(
    RouteSettings settings,
    Widget child, {
    bool fullscreenDialog = false,
  }) {
    return MaterialPageRoute<void>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      builder: (_) => child,
    );
  }
}

class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('页面不存在')),
        body: const Center(child: Text('无法打开此页面')),
      );
}
