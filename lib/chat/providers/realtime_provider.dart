import 'package:flutter_riverpod/flutter_riverpod.dart';

final realtimeConnectionProvider =
    StateProvider<RealtimeConnectionState>((ref) {
  return RealtimeConnectionState.disconnected;
});

enum RealtimeConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}
