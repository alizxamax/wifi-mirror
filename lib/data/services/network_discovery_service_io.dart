import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/models.dart';

/// Native platform implementation for network discovery using mDNS
class NetworkDiscoveryPlatform {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  // ignore: avoid_unused_constructor_parameters
  NetworkDiscoveryPlatform(dynamic service);

  /// Get device info from device_info_plus
  Future<Map<String, String?>> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return {'name': info.model, 'type': 'android', 'id': info.id};
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return {'name': info.name, 'type': 'ios', 'id': info.identifierForVendor};
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      return {
        'name': info.computerName,
        'type': 'macos',
        'id': info.systemGUID,
      };
    } else if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      return {
        'name': info.computerName,
        'type': 'windows',
        'id': info.deviceId,
      };
    } else if (Platform.isLinux) {
      final info = await deviceInfo.linuxInfo;
      return {'name': info.prettyName, 'type': 'linux', 'id': info.machineId};
    }

    return {
      'name': 'Unknown Device',
      'type': 'unknown',
      'id': 'unknown-${DateTime.now().millisecondsSinceEpoch}',
    };
  }

  /// Start broadcasting service using Bonsoir mDNS
  Future<void> startBroadcast({
    required String serviceName,
    required String serviceType,
    required int port,
    required Map<String, String> attributes,
  }) async {
    final service = BonsoirService(
      name: serviceName,
      type: serviceType,
      port: port,
      attributes: attributes,
    );

    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();
  }

  /// Stop broadcasting
  Future<void> stopBroadcast() async {
    if (_broadcast != null) {
      await _broadcast!.stop();
      _broadcast = null;
    }
  }

  /// Start discovering devices using Bonsoir mDNS
  Future<void> startDiscovery({
    required String serviceType,
    required String? localDeviceId,
    required void Function(NetworkDevice) onDeviceFound,
    required void Function(String) onDeviceLost,
  }) async {
    _discovery = BonsoirDiscovery(type: serviceType);
    await _discovery!.initialize();

    _discovery!.eventStream!.listen((event) {
      _handleDiscoveryEvent(event, localDeviceId, onDeviceFound, onDeviceLost);
    });

    await _discovery!.start();
  }

  /// Handle discovery events
  void _handleDiscoveryEvent(
    BonsoirDiscoveryEvent event,
    String? localDeviceId,
    void Function(NetworkDevice) onDeviceFound,
    void Function(String) onDeviceLost,
  ) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        // Resolve the service to get IP address
        event.service.resolve(_discovery!.serviceResolver);
        break;

      case BonsoirDiscoveryServiceResolvedEvent():
        _handleServiceResolved(event.service, localDeviceId, onDeviceFound);
        break;

      case BonsoirDiscoveryServiceUpdatedEvent():
        _handleServiceResolved(event.service, localDeviceId, onDeviceFound);
        break;

      case BonsoirDiscoveryServiceLostEvent():
        final deviceId = event.service.attributes['device_id'];
        if (deviceId != null) {
          onDeviceLost(deviceId);
        }
        break;

      default:
        break;
    }
  }

  /// Handle when a service is resolved
  void _handleServiceResolved(
    BonsoirService service,
    String? localDeviceId,
    void Function(NetworkDevice) onDeviceFound,
  ) {
    // Skip our own device
    final deviceId = service.attributes['device_id'];
    if (deviceId == localDeviceId) {
      return;
    }

    final String ipAddress = service.host ?? '';

    final device = NetworkDevice.fromServiceInfo(
      name: service.name,
      ip: ipAddress,
      port: service.port,
      txtRecords: service.attributes,
    );

    onDeviceFound(device);
  }

  /// Stop discovery
  Future<void> stopDiscovery() async {
    if (_discovery != null) {
      await _discovery!.stop();
      _discovery = null;
    }
  }
}
