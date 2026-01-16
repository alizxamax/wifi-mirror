import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/models.dart';
import '../../core/utils/logger.dart';
import 'signaling_service.dart';

/// Service for handling WebRTC connections for screen sharing
class WebRTCService {
  static const String _module = 'WebRTC';

  final SignalingService _signalingService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final StreamController<WebRTCConnectionState> _connectionStateController =
      StreamController<WebRTCConnectionState>.broadcast();

  final StreamController<StreamingMetrics> _metricsController =
      StreamController<StreamingMetrics>.broadcast();

  String? _localDeviceId;
  String? _remoteDeviceId;
  StreamingQuality _quality = StreamingQuality.medium;
  bool _isHost = false;
  Timer? _metricsTimer;

  /// Stream of connection state changes
  Stream<WebRTCConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Stream of streaming metrics
  Stream<StreamingMetrics> get metricsStream => _metricsController.stream;

  /// Current connection state
  WebRTCConnectionState _connectionState = WebRTCConnectionState.disconnected;
  WebRTCConnectionState get connectionState => _connectionState;

  /// Whether we are the host (screen sharer)
  bool get isHost => _isHost;

  /// Current streaming quality
  StreamingQuality get quality => _quality;

  WebRTCService(this._signalingService);

  /// Whether to force relay mode (for mobile hotspots with AP isolation)
  bool _forceRelayMode = false;

  /// Set force relay mode (must be called before createPeerConnection)
  void setForceRelayMode(bool forceRelay) {
    _forceRelayMode = forceRelay;
    AppLogger.info(
      'Force relay mode: ${forceRelay ? 'enabled' : 'disabled'}',
      _module,
    );
  }

  /// Get WebRTC configuration with STUN and TURN servers
  /// TURN servers are essential for mobile hotspots which have AP isolation enabled
  Map<String, dynamic> get _configuration {
    AppLogger.info('Creating ICE config: forceRelay=$_forceRelayMode', _module);

    return {
      'iceServers': <Map<String, dynamic>>[
        // Google STUN servers (free, reliable)
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun3.l.google.com:19302'},
        {'urls': 'stun:stun4.l.google.com:19302'},

        // Twilio STUN (generally reliable)
        {'urls': 'stun:global.stun.twilio.com:3478'},

        // Metered.ca TURN servers (free tier - more reliable)
        // These allow relay of media when direct P2P is blocked
        {
          'urls': [
            'turn:a.relay.metered.ca:80',
            'turn:a.relay.metered.ca:80?transport=tcp',
            'turn:a.relay.metered.ca:443',
            'turn:a.relay.metered.ca:443?transport=tcp',
          ],
          'username': 'e8dd65c92e326d5e0dff6a9d',
          'credential': 'YhNjCYdUoYCiUWbd',
        },
      ],
      'sdpSemantics': 'unified-plan',
      // 'relay' forces TURN-only connections (slower but works with AP isolation)
      // 'all' allows both direct and relay connections (preferred when possible)
      'iceTransportPolicy': _forceRelayMode ? 'relay' : 'all',
    };
  }

  /// Initialize the WebRTC service
  Future<void> initialize(
    String deviceId, {
    bool forceRelayMode = false,
  }) async {
    _localDeviceId = deviceId;
    _forceRelayMode = forceRelayMode;

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    // Listen for signaling messages
    _signalingService.messageStream.listen(_handleSignalingMessage);

    AppLogger.info(
      'WebRTC service initialized (forceRelay: $forceRelayMode)',
      _module,
    );
  }

  /// Start sharing screen (as host)
  Future<void> startScreenShare() async {
    _isHost = true;
    _updateConnectionState(WebRTCConnectionState.connecting);

    try {
      // Create peer connection
      await _createPeerConnection();

      // Start screen capture
      _localStream = await _getScreenStream();

      if (_localStream != null) {
        localRenderer.srcObject = _localStream;

        // Add tracks to peer connection and set quality
        for (final track in _localStream!.getTracks()) {
          final sender = await _peerConnection?.addTrack(track, _localStream!);
          if (sender != null && track.kind == 'video') {
            await _setVideoQuality(sender);
          }
        }

        _updateConnectionState(WebRTCConnectionState.ready);
        _startMetricsCollection();

        AppLogger.info('Screen sharing started', _module);
      } else {
        throw Exception('Failed to get screen stream');
      }
    } catch (e, stack) {
      AppLogger.error('Failed to start screen share', e, stack, _module);
      _updateConnectionState(WebRTCConnectionState.error);
      rethrow;
    }
  }

  /// Get screen capture stream
  Future<MediaStream?> _getScreenStream() async {
    try {
      // On Android 14+, we MUST request media projection permission BEFORE
      // starting the foreground service with mediaProjection type.
      // The native side handles requesting permission and starting the service.
      if (Platform.isAndroid) {
        try {
          const channel = MethodChannel('com.wifimirror/service');
          await channel.invokeMethod('startForegroundService');
          AppLogger.info('Started Android foreground service', _module);
        } on PlatformException catch (e) {
          // Handle permission denial from user
          if (e.code == 'PERMISSION_DENIED') {
            AppLogger.warning('User denied screen capture permission', _module);
            rethrow; // Propagate so the UI can show appropriate message
          }
          AppLogger.error(
            'Failed to start foreground service',
            e,
            null,
            _module,
          );
          rethrow;
        } catch (e) {
          AppLogger.error(
            'Failed to start foreground service',
            e,
            null,
            _module,
          );
          rethrow;
        }
      }

      // Use display media for screen capture
      final stream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'width': {'ideal': _quality.width},
          'height': {'ideal': _quality.height},
          'frameRate': {'ideal': _quality.frameRate},
        },
        'audio': false,
      });

      AppLogger.info('Got screen stream: ${stream.id}', _module);
      return stream;
    } catch (e) {
      AppLogger.error('Failed to get screen stream', e, null, _module);

      // If we failed, try to stop the service we might have started
      if (Platform.isAndroid) {
        try {
          const channel = MethodChannel('com.wifimirror/service');
          await channel.invokeMethod('stopForegroundService');
        } catch (_) {}
      }

      // Fallback: try getUserMedia (for testing)
      try {
        final stream = await navigator.mediaDevices.getUserMedia({
          'video': {
            'width': {'ideal': _quality.width},
            'height': {'ideal': _quality.height},
            'frameRate': {'ideal': _quality.frameRate},
          },
          'audio': false,
        });
        AppLogger.info('Using camera as fallback for screen share', _module);
        return stream;
      } catch (e2) {
        AppLogger.error('Fallback also failed', e2, null, _module);
        return null;
      }
    }
  }

  /// Connect to a screen share session (as viewer)
  Future<void> connectToHost(String hostDeviceId) async {
    _isHost = false;
    _remoteDeviceId = hostDeviceId;
    _updateConnectionState(WebRTCConnectionState.connecting);

    try {
      await _createPeerConnection();
      AppLogger.info('Connecting to host: $hostDeviceId', _module);
    } catch (e, stack) {
      AppLogger.error('Failed to connect to host', e, stack, _module);
      _updateConnectionState(WebRTCConnectionState.error);
      rethrow;
    }
  }

  /// Create WebRTC peer connection
  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_configuration);

    // Set up event handlers
    _peerConnection!.onIceCandidate = _handleIceCandidate;
    _peerConnection!.onIceConnectionState = _handleIceConnectionState;
    _peerConnection!.onConnectionState = _handleConnectionState;
    _peerConnection!.onTrack = _handleTrack;
    _peerConnection!.onRenegotiationNeeded = _handleRenegotiationNeeded;

    // ICE gathering state handler
    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      AppLogger.info('ICE gathering state: $state', _module);
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        AppLogger.info('ICE gathering complete!', _module);
      }
    };

    AppLogger.info('Peer connection created with all handlers', _module);
  }

  /// Handle ICE candidate
  void _handleIceCandidate(RTCIceCandidate candidate) {
    // Parse candidate type for logging
    final candidateStr = candidate.candidate ?? '';
    String candidateType = 'unknown';
    if (candidateStr.contains('typ host')) {
      candidateType = 'host';
    } else if (candidateStr.contains('typ srflx')) {
      candidateType = 'srflx (STUN)';
    } else if (candidateStr.contains('typ relay')) {
      candidateType = 'relay (TURN)';
    } else if (candidateStr.contains('typ prflx')) {
      candidateType = 'prflx';
    }

    AppLogger.info('ICE candidate generated: type=$candidateType', _module);

    if (_remoteDeviceId != null) {
      AppLogger.info('Sending ICE candidate to: $_remoteDeviceId', _module);
      _signalingService.sendMessage(
        SignalingMessage.iceCandidate(
          senderId: _localDeviceId!,
          targetId: _remoteDeviceId!,
          candidate: candidate.toMap(),
        ),
      );
    } else if (_isHost) {
      // Broadcast to all viewers
      AppLogger.info('Broadcasting ICE candidate (host mode)', _module);
      _signalingService.sendMessage(
        SignalingMessage(
          type: SignalingType.iceCandidate,
          senderId: _localDeviceId!,
          payload: candidate.toMap(),
        ),
      );
    } else {
      AppLogger.warning(
        'ICE candidate generated but no remote device ID set!',
        _module,
      );
    }
  }

  /// Handle ICE connection state changes
  void _handleIceConnectionState(RTCIceConnectionState state) {
    AppLogger.info('ICE connection state changed: $state', _module);

    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateNew:
        AppLogger.debug('ICE: New - Starting ICE negotiation', _module);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
        AppLogger.debug('ICE: Checking - Validating candidates...', _module);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
        AppLogger.info(
          'ICE: Connected! Peer-to-peer link established',
          _module,
        );
        _updateConnectionState(WebRTCConnectionState.connected);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        AppLogger.info('ICE: Completed - All candidates processed', _module);
        _updateConnectionState(WebRTCConnectionState.connected);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        AppLogger.warning(
          'ICE: Disconnected - Connection lost, may reconnect',
          _module,
        );
        _updateConnectionState(WebRTCConnectionState.reconnecting);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        AppLogger.error(
          'ICE: FAILED - Could not establish connection. '
          'This often happens with mobile hotspots due to AP isolation. '
          'Try enabling "Force Relay Mode" in Settings.',
          null,
          null,
          _module,
        );
        _updateConnectionState(WebRTCConnectionState.error);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        AppLogger.info('ICE: Closed - Connection terminated', _module);
        _updateConnectionState(WebRTCConnectionState.disconnected);
        break;
      default:
        AppLogger.debug('ICE: Unknown state - $state', _module);
        break;
    }
  }

  /// Handle peer connection state changes
  void _handleConnectionState(RTCPeerConnectionState state) {
    AppLogger.info('Peer connection state: $state', _module);

    // Also update our connection state based on peer connection state
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _updateConnectionState(WebRTCConnectionState.connected);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _updateConnectionState(WebRTCConnectionState.error);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _updateConnectionState(WebRTCConnectionState.disconnected);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _updateConnectionState(WebRTCConnectionState.reconnecting);
        break;
      default:
        break;
    }
  }

  /// Handle incoming track (remote stream)
  void _handleTrack(RTCTrackEvent event) {
    AppLogger.info(
      'Track event received: track.kind=${event.track.kind}, streams=${event.streams.length}',
      _module,
    );

    if (event.streams.isNotEmpty) {
      _remoteStream = event.streams[0];
      remoteRenderer.srcObject = _remoteStream;
      _startMetricsCollection();

      AppLogger.info(
        'Remote stream attached to renderer: streamId=${_remoteStream?.id}, tracks=${_remoteStream?.getTracks().length}',
        _module,
      );

      // Log video track details
      final videoTracks = _remoteStream?.getVideoTracks();
      if (videoTracks != null && videoTracks.isNotEmpty) {
        AppLogger.info(
          'Video track: id=${videoTracks.first.id}, enabled=${videoTracks.first.enabled}',
          _module,
        );
      } else {
        AppLogger.warning('No video tracks in remote stream!', _module);
      }
    } else {
      AppLogger.warning('Track event received but no streams!', _module);
    }
  }

  /// Handle renegotiation needed
  Future<void> _handleRenegotiationNeeded() async {
    if (_isHost && _peerConnection != null) {
      AppLogger.debug('Renegotiation needed', _module);
      // Will be triggered when we need to send a new offer
    }
  }

  /// Handle incoming signaling message
  Future<void> _handleSignalingMessage(SignalingMessage message) async {
    // Ignore messages not for us
    if (message.targetId != null &&
        message.targetId != _localDeviceId &&
        message.targetId != 'server') {
      return;
    }

    switch (message.type) {
      case SignalingType.joinRequest:
        if (_isHost) {
          await _handleViewerJoin(message.senderId);
        }
        break;

      case SignalingType.offer:
        await _handleOffer(message);
        break;

      case SignalingType.answer:
        await _handleAnswer(message);
        break;

      case SignalingType.iceCandidate:
        await _handleRemoteIceCandidate(message);
        break;

      case SignalingType.disconnect:
        if (message.senderId == _remoteDeviceId) {
          await stop();
        }
        break;

      default:
        break;
    }
  }

  /// Handle viewer joining (host side)
  Future<void> _handleViewerJoin(String viewerId) async {
    // If we're already connecting/connected to this viewer, ignore duplicate requests
    if (_remoteDeviceId == viewerId &&
        (_connectionState == WebRTCConnectionState.connecting ||
            _connectionState == WebRTCConnectionState.connected ||
            _connectionState == WebRTCConnectionState.ready)) {
      AppLogger.warning(
        'Ignoring duplicate join request from $viewerId',
        _module,
      );
      return;
    }

    _remoteDeviceId = viewerId;

    // Send join response
    _signalingService.sendMessage(
      SignalingMessage.joinResponse(
        senderId: _localDeviceId!,
        targetId: viewerId,
        accepted: true,
      ),
    );

    // Create and send offer
    await _createAndSendOffer(viewerId);

    AppLogger.info('Viewer joined: $viewerId', _module);
  }

  /// Create and send SDP offer
  Future<void> _createAndSendOffer(String targetId) async {
    if (_peerConnection == null) return;

    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': true,
        'offerToReceiveAudio': false,
      });

      await _peerConnection!.setLocalDescription(offer);

      _signalingService.sendMessage(
        SignalingMessage.offer(
          senderId: _localDeviceId!,
          targetId: targetId,
          sdp: offer.toMap(),
        ),
      );

      AppLogger.info('Sent offer to: $targetId', _module);
    } catch (e, stack) {
      AppLogger.error('Failed to create offer', e, stack, _module);
    }
  }

  /// Handle incoming offer (viewer side)
  Future<void> _handleOffer(SignalingMessage message) async {
    if (_peerConnection == null) return;

    try {
      _remoteDeviceId = message.senderId;

      final sdp = RTCSessionDescription(
        message.payload['sdp'] as String,
        message.payload['type'] as String,
      );

      await _peerConnection!.setRemoteDescription(sdp);

      // Create and send answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      _signalingService.sendMessage(
        SignalingMessage.answer(
          senderId: _localDeviceId!,
          targetId: message.senderId,
          sdp: answer.toMap(),
        ),
      );

      AppLogger.info('Sent answer to: ${message.senderId}', _module);
    } catch (e, stack) {
      AppLogger.error('Failed to handle offer', e, stack, _module);
    }
  }

  /// Handle incoming answer (host side)
  Future<void> _handleAnswer(SignalingMessage message) async {
    if (_peerConnection == null) return;

    try {
      final sdp = RTCSessionDescription(
        message.payload['sdp'] as String,
        message.payload['type'] as String,
      );

      await _peerConnection!.setRemoteDescription(sdp);

      AppLogger.info(
        'Remote description set from: ${message.senderId}',
        _module,
      );
    } catch (e, stack) {
      AppLogger.error('Failed to handle answer', e, stack, _module);
    }
  }

  /// Handle incoming ICE candidate
  Future<void> _handleRemoteIceCandidate(SignalingMessage message) async {
    if (_peerConnection == null) {
      AppLogger.warning(
        'Received ICE candidate but peer connection is null!',
        _module,
      );
      return;
    }

    try {
      final candidateMap = message.payload as Map<String, dynamic>;
      final candidateStr = candidateMap['candidate'] as String? ?? '';

      // Parse candidate type for logging
      String candidateType = 'unknown';
      if (candidateStr.contains('typ host')) {
        candidateType = 'host';
      } else if (candidateStr.contains('typ srflx')) {
        candidateType = 'srflx (STUN)';
      } else if (candidateStr.contains('typ relay')) {
        candidateType = 'relay (TURN)';
      } else if (candidateStr.contains('typ prflx')) {
        candidateType = 'prflx';
      }

      final candidate = RTCIceCandidate(
        candidateMap['candidate'] as String?,
        candidateMap['sdpMid'] as String?,
        candidateMap['sdpMLineIndex'] as int?,
      );

      await _peerConnection!.addCandidate(candidate);
      AppLogger.info(
        'Added remote ICE candidate: type=$candidateType, from=${message.senderId}',
        _module,
      );
    } catch (e) {
      AppLogger.error('Failed to add ICE candidate', e, null, _module);
    }
  }

  /// Update connection state
  void _updateConnectionState(WebRTCConnectionState state) {
    _connectionState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  /// Start collecting streaming metrics
  void _startMetricsCollection() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _collectMetrics();
    });
  }

  /// Collect and emit streaming metrics
  Future<void> _collectMetrics() async {
    if (_peerConnection == null) return;

    try {
      final stats = await _peerConnection!.getStats();

      double fps = 0;
      int latency = 0;
      int bitrate = 0;
      double packetLoss = 0;
      int jitter = 0;

      for (final report in stats) {
        final values = report.values;

        if (report.type == 'inbound-rtp' || report.type == 'outbound-rtp') {
          fps = (values['framesPerSecond'] as num?)?.toDouble() ?? fps;
          bitrate =
              (values['bytesReceived'] as num?)?.toInt() ??
              (values['bytesSent'] as num?)?.toInt() ??
              bitrate;
        }

        if (report.type == 'candidate-pair' && values['state'] == 'succeeded') {
          latency = ((values['currentRoundTripTime'] as num?) ?? 0 * 1000)
              .toInt();
        }

        if (report.type == 'remote-inbound-rtp') {
          packetLoss = (values['packetsLost'] as num?)?.toDouble() ?? 0;
          jitter = ((values['jitter'] as num?) ?? 0 * 1000).toInt();
        }
      }

      final metrics = StreamingMetrics(
        fps: fps,
        latencyMs: latency,
        bitrate: bitrate,
        packetLoss: packetLoss,
        jitterMs: jitter,
      );

      if (!_metricsController.isClosed) {
        _metricsController.add(metrics);
      }
    } catch (e) {
      AppLogger.error('Failed to collect metrics', e, null, _module);
    }
  }

  /// Change streaming quality
  Future<void> setQuality(StreamingQuality newQuality) async {
    if (_quality == newQuality) return;

    _quality = newQuality;
    AppLogger.info('Quality changed to: ${newQuality.displayName}', _module);

    // Update bitrate for active video senders
    if (_peerConnection != null) {
      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await _setVideoQuality(sender);
        }
      }
    }
  }

  /// Set video quality parameters on the sender
  Future<void> _setVideoQuality(RTCRtpSender sender) async {
    try {
      final parameters = sender.parameters;
      if (parameters.encodings != null && parameters.encodings!.isNotEmpty) {
        for (final encoding in parameters.encodings!) {
          encoding.maxBitrate = _quality.bitrate;
          // Set a reasonable floor to prevent extreme quality drops
          // encoding.minBitrate = (_quality.bitrate * 0.1).toInt();
        }
        await sender.setParameters(parameters);
        AppLogger.info('Set video bitrate to ${_quality.bitrate} bps', _module);
      }
    } catch (e) {
      AppLogger.error('Failed to set video quality', e, null, _module);
    }
  }

  /// Stop screen sharing / viewing
  Future<void> stop() async {
    _metricsTimer?.cancel();

    // Stop local stream
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    // Stop remote stream
    if (_remoteStream != null) {
      await _remoteStream!.dispose();
      _remoteStream = null;
    }

    // Close peer connection
    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    _updateConnectionState(WebRTCConnectionState.disconnected);
    _remoteDeviceId = null;

    // Stop foreground service on Android
    if (Platform.isAndroid && _isHost) {
      try {
        const channel = MethodChannel('com.wifimirror/service');
        await channel.invokeMethod('stopForegroundService');
      } catch (e) {
        AppLogger.error('Failed to stop foreground service', e, null, _module);
      }
    }

    AppLogger.info('WebRTC stopped', _module);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
    await _connectionStateController.close();
    await _metricsController.close();
    AppLogger.info('WebRTC service disposed', _module);
  }
}

/// WebRTC Connection states (named to avoid Flutter's ConnectionState)
enum WebRTCConnectionState {
  disconnected,
  connecting,
  ready,
  connected,
  reconnecting,
  error,
}
