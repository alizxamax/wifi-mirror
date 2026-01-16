import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

// Conditional imports for platform-specific code
import 'signaling_service_stub.dart'
    if (dart.library.io) 'signaling_service_io.dart'
    as platform_impl;

/// Service for WebRTC signaling between peers
///
/// On native platforms, this uses TCP sockets.
/// On web, this uses WebSockets to connect to the host's WebSocket server.
class SignalingService {
  static const String _module = 'Signaling';

  final StreamController<SignalingMessage> _messageController =
      StreamController<SignalingMessage>.broadcast();

  final StreamController<String> _peerConnectedController =
      StreamController<String>.broadcast();

  final StreamController<String> _peerDisconnectedController =
      StreamController<String>.broadcast();

  String? _localDeviceId;
  bool _isServer = false;
  bool _isRunning = false;

  // Platform-specific implementation for native
  late final platform_impl.SignalingPlatform _platformImpl;

  // WebSocket for web clients
  WebSocketChannel? _webSocketChannel;

  SignalingService() {
    _platformImpl = platform_impl.SignalingPlatform(this);
  }

  /// Stream of incoming signaling messages
  Stream<SignalingMessage> get messageStream => _messageController.stream;

  /// Stream of peer connection events
  Stream<String> get peerConnectedStream => _peerConnectedController.stream;

  /// Stream of peer disconnection events
  Stream<String> get peerDisconnectedStream =>
      _peerDisconnectedController.stream;

  /// Whether the signaling service is running
  bool get isRunning => _isRunning;

  /// Whether we are the server (host)
  bool get isServer => _isServer;

  /// Number of connected peers
  int get connectedPeerCount => _platformImpl.connectedPeerCount;

  /// Initialize service with local device ID
  void initialize(String deviceId) {
    _localDeviceId = deviceId;
    AppLogger.info(
      'Signaling service initialized for device: $deviceId',
      _module,
    );
  }

  /// Start as server (for screen sharer / host)
  /// Not supported on web
  Future<void> startServer() async {
    if (kIsWeb) {
      AppLogger.warning(
        'Starting signaling server not supported on web',
        _module,
      );
      throw UnsupportedError('Cannot start signaling server on web platform');
    }

    if (_isRunning) {
      AppLogger.warning('Signaling service already running', _module);
      return;
    }

    try {
      await _platformImpl.startServer(
        port: AppConstants.signalingPort,
        onMessage: _handleMessage,
        onPeerConnected: (peerId) => _peerConnectedController.add(peerId),
        onPeerDisconnected: (peerId) => _peerDisconnectedController.add(peerId),
      );

      _isServer = true;
      _isRunning = true;

      AppLogger.info(
        'Signaling server started on port ${AppConstants.signalingPort}',
        _module,
      );
    } catch (e, stack) {
      AppLogger.error('Failed to start signaling server', e, stack, _module);
      _isRunning = false;
      rethrow;
    }
  }

  /// Handle incoming signaling message
  void _handleMessage(SignalingMessage message) {
    AppLogger.debug(
      'Received message: ${message.type} from ${message.senderId}',
      _module,
    );

    // Forward message to listeners
    if (!_messageController.isClosed) {
      _messageController.add(message);
    }
  }

  /// Connect to a server (for viewer / client)
  Future<void> connectToServer(String host, int port) async {
    if (_isRunning) {
      AppLogger.warning('Already connected', _module);
      return;
    }

    if (kIsWeb) {
      // Use WebSocket on web
      await _connectWebSocket(host, port);
    } else {
      // Use TCP socket on native
      await _connectNative(host, port);
    }
  }

  /// Connect using WebSocket (web platform)
  Future<void> _connectWebSocket(String host, int port) async {
    try {
      // WebSocket port is signaling port + 1
      final wsUrl = 'ws://$host:${port + 1}';
      AppLogger.info('Connecting to WebSocket: $wsUrl', _module);

      _webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _isServer = false;
      _isRunning = true;

      _webSocketChannel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String);
            final message = SignalingMessage.fromJson(json);
            _handleMessage(message);
          } catch (e) {
            AppLogger.error(
              'Failed to parse WebSocket message',
              e,
              null,
              _module,
            );
          }
        },
        onError: (error) {
          AppLogger.error('WebSocket error', error, null, _module);
          _handleDisconnect();
        },
        onDone: () {
          _handleDisconnect();
        },
      );

      // Send join request
      sendMessage(
        SignalingMessage.joinRequest(
          senderId: _localDeviceId!,
          targetId: 'server',
        ),
      );

      AppLogger.info('Connected to signaling server via WebSocket', _module);
    } catch (e, stack) {
      AppLogger.error('Failed to connect via WebSocket', e, stack, _module);
      _isRunning = false;
      rethrow;
    }
  }

  /// Connect using TCP socket (native platform)
  Future<void> _connectNative(String host, int port) async {
    try {
      await _platformImpl.connectToServer(
        host: host,
        port: port,
        localDeviceId: _localDeviceId!,
        onMessage: _handleMessage,
        onDisconnected: _handleDisconnect,
      );

      _isServer = false;
      _isRunning = true;

      AppLogger.info('Connected to signaling server at $host:$port', _module);
    } catch (e, stack) {
      AppLogger.error(
        'Failed to connect to signaling server',
        e,
        stack,
        _module,
      );
      _isRunning = false;
      rethrow;
    }
  }

  /// Handle disconnection
  void _handleDisconnect() {
    AppLogger.info('Disconnected from server', _module);
    _isRunning = false;
    _webSocketChannel = null;
  }

  /// Send a signaling message
  void sendMessage(SignalingMessage message) {
    if (!_isRunning) {
      AppLogger.warning('Cannot send message, service not running', _module);
      return;
    }

    if (kIsWeb && _webSocketChannel != null) {
      // Send via WebSocket on web
      try {
        final jsonStr = jsonEncode(message.toJson());
        _webSocketChannel!.sink.add(jsonStr);
        AppLogger.debug('Sent message via WebSocket: ${message.type}', _module);
      } catch (e) {
        AppLogger.error('Failed to send WebSocket message', e, null, _module);
      }
    } else {
      // Send via platform implementation (TCP socket)
      _platformImpl.sendMessage(message, localDeviceId: _localDeviceId!);
    }
  }

  /// Stop the signaling service
  Future<void> stop() async {
    if (!_isRunning) return;

    // Send disconnect to peers
    if (_localDeviceId != null) {
      sendMessage(SignalingMessage.disconnect(senderId: _localDeviceId!));
    }

    // Close WebSocket if on web
    if (_webSocketChannel != null) {
      await _webSocketChannel!.sink.close();
      _webSocketChannel = null;
    }

    // Close native connections
    await _platformImpl.stop();

    _isRunning = false;
    _isServer = false;

    AppLogger.info('Signaling service stopped', _module);
  }

  /// Clean up resources
  Future<void> dispose() async {
    await stop();
    await _messageController.close();
    await _peerConnectedController.close();
    await _peerDisconnectedController.close();
    AppLogger.info('Signaling service disposed', _module);
  }
}
