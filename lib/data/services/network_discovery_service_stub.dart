import '../models/models.dart';

/// Stub implementation for web platform
///
/// On web, mDNS discovery is not available. This stub provides
/// no-op implementations that gracefully handle the missing functionality.
class NetworkDiscoveryPlatform {
  // ignore: avoid_unused_constructor_parameters
  NetworkDiscoveryPlatform(dynamic service);

  /// Get device info - returns basic info for web
  Future<Map<String, String?>> getDeviceInfo() async {
    return {
      'name': 'Web Browser',
      'type': 'unknown',
      'id': 'web-${DateTime.now().millisecondsSinceEpoch}',
    };
  }

  /// Start broadcast - not supported on web
  Future<void> startBroadcast({
    required String serviceName,
    required String serviceType,
    required int port,
    required Map<String, String> attributes,
  }) async {
    // Not supported on web
  }

  /// Stop broadcast - not supported on web
  Future<void> stopBroadcast() async {
    // Not supported on web
  }

  /// Start discovery - not supported on web
  Future<void> startDiscovery({
    required String serviceType,
    required String? localDeviceId,
    required void Function(NetworkDevice) onDeviceFound,
    required void Function(String) onDeviceLost,
  }) async {
    // Not supported on web
  }

  /// Stop discovery - not supported on web
  Future<void> stopDiscovery() async {
    // Not supported on web
  }
}
