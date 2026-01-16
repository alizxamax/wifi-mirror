import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/models.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

// Conditional imports for platform-specific code
import 'network_discovery_service_stub.dart'
    if (dart.library.io) 'network_discovery_service_io.dart'
    as platform_impl;

/// Service for discovering and advertising devices on the local network using mDNS
///
/// On web platform, mDNS discovery is not supported. Users must manually connect
/// by entering the host device's IP address and port.
class NetworkDiscoveryService {
  static const String _module = 'NetworkDiscovery';

  final StreamController<List<NetworkDevice>> _devicesController =
      StreamController<List<NetworkDevice>>.broadcast();

  final Map<String, NetworkDevice> _discoveredDevices = {};

  String? _localDeviceId;
  String? _localDeviceName;
  DeviceType? _localDeviceType;
  bool _isSharing = false;
  bool _isBroadcasting = false;
  bool _isDiscovering = false;

  // Platform-specific implementation
  late final platform_impl.NetworkDiscoveryPlatform _platformImpl;

  NetworkDiscoveryService() {
    _platformImpl = platform_impl.NetworkDiscoveryPlatform(this);
  }

  /// Stream of discovered devices
  Stream<List<NetworkDevice>> get devicesStream => _devicesController.stream;

  /// Current list of discovered devices
  List<NetworkDevice> get discoveredDevices =>
      _discoveredDevices.values.toList();

  /// Whether service discovery is running
  bool get isDiscovering => _isDiscovering;

  /// Whether we are broadcasting our service
  bool get isBroadcasting => _isBroadcasting;

  /// Whether network discovery is supported on this platform
  bool get isDiscoverySupported => !kIsWeb;

  /// Initialize the service
  Future<void> initialize() async {
    AppLogger.info('Initializing network discovery service', _module);
    await _initializeDeviceInfo();
  }

  /// Get device information
  Future<void> _initializeDeviceInfo() async {
    if (kIsWeb) {
      // Web platform: Use basic info
      _localDeviceName = 'Web Browser';
      _localDeviceType = DeviceType.unknown;
      _localDeviceId = 'web-${DateTime.now().millisecondsSinceEpoch}';
      AppLogger.info('Web device initialized: $_localDeviceName', _module);
      return;
    }

    // Native platforms: Get detailed device info
    try {
      final info = await _platformImpl.getDeviceInfo();
      _localDeviceName = info['name'];
      _localDeviceType = DeviceType.fromString(info['type'] ?? 'unknown');
      _localDeviceId = info['id'];

      AppLogger.info(
        'Device info: $_localDeviceName (${_localDeviceType?.name})',
        _module,
      );
    } catch (e) {
      AppLogger.error('Failed to get device info', e, null, _module);
      _localDeviceName = 'Unknown Device';
      _localDeviceType = DeviceType.unknown;
      _localDeviceId = 'unknown-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Start broadcasting our service on the network
  Future<void> startBroadcast({bool isSharing = false}) async {
    if (kIsWeb) {
      AppLogger.warning('Broadcasting not supported on web', _module);
      return;
    }

    if (_isBroadcasting) {
      AppLogger.warning('Broadcast already running', _module);
      return;
    }

    _isSharing = isSharing;

    try {
      await _platformImpl.startBroadcast(
        serviceName: _localDeviceName ?? 'WiFi Mirror Device',
        serviceType: AppConstants.serviceType,
        port: AppConstants.servicePort,
        attributes: {
          'device_id': _localDeviceId ?? '',
          'device_type': _localDeviceType?.name ?? 'unknown',
          'is_sharing': _isSharing.toString(),
          'version': AppConstants.appVersion,
        },
      );

      _isBroadcasting = true;
      AppLogger.info(
        'Started broadcasting service: $_localDeviceName',
        _module,
      );
    } catch (e, stack) {
      AppLogger.error('Failed to start broadcast', e, stack, _module);
      _isBroadcasting = false;
      rethrow;
    }
  }

  /// Stop broadcasting our service
  Future<void> stopBroadcast() async {
    if (kIsWeb || !_isBroadcasting) return;

    try {
      await _platformImpl.stopBroadcast();
      _isBroadcasting = false;
      AppLogger.info('Stopped broadcasting', _module);
    } catch (e, stack) {
      AppLogger.error('Failed to stop broadcast', e, stack, _module);
    }
  }

  /// Update broadcast status (e.g., when sharing state changes)
  Future<void> updateBroadcast({required bool isSharing}) async {
    if (_isSharing == isSharing) return;

    _isSharing = isSharing;
    if (_isBroadcasting) {
      // Restart broadcast with new attributes
      await stopBroadcast();
      await startBroadcast(isSharing: isSharing);
    }
  }

  /// Start discovering devices on the network
  Future<void> startDiscovery() async {
    if (kIsWeb) {
      AppLogger.warning(
        'Network discovery not supported on web. Use manual connection.',
        _module,
      );
      // Mark as discovering briefly then stop (for UI feedback)
      _isDiscovering = true;
      _notifyDevicesChanged();
      await Future.delayed(const Duration(milliseconds: 500));
      _isDiscovering = false;
      _notifyDevicesChanged();
      return;
    }

    if (_isDiscovering) {
      AppLogger.warning('Discovery already running', _module);
      return;
    }

    try {
      _discoveredDevices.clear();

      await _platformImpl.startDiscovery(
        serviceType: AppConstants.serviceType,
        localDeviceId: _localDeviceId,
        onDeviceFound: _handleDeviceFound,
        onDeviceLost: _handleDeviceLost,
      );

      _isDiscovering = true;
      AppLogger.info('Started device discovery', _module);
    } catch (e, stack) {
      AppLogger.error('Failed to start discovery', e, stack, _module);
      _isDiscovering = false;
      rethrow;
    }
  }

  /// Handle when a device is found
  void _handleDeviceFound(NetworkDevice device) {
    // Skip our own device
    if (device.id == _localDeviceId) {
      AppLogger.debug('Ignoring own device', _module);
      return;
    }

    _discoveredDevices[device.id] = device;
    _notifyDevicesChanged();

    AppLogger.info(
      'Found device: ${device.name} (${device.ipAddress}:${device.port})',
      _module,
    );
  }

  /// Handle when a device is lost
  void _handleDeviceLost(String deviceId) {
    if (_discoveredDevices.containsKey(deviceId)) {
      _discoveredDevices.remove(deviceId);
      _notifyDevicesChanged();
      AppLogger.info('Device lost: $deviceId', _module);
    }
  }

  /// Stop discovering devices
  Future<void> stopDiscovery() async {
    if (kIsWeb || !_isDiscovering) return;

    try {
      await _platformImpl.stopDiscovery();
      _isDiscovering = false;
      AppLogger.info('Stopped discovery', _module);
    } catch (e, stack) {
      AppLogger.error('Failed to stop discovery', e, stack, _module);
    }
  }

  /// Add a manually connected device
  void addManualDevice(NetworkDevice device) {
    _discoveredDevices[device.id] = device;
    _notifyDevicesChanged();
    AppLogger.info(
      'Manually added device: ${device.name} (${device.ipAddress}:${device.port})',
      _module,
    );
  }

  /// Remove a manually connected device
  void removeDevice(String deviceId) {
    if (_discoveredDevices.containsKey(deviceId)) {
      _discoveredDevices.remove(deviceId);
      _notifyDevicesChanged();
    }
  }

  /// Notify listeners of device changes
  void _notifyDevicesChanged() {
    if (!_devicesController.isClosed) {
      _devicesController.add(discoveredDevices);
    }
  }

  /// Get local device info
  NetworkDevice? getLocalDevice() {
    if (_localDeviceId == null) return null;

    return NetworkDevice(
      id: _localDeviceId!,
      name: _localDeviceName ?? 'This Device',
      ipAddress: '', // Will be filled when broadcasting
      port: AppConstants.servicePort,
      deviceType: _localDeviceType ?? DeviceType.unknown,
      isSharing: _isSharing,
    );
  }

  /// Clean up resources
  Future<void> dispose() async {
    await stopDiscovery();
    await stopBroadcast();
    await _devicesController.close();
    AppLogger.info('Disposed network discovery service', _module);
  }
}
