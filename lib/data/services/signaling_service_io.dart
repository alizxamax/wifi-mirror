import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/models.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import 'signaling_service.dart';

/// Native platform implementation for signaling using TCP sockets
/// Also includes a WebSocket server for web clients
class SignalingPlatform {
  static const String _module = 'Signaling';

  final SignalingService _service;

  ServerSocket? _server;
  HttpServer? _webSocketServer;
  Socket? _clientSocket;

  final Map<String, Socket> _connectedPeers = {};
  final Map<String, WebSocket> _webSocketPeers = {};

  void Function(SignalingMessage)? _onMessage;
  void Function(String)? _onPeerConnected;
  void Function(String)? _onPeerDisconnected;

  SignalingPlatform(this._service);

  /// Number of connected peers (TCP + WebSocket)
  int get connectedPeerCount => _connectedPeers.length + _webSocketPeers.length;

  /// Start TCP and WebSocket servers
  Future<void> startServer({
    required int port,
    required void Function(SignalingMessage) onMessage,
    required void Function(String) onPeerConnected,
    required void Function(String) onPeerDisconnected,
  }) async {
    _onMessage = onMessage;
    _onPeerConnected = onPeerConnected;
    _onPeerDisconnected = onPeerDisconnected;

    // Start TCP server for native clients
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);

    _server!.listen(
      _handleClientConnection,
      onError: (error) {
        AppLogger.error('Server error', error, null, _module);
      },
      onDone: () {
        AppLogger.info('Server closed', _module);
      },
    );

    AppLogger.info('TCP signaling server started on port $port', _module);

    // Start WebSocket server for web clients
    await _startWebSocketServer(port + 1);
  }

  /// Start WebSocket server for web clients
  Future<void> _startWebSocketServer(int port) async {
    try {
      _webSocketServer = await HttpServer.bind(InternetAddress.anyIPv4, port);

      _webSocketServer!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final webSocket = await WebSocketTransformer.upgrade(request);
          _handleWebSocketConnection(webSocket, request);
        } else {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.close();
        }
      });

      AppLogger.info('WebSocket server started on port $port', _module);
    } catch (e, stack) {
      AppLogger.error('Failed to start WebSocket server', e, stack, _module);
    }
  }

  /// Handle WebSocket connection from web client
  void _handleWebSocketConnection(WebSocket webSocket, HttpRequest request) {
    final clientId =
        '${request.connectionInfo?.remoteAddress.address}:${request.connectionInfo?.remotePort}';
    AppLogger.info('WebSocket client connected: $clientId', _module);

    String? peerId;

    webSocket.listen(
      (data) {
        try {
          final json = jsonDecode(data as String);
          final message = SignalingMessage.fromJson(json);

          // Store peer ID for this WebSocket
          if (message.type == SignalingType.joinRequest) {
            peerId = message.senderId;
            _webSocketPeers[message.senderId] = webSocket;
            _onPeerConnected?.call(message.senderId);
          }

          _handleMessage(message, webSocket: webSocket);
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
        AppLogger.error(
          'WebSocket client error: $clientId',
          error,
          null,
          _module,
        );
        _handleWebSocketDisconnect(peerId, webSocket);
      },
      onDone: () {
        _handleWebSocketDisconnect(peerId, webSocket);
      },
    );
  }

  /// Handle WebSocket disconnect
  void _handleWebSocketDisconnect(String? peerId, WebSocket webSocket) {
    if (peerId != null && _webSocketPeers.containsKey(peerId)) {
      _webSocketPeers.remove(peerId);
      _onPeerDisconnected?.call(peerId);
      AppLogger.info('WebSocket client disconnected: $peerId', _module);
    }

    try {
      webSocket.close();
    } catch (_) {}
  }

  /// Handle incoming TCP client connection
  void _handleClientConnection(Socket client) {
    final clientId = '${client.remoteAddress.address}:${client.remotePort}';
    AppLogger.info('TCP client connected: $clientId', _module);

    String buffer = '';

    client.listen(
      (data) {
        buffer += utf8.decode(data);
        _processBuffer(buffer, client, (remaining) => buffer = remaining);
      },
      onError: (error) {
        AppLogger.error('Client error: $clientId', error, null, _module);
        _handleClientDisconnect(client);
      },
      onDone: () {
        _handleClientDisconnect(client);
      },
    );
  }

  /// Process incoming data buffer
  void _processBuffer(
    String buffer,
    Socket socket,
    Function(String) updateBuffer,
  ) {
    // Messages are newline-delimited JSON
    while (buffer.contains('\n')) {
      final index = buffer.indexOf('\n');
      final messageStr = buffer.substring(0, index);
      buffer = buffer.substring(index + 1);

      try {
        final json = jsonDecode(messageStr);
        final message = SignalingMessage.fromJson(json);
        _handleMessage(message, socket: socket);
      } catch (e) {
        AppLogger.error(
          'Failed to parse message: $messageStr',
          e,
          null,
          _module,
        );
      }
    }
    updateBuffer(buffer);
  }

  /// Handle signaling message from either TCP or WebSocket client
  void _handleMessage(
    SignalingMessage message, {
    Socket? socket,
    WebSocket? webSocket,
  }) {
    AppLogger.info(
      'Received message: ${message.type} from ${message.senderId}',
      _module,
    );

    switch (message.type) {
      case SignalingType.joinRequest:
        AppLogger.info(
          'Processing join request from: ${message.senderId}',
          _module,
        );
        if (socket != null) {
          _connectedPeers[message.senderId] = socket;
        }
        _onPeerConnected?.call(message.senderId);
        break;

      case SignalingType.disconnect:
        _connectedPeers.remove(message.senderId);
        _webSocketPeers.remove(message.senderId);
        _onPeerDisconnected?.call(message.senderId);
        break;

      default:
        break;
    }

    // Forward message to service
    _onMessage?.call(message);

    // Forward to target if specified
    if (message.targetId != null) {
      AppLogger.info(
        'Forwarding ${message.type} to target: ${message.targetId}',
        _module,
      );
      _forwardMessage(message);
    }
  }

  /// Forward message to target peer
  void _forwardMessage(SignalingMessage message) {
    // Try TCP socket
    final targetSocket = _connectedPeers[message.targetId];
    if (targetSocket != null) {
      _sendToSocket(targetSocket, message);
      return;
    }

    // Try WebSocket
    final targetWebSocket = _webSocketPeers[message.targetId];
    if (targetWebSocket != null) {
      _sendToWebSocket(targetWebSocket, message);
      return;
    }

    AppLogger.warning(
      'Cannot forward message, target not found: ${message.targetId}',
      _module,
    );
  }

  /// Handle client disconnect
  void _handleClientDisconnect(Socket client) {
    String? deviceId;
    _connectedPeers.forEach((id, socket) {
      if (socket == client) {
        deviceId = id;
      }
    });

    if (deviceId != null) {
      _connectedPeers.remove(deviceId);
      _onPeerDisconnected?.call(deviceId!);
      AppLogger.info('Client disconnected: $deviceId', _module);
    }

    try {
      client.close();
    } catch (_) {}
  }

  /// Connect to server as client (native platforms only)
  Future<void> connectToServer({
    required String host,
    required int port,
    required String localDeviceId,
    required void Function(SignalingMessage) onMessage,
    required void Function() onDisconnected,
  }) async {
    _clientSocket = await Socket.connect(
      host,
      port,
      timeout: AppConstants.connectionTimeout,
    );

    String buffer = '';

    _clientSocket!.listen(
      (data) {
        buffer += utf8.decode(data);
        while (buffer.contains('\n')) {
          final index = buffer.indexOf('\n');
          final messageStr = buffer.substring(0, index);
          buffer = buffer.substring(index + 1);

          try {
            final json = jsonDecode(messageStr);
            final message = SignalingMessage.fromJson(json);
            onMessage(message);
          } catch (e) {
            AppLogger.error('Failed to parse message', e, null, _module);
          }
        }
      },
      onError: (error) {
        AppLogger.error('Connection error', error, null, _module);
        onDisconnected();
      },
      onDone: () {
        onDisconnected();
      },
    );

    // Send join request
    final joinMessage = SignalingMessage.joinRequest(
      senderId: localDeviceId,
      targetId: 'server',
    );
    _sendToSocket(_clientSocket!, joinMessage);
  }

  /// Send message
  void sendMessage(SignalingMessage message, {required String localDeviceId}) {
    if (_service.isServer) {
      // Send to specific target or broadcast
      if (message.targetId != null) {
        _forwardMessage(message);
      } else {
        // Broadcast to all connected peers
        for (final socket in _connectedPeers.values) {
          _sendToSocket(socket, message);
        }
        for (final webSocket in _webSocketPeers.values) {
          _sendToWebSocket(webSocket, message);
        }
      }
    } else {
      // Send to server
      if (_clientSocket != null) {
        _sendToSocket(_clientSocket!, message);
      }
    }
  }

  /// Send message to TCP socket
  void _sendToSocket(Socket socket, SignalingMessage message) {
    try {
      final jsonStr = jsonEncode(message.toJson());
      socket.write('$jsonStr\n');
      AppLogger.debug('Sent message: ${message.type}', _module);
    } catch (e) {
      AppLogger.error('Failed to send message', e, null, _module);
    }
  }

  /// Send message to WebSocket
  void _sendToWebSocket(WebSocket webSocket, SignalingMessage message) {
    try {
      final jsonStr = jsonEncode(message.toJson());
      webSocket.add(jsonStr);
      AppLogger.debug('Sent WebSocket message: ${message.type}', _module);
    } catch (e) {
      AppLogger.error('Failed to send WebSocket message', e, null, _module);
    }
  }

  /// Stop the service
  Future<void> stop() async {
    // Close all peer connections
    for (final socket in _connectedPeers.values) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _connectedPeers.clear();

    // Close all WebSocket connections
    for (final webSocket in _webSocketPeers.values) {
      try {
        await webSocket.close();
      } catch (_) {}
    }
    _webSocketPeers.clear();

    // Close servers
    if (_server != null) {
      await _server!.close();
      _server = null;
    }

    if (_webSocketServer != null) {
      await _webSocketServer!.close();
      _webSocketServer = null;
    }

    // Close client socket
    if (_clientSocket != null) {
      await _clientSocket!.close();
      _clientSocket = null;
    }
  }
}
