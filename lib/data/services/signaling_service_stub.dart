import '../models/models.dart';

/// Stub implementation for web platform
///
/// On web, TCP sockets are not available. The SignalingService uses
/// WebSockets directly instead of this platform implementation.
class SignalingPlatform {
  // ignore: avoid_unused_constructor_parameters
  SignalingPlatform(dynamic service);

  /// Number of connected peers - always 0 on web stub
  int get connectedPeerCount => 0;

  /// Start server - not supported on web
  Future<void> startServer({
    required int port,
    required void Function(SignalingMessage) onMessage,
    required void Function(String) onPeerConnected,
    required void Function(String) onPeerDisconnected,
  }) async {
    throw UnsupportedError('TCP server not supported on web');
  }

  /// Connect to server - not used on web (uses WebSocket directly)
  Future<void> connectToServer({
    required String host,
    required int port,
    required String localDeviceId,
    required void Function(SignalingMessage) onMessage,
    required void Function() onDisconnected,
  }) async {
    throw UnsupportedError('TCP client not supported on web');
  }

  /// Send message - not used on web
  void sendMessage(SignalingMessage message, {required String localDeviceId}) {
    // Not used on web
  }

  /// Stop - not used on web
  Future<void> stop() async {
    // Not used on web
  }
}
