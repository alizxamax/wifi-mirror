import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// Utility class for platform detection and capability checks
class PlatformUtils {
  PlatformUtils._();

  /// Whether the app is running on web
  static bool get isWeb => kIsWeb;

  /// Whether network discovery (mDNS) is supported
  static bool get supportsNetworkDiscovery => !kIsWeb;

  /// Whether we can run a signaling server (requires dart:io sockets)
  static bool get supportsSignalingServer => !kIsWeb;

  /// Whether screen sharing is supported
  /// Web browsers cannot share their screen to other devices,
  /// but they can view shared screens
  static bool get supportsScreenSharing => !kIsWeb;

  /// Get the current platform name
  static String get platformName {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// Get device type enumeration for web
  static String get webDeviceType => 'web';
}
