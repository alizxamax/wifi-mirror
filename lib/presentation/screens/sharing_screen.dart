import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/providers.dart';
import '../widgets/widgets.dart';

/// Screen displayed when sharing your screen - Revamped for responsiveness & UI/UX
class SharingScreen extends ConsumerStatefulWidget {
  const SharingScreen({super.key});

  @override
  ConsumerState<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends ConsumerState<SharingScreen> {
  Timer? _durationTimer;
  Duration _sharingDuration = Duration.zero;
  List<String> _localIpAddresses = [];
  bool _isLoadingIp = true;

  @override
  void initState() {
    super.initState();
    _startDurationTimer();
    _fetchLocalIpAddresses();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _sharingDuration += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _fetchLocalIpAddresses() async {
    if (kIsWeb) {
      setState(() {
        _isLoadingIp = false;
        _localIpAddresses = ['Not available on web'];
      });
      return;
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      final addresses = <String>[];
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
            addresses.add(addr.address);
          }
        }
      }

      setState(() {
        _localIpAddresses = addresses.isEmpty
            ? ['Unable to detect']
            : addresses;
        _isLoadingIp = false;
      });
    } catch (e) {
      setState(() {
        _localIpAddresses = ['Unable to detect'];
        _isLoadingIp = false;
      });
    }
  }

  Future<void> _stopSharing() async {
    await ref.read(screenSharingControllerProvider).stopSharing();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _copyConnectionInfo() {
    if (_localIpAddresses.isEmpty) return;

    final ip = _localIpAddresses.first;
    final port = AppConstants.servicePort;
    final connectionInfo = 'IP: $ip\nPort: $port';

    Clipboard.setData(ClipboardData(text: connectionInfo));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text('Connection info copied: $ip:$port'),
          ],
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Use LayoutBuilder for responsive design
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Determine if we have enough width for a side-by-side view
            // Using 800 as a comfortable breakpoint for tablet/landscape
            final isWide = constraints.maxWidth > 800;

            if (isWide) {
              return _buildWideLayout(context, theme, constraints);
            }
            return _buildNarrowLayout(context, theme, constraints);
          },
        ),
      ),
    );
  }

  /// Builds the layout for mobile/portrait screens (Vertical Stack)
  /// Modified: Stats Card on top, and pinned Stop button at bottom.
  Widget _buildNarrowLayout(
    BuildContext context,
    ThemeData theme,
    BoxConstraints constraints,
  ) {
    return Column(
      children: [
        // Scrollable content area
        Expanded(
          child: CustomScrollView(
            slivers: [
              // App Bar / Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _buildHeader(context, theme),
                ),
              ),

              // Stats Card (Pinned to top as requested)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: _buildStatsCard(context, theme)
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 100.ms)
                      .slideY(begin: 0.1),
                ),
              ),

              // Screen Preview Area
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: SizedBox(
                    // Allow the preview to take up to 50% of the screen height
                    height: constraints.maxHeight * 0.50,
                    child: _buildPreview(context, theme),
                  ),
                ),
              ),

              // Other Controls (Connection Info, Detailed metrics)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      // Web Server Card (Native only)
                      if (!kIsWeb) WebServerCard(isLargeScreen: false),

                      // Connection Info (Web Viewers)
                      _buildConnectionInfoCard(theme, theme.colorScheme)
                          .animate()
                          .fadeIn(duration: 400.ms, delay: 250.ms)
                          .slideY(begin: 0.1),

                      const SizedBox(height: 16),

                      // Detailed Metrics (Latency, Bitrate...)
                      _buildDetailedMetrics(context, theme),

                      // Extra space at bottom to ensure scrolling sees everything
                      // before the pinned button.
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Pinned Bottom - Stop Sharing Button
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child:
                GradientButton(
                      text: 'Stop Sharing',
                      icon: Icons.stop_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                      ),
                      onPressed: _showStopDialog,
                      width: double.infinity,
                    )
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 500.ms)
                    .slideY(begin: 0.1),
          ),
        ),
      ],
    );
  }

  /// Builds the layout for tablet/desktop/landscape screens (Horizontal Split)
  Widget _buildWideLayout(
    BuildContext context,
    ThemeData theme,
    BoxConstraints constraints,
  ) {
    return Row(
      children: [
        // Left Side: Main Preview
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(24),
            color: Colors.black12, // Subtle distinct background
            child: Column(
              children: [
                _buildHeader(context, theme, hideStatus: true),
                const SizedBox(height: 24),
                Expanded(
                  child: _buildPreview(context, theme, forceContain: true),
                ),
              ],
            ),
          ),
        ),

        // Right Side: Sidebar Controls
        Container(
          width: 400,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              left: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            children: [
              // Sidebar Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const StatusIndicator(status: StatusType.sharing),
                    const Spacer(),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Scrollable controls
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildControls(context, theme, isWide: true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Reusable Component Builders ---

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme, {
    bool hideStatus = false,
  }) {
    final metricsAsync = ref.watch(streamingMetricsProvider);

    return Row(
      children: [
        IconButton(
          onPressed: _showStopDialog,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Stop Sharing',
        ),
        if (!hideStatus) ...[
          const Spacer(),
          const StatusIndicator(status: StatusType.sharing),
          const Spacer(),
          metricsAsync.when(
            data: (metrics) =>
                QualityIndicator(metrics: metrics, compact: true),
            loading: () => const QualityIndicator(compact: true),
            error: (err, stack) => const QualityIndicator(compact: true),
          ),
        ],
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildStatsCard(BuildContext context, ThemeData theme) {
    final signalingService = ref.watch(signalingServiceProvider);
    final session = ref.watch(currentSessionProvider);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            theme,
            Icons.timer_rounded,
            'Duration',
            _formatDuration(_sharingDuration),
          ),
          _buildVerticalDivider(colorScheme),
          _buildStatItem(
            theme,
            Icons.people_rounded,
            'Viewers',
            '${signalingService.connectedPeerCount}',
          ),
          _buildVerticalDivider(colorScheme),
          _buildStatItem(
            theme,
            Icons.hd_rounded,
            'Quality',
            session?.quality.displayName ?? 'Medium',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedMetrics(BuildContext context, ThemeData theme) {
    final metricsAsync = ref.watch(streamingMetricsProvider);

    return metricsAsync
        .when(
          data: (metrics) => QualityIndicator(metrics: metrics),
          loading: () => const QualityIndicator(),
          error: (err, stack) => const QualityIndicator(),
        )
        .animate()
        .fadeIn(duration: 400.ms, delay: 400.ms);
  }

  Widget _buildPreview(
    BuildContext context,
    ThemeData theme, {
    bool forceContain = false,
  }) {
    final webrtcService = ref.watch(webrtcServiceProvider);

    return Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RTCVideoView(
                webrtcService.localRenderer,
                mirror: false,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                filterQuality: FilterQuality.medium,
              ),
              // Gradient Overlay (Subtle at bottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 80,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
              ),

              // Live Tag
              Positioned(top: 16, left: 16, child: _buildLiveTag(theme)),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 500.ms, delay: 200.ms)
        .scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutCubic);
  }

  Widget _buildLiveTag(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.success,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.success.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .fadeIn(duration: 500.ms)
              .then()
              .fadeOut(duration: 500.ms),
          const SizedBox(width: 8),
          Text(
            'LIVE',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// Original _buildControls logic, now primarily for Wide Layout side panel
  Widget _buildControls(
    BuildContext context,
    ThemeData theme, {
    bool isWide = false,
  }) {
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Web Server Card (Native only)
        if (!kIsWeb) WebServerCard(isLargeScreen: isWide),

        // Connection Info (Web Viewers)
        _buildConnectionInfoCard(
          theme,
          colorScheme,
        ).animate().fadeIn(duration: 400.ms, delay: 250.ms).slideY(begin: 0.1),

        const SizedBox(height: 16),

        // Stats Card
        _buildStatsCard(
          context,
          theme,
        ).animate().fadeIn(duration: 400.ms, delay: 300.ms).slideY(begin: 0.1),

        const SizedBox(height: 20),

        // Detailed Metrics (Latency, Bitrate...)
        _buildDetailedMetrics(context, theme),

        const SizedBox(height: 24),

        // Stop Button
        GradientButton(
          text: 'Stop Sharing',
          icon: Icons.stop_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
          ),
          onPressed: _showStopDialog,
          width: double.infinity,
        ).animate().fadeIn(duration: 400.ms, delay: 500.ms).slideY(begin: 0.1),
      ],
    );
  }

  Widget _buildConnectionInfoCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.wifi_tethering_rounded,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connection Info',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'For manual connections',
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                  ),
                ],
              ),
              const Spacer(),
              if (_localIpAddresses.isNotEmpty)
                IconButton.filledTonal(
                  onPressed: _copyConnectionInfo,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  tooltip: 'Copy Info',
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingIp)
            Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
            )
          else
            Column(
              children: _localIpAddresses
                  .map(
                    (ip) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.monitor,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ip,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            ':${AppConstants.servicePort}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider(ColorScheme colorScheme) {
    return Container(width: 1, height: 40, color: colorScheme.outlineVariant);
  }

  Widget _buildStatItem(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  void _showStopDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Sharing?'),
        content: const Text(
          'This will disconnect all viewers and stop sharing your screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _stopSharing();
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
