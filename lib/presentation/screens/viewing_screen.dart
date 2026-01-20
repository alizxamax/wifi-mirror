import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/models.dart';
import '../../data/services/webrtc_service.dart' show WebRTCConnectionState;
import '../../providers/providers.dart';
import '../widgets/widgets.dart';

// Conditional import for web fullscreen functionality
import 'viewing_screen_web.dart'
    if (dart.library.io) 'viewing_screen_native.dart'
    as fullscreen_helper;

/// Screen displayed when viewing another device's screen
class ViewingScreen extends ConsumerStatefulWidget {
  final NetworkDevice hostDevice;

  const ViewingScreen({super.key, required this.hostDevice});

  @override
  ConsumerState<ViewingScreen> createState() => _ViewingScreenState();
}

class _ViewingScreenState extends ConsumerState<ViewingScreen> {
  bool _isFullscreen = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    // Hide controls after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  /// Check if fullscreen button should be shown
  bool _shouldShowFullscreenButton(BuildContext context) {
    if (kIsWeb) {
      return true;
    }
    return !context.isLargeDesktop;
  }

  void _toggleFullscreen() async {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });

    if (kIsWeb) {
      fullscreen_helper.toggleFullscreen(_isFullscreen);
    } else {
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  Future<void> _disconnect() async {
    if (_isFullscreen) {
      if (kIsWeb) {
        fullscreen_helper.toggleFullscreen(false);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    }

    await ref.read(screenSharingControllerProvider).disconnect();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final webrtcService = ref.watch(webrtcServiceProvider);
    final connectionState = ref.watch(connectionStateProvider);
    final metricsAsync = ref.watch(streamingMetricsProvider);
    final showFullscreenBtn = _shouldShowFullscreenButton(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          final isLargerScreen = kIsWeb ? _isFullscreen : isWide;

          return GestureDetector(
            onTap: _toggleControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Remote video content
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: kIsWeb
                          ? double.infinity
                          : (isLargerScreen
                                ? constraints.maxWidth * 0.9
                                : double.infinity),
                      maxHeight: kIsWeb
                          ? double.infinity
                          : (isLargerScreen
                                ? constraints.maxHeight * 0.85
                                : double.infinity),
                    ),
                    child: kIsWeb
                        ? _buildVideoContent(
                            connectionState,
                            webrtcService,
                            theme,
                            isLargerScreen,
                          )
                        : AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: isLargerScreen
                                  ? BorderRadius.circular(16)
                                  : BorderRadius.zero,
                              child: _buildVideoContent(
                                connectionState,
                                webrtcService,
                                theme,
                                isLargerScreen,
                              ),
                            ),
                          ),
                  ),
                ),

                // Controls overlay
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: _buildControlsOverlay(
                    theme,
                    metricsAsync,
                    isLargerScreen,
                    showFullscreenBtn,
                  ),
                ),

                // Persistent connection indicator (only when controls hidden)
                if (!_showControls)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const StatusIndicator(
                              status: StatusType.viewing,
                              size: 8,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.hostDevice.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Builds the video content widget
  Widget _buildVideoContent(
    AsyncValue<WebRTCConnectionState> connectionState,
    dynamic webrtcService,
    ThemeData theme,
    bool isLargeScreen,
  ) {
    return connectionState.when(
      data: (state) {
        if (state == WebRTCConnectionState.connected) {
          return Container(
            width: kIsWeb ? double.infinity : null,
            height: kIsWeb ? double.infinity : null,
            decoration: (!kIsWeb && isLargeScreen)
                ? BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  )
                : null,
            child: RTCVideoView(
              webrtcService.remoteRenderer,
              mirror: false,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ).animate().fadeIn(duration: 500.ms),
          );
        }
        return _buildConnectingState(theme, isLargeScreen);
      },
      loading: () => _buildConnectingState(theme, isLargeScreen),
      error: (error, _) => _buildErrorState(theme, error, isLargeScreen),
    );
  }

  Widget _buildControlsOverlay(
    ThemeData theme,
    AsyncValue metricsAsync,
    bool isLargeScreen,
    bool showFullscreenBtn,
  ) {
    return SafeArea(
      child: Stack(
        children: [
          // Top Left: Back + Info
          Positioned(
            top: 16,
            left: 16,
            child: Row(
              children: [
                _buildCircleButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: _disconnect,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.hostDevice.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          const Shadow(color: Colors.black45, blurRadius: 4),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.hostDevice.deviceType.displayName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Top Right: The Requested Card (FPS, Fullscreen, Disconnect)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // FPS / Quality
                  metricsAsync.when(
                    data: (metrics) =>
                        QualityIndicator(metrics: metrics, compact: true),
                    loading: () => const QualityIndicator(compact: true),
                    error: (err, stack) =>
                        const QualityIndicator(compact: true),
                  ),

                  // Divider
                  Container(
                    width: 1,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: Colors.white.withValues(alpha: 0.2),
                  ),

                  // Fullscreen Button
                  if (showFullscreenBtn) ...[
                    _buildIconButton(
                      icon: _isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      tooltip: _isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                      onTap: _toggleFullscreen,
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Disconnect Button (Destructive)
                  _buildIconButton(
                    icon: Icons.call_end_rounded,
                    tooltip: 'Disconnect',
                    onTap: _disconnect,
                    color: AppTheme.error,
                    backgroundColor: AppTheme.error.withValues(alpha: 0.2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    Color? backgroundColor,
    double size = 40,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: color ?? Colors.white),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color? color,
    Color? backgroundColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: color ?? Colors.white),
        ),
      ),
    );
  }

  Widget _buildConnectingState(ThemeData theme, bool isLargeScreen) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
                width: isLargeScreen ? 80 : 60,
                height: isLargeScreen ? 80 : 60,
                child: const CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                duration: 1500.ms,
                color: AppTheme.success.withValues(alpha: 0.3),
              ),
          const SizedBox(height: 24),
          Text(
            'Connecting to ${widget.hostDevice.name}...',
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, Object error, bool isLargeScreen) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.error),
          const SizedBox(height: 16),
          Text(
            'Connection Failed',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Go Back'),
          ),
        ],
      ),
    );
  }
}
