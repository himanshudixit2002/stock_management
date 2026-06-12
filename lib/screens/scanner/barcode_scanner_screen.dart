import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/motion.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../utils/product_search.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/animations.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/success_check_animation.dart';
import '../../config/app_navigation.dart';

const _kRecentScansKey = 'barcode_recent_scans';
const _kMaxRecentScans = 10;
const _kScanThrottleMs = 2500;
const _kDebounceMs = 300;

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key, this.captureOnly = false});

  /// When true, pops with the scanned/typed code instead of searching products.
  final bool captureOnly;

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  MobileScannerController? _scannerController;
  bool _showCamera = !kIsWeb;
  bool _torchOn = false;
  List<ProductModel> _results = [];
  bool _searched = false;
  List<String> _recentScans = [];
  String? _lastScannedValue;
  DateTime? _lastScannedTime;
  Timer? _debounce;

  /// Brief visual success pulse shown over the reticle after a detection.
  bool _detected = false;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
    }
    if (widget.captureOnly) {
      _showCamera = !kIsWeb;
    }
    _loadRecentScans();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.captureOnly) {
        if (kIsWeb) _focusNode.requestFocus();
      } else {
        context.read<ProductProvider>().loadAnalytics();
        if (!_showCamera) _focusNode.requestFocus();
      }
    });
  }

  Future<void> _loadRecentScans() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRecentScansKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        if (mounted) {
          setState(() => _recentScans = list.map((e) => e.toString()).toList());
        }
      } catch (_) {}
    }
  }

  Future<void> _saveRecentScans(List<String> scans) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRecentScansKey, jsonEncode(scans));
  }

  void _removeRecentScan(String query) {
    setState(() => _recentScans.remove(query));
    _saveRecentScans(_recentScans);
  }

  void _lookupByQuery(String query) {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }

    final products = context.read<ProductProvider>().analyticsProducts;
    final matches = productsMatchingBarcodeOrName(products, query);
    _applyLookupState(query, matches);
  }

  void _applyLookupState(String rawQuery, List<ProductModel> matches) {
    final trimmed = rawQuery.trim();
    var nextRecent = _recentScans;
    if (matches.isNotEmpty && trimmed.isNotEmpty) {
      nextRecent = List<String>.from(_recentScans);
      nextRecent.remove(trimmed);
      nextRecent.insert(0, trimmed);
      if (nextRecent.length > _kMaxRecentScans) {
        nextRecent = nextRecent.sublist(0, _kMaxRecentScans);
      }
    }

    if (!mounted) return;
    setState(() {
      _results = matches;
      _searched = true;
      if (trimmed.isNotEmpty) {
        _controller.text = rawQuery;
        if (matches.length != 1) {
          _showCamera = false;
        }
      }
      if (matches.isNotEmpty && trimmed.isNotEmpty) {
        _recentScans = nextRecent;
      }
    });
    if (matches.isNotEmpty && trimmed.isNotEmpty) {
      _saveRecentScans(nextRecent);
    }
  }

  void _lookup() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    _lookupByQuery(query);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _kDebounceMs), () {
      _lookupByQuery(value.trim());
    });
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull;
    final rawValue = barcode?.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    final now = DateTime.now();
    if (_lastScannedValue == rawValue &&
        _lastScannedTime != null &&
        now.difference(_lastScannedTime!).inMilliseconds < _kScanThrottleMs) {
      return;
    }
    _lastScannedValue = rawValue;
    _lastScannedTime = now;

    HapticFeedback.mediumImpact();

    if (widget.captureOnly) {
      if (!mounted) return;
      Navigator.maybePop(context, rawValue);
      return;
    }

    _triggerDetectPulse();

    final products = context.read<ProductProvider>().analyticsProducts;
    final matches = productsMatchingBarcodeOrName(products, rawValue);

    if (!mounted) return;
    _applyLookupState(rawValue, matches);

    if (!mounted) return;
    if (matches.length == 1) {
      context.pushAppRoute(AppRoutes.productDetail, extra: matches.first);
    }
  }

  void _toggleTorch() {
    _scannerController?.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  /// Shows a short-lived success checkmark over the reticle as purely visual
  /// feedback. Does not affect detection/return behavior. Skipped under
  /// reduce-motion (the haptic still fires).
  void _triggerDetectPulse() {
    if (!mounted || reduceMotion(context)) return;
    setState(() => _detected = true);
    _pulseTimer?.cancel();
    _pulseTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _detected = false);
    });
  }

  void _onRecentScanTap(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _lookup();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pulseTimer?.cancel();
    _scannerController?.dispose();
    _scannerController = null;
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _popCaptureIfValid() {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    Navigator.maybePop(context, v);
  }

  Widget _buildCaptureManualScaffold(
    BuildContext context, {
    required String title,
    required String subtitle,
    bool showOpenCamera = false,
  }) {
    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(subtitle, style: TextStyle(color: AppTheme.textSec(context))),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Barcode or SKU',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _popCaptureIfValid(),
            ),
            const SizedBox(height: 16),
            if (showOpenCamera) ...[
              OutlinedButton.icon(
                onPressed: () => setState(() => _showCamera = true),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Use camera'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _popCaptureIfValid,
              child: const Text('Use this code'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.captureOnly && kIsWeb) {
      return _buildCaptureManualScaffold(
        context,
        title: 'Enter barcode',
        subtitle:
            'Camera scanning is not available on web. Type or paste the code.',
      );
    }
    if (widget.captureOnly && !kIsWeb && !_showCamera) {
      return _buildCaptureManualScaffold(
        context,
        title: 'Enter barcode',
        subtitle: 'Type the code or open the camera to scan.',
        showOpenCamera: true,
      );
    }

    final isLoading = context.watch<ProductProvider>().isLoadingAnalytics;

    if (_showCamera && _scannerController != null) {
      return Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _scannerController!,
              onDetect: _onBarcodeDetected,
              errorBuilder: (context, error) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.camera_alt_rounded,
                        size: 64,
                        color: Colors.white38,
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          error.errorDetails?.message ??
                              'Camera unavailable. Use manual entry instead.',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              _scannerController?.stop();
                              _scannerController?.start();
                            },
                            icon: const Icon(
                              Icons.refresh_rounded,
                              color: Colors.white70,
                            ),
                            label: const Text(
                              'Retry',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(width: 16),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _showCamera = false),
                            icon: const Icon(
                              Icons.keyboard_rounded,
                              color: Colors.white70,
                            ),
                            label: const Text(
                              'Type instead',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const _ViewfinderOverlay(),
            if (_detected)
              Center(
                child: SuccessCheckAnimation(
                  size: 76,
                  color: AppTheme.primaryLight,
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    automaticallyImplyLeading: !widget.captureOnly,
                    leading: widget.captureOnly
                        ? IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                            onPressed: () => Navigator.maybePop(context),
                          )
                        : null,
                    iconTheme: const IconThemeData(color: Colors.white),
                    title: const Text(
                      'Scan barcode',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(
                          _torchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          color: _torchOn ? Colors.amber : Colors.white70,
                        ),
                        tooltip: 'Toggle flashlight',
                        onPressed: _toggleTorch,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_rounded,
                          color: Colors.white70,
                        ),
                        tooltip: 'Type instead',
                        onPressed: () => setState(() => _showCamera = false),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 16,
                        color: AppTheme.primaryLight,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Point camera at a barcode',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.qr_code_scanner_rounded,
            color: AppTheme.primaryColor,
            title: 'Barcode Scanner',
          ),
          actions: [
            if (!kIsWeb)
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded),
                tooltip: 'Scan with camera',
                onPressed: () {
                  _scannerController ??= MobileScannerController(
                    detectionSpeed: DetectionSpeed.normal,
                    facing: CameraFacing.back,
                    torchEnabled: false,
                  );
                  setState(() => _showCamera = true);
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.infoColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.infoColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.infoColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Camera scanning requires a mobile device. Use manual search below.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            GlassPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: !_showCamera,
                    decoration: InputDecoration(
                      hintText: 'Enter barcode or product name...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _controller.clear();
                                setState(() {
                                  _results = [];
                                  _searched = false;
                                });
                              },
                            )
                          : null,
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    onSubmitted: (_) => _lookup(),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : _lookup,
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_rounded),
                    label: Text(isLoading ? 'Loading products...' : 'Search'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_recentScans.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Recent Scans',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentScans.map((query) {
                  return Dismissible(
                    key: ValueKey(query),
                    direction: DismissDirection.up,
                    onDismissed: (_) => _removeRecentScan(query),
                    child: ActionChip(
                      avatar: const Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: AppTheme.primaryColor,
                      ),
                      label: Text(query),
                      onPressed: () => _onRecentScanTap(query),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            if (_searched && _results.isEmpty)
              const EmptyStateWidget(
                icon: Icons.search_off_rounded,
                title: 'No Products Found',
                subtitle:
                    'No products match your search. Try a different barcode or product name.',
              ),
            if (_results.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_results.length} product${_results.length == 1 ? '' : 's'} found',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ..._results.asMap().entries.map((entry) {
                final product = entry.value;
                return FadeSlideIn(
                  index: entry.key,
                  child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    onTap: () => context.pushAppRoute(
                      AppRoutes.productDetail,
                      extra: product,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.inventory_2_rounded,
                              color: AppTheme.primaryColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: AppTheme.textPri(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (product.categoryName.isNotEmpty)
                                      product.categoryName,
                                    if (product.barcode.isNotEmpty)
                                      'Barcode: ${product.barcode}',
                                    'Qty: ${product.quantity} ${product.unit}',
                                  ].join(' \u2022 '),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSec(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.getStockColor(
                                product.quantity,
                                threshold: product.lowStockThreshold,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              product.stockStatus,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.getStockColor(
                                  product.quantity,
                                  threshold: product.lowStockThreshold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated viewfinder overlay for the camera scanning mode.
class _ViewfinderOverlay extends StatefulWidget {
  const _ViewfinderOverlay();

  @override
  State<_ViewfinderOverlay> createState() => _ViewfinderOverlayState();
}

class _ViewfinderOverlayState extends State<_ViewfinderOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Static reticle under reduce-motion; gentle sweep otherwise.
    if (!reduceMotion(context) && !_anim.isAnimating) {
      _anim.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanArea = math.min(size.width, size.height) * 0.65;

    if (reduceMotion(context)) {
      return Center(
        child: CustomPaint(
          size: Size(scanArea, scanArea),
          painter: _ViewfinderPainter(cornerOpacity: 0.85, scanPos: 0.5),
        ),
      );
    }

    return Center(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          return CustomPaint(
            size: Size(scanArea, scanArea),
            painter: _ViewfinderPainter(
              cornerOpacity: 0.5 + (_anim.value * 0.45),
              scanPos: _anim.value,
            ),
          );
        },
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  final double cornerOpacity;

  /// Vertical position of the scan line within the reticle (0 = top, 1 = bottom).
  final double scanPos;

  _ViewfinderPainter({required this.cornerOpacity, required this.scanPos});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: cornerOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const cornerLen = 28.0;
    const r = 14.0;

    // Sweeping scan line with a soft teal glow that fades at the edges.
    const inset = 8.0;
    final y = scanPos.clamp(0.0, 1.0) * size.height;
    final glowPaint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          AppTheme.primaryLight.withValues(alpha: 0.0),
          AppTheme.primaryLight.withValues(alpha: 0.95),
          AppTheme.primaryLight.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(inset, y - 2, size.width - inset * 2, 4));
    canvas.drawLine(
      Offset(inset, y),
      Offset(size.width - inset, y),
      glowPaint,
    );

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, cornerLen)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..lineTo(cornerLen, 0),
      paint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLen, 0)
        ..lineTo(size.width - r, 0)
        ..quadraticBezierTo(size.width, 0, size.width, r)
        ..lineTo(size.width, cornerLen),
      paint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - cornerLen)
        ..lineTo(0, size.height - r)
        ..quadraticBezierTo(0, size.height, r, size.height)
        ..lineTo(cornerLen, size.height),
      paint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLen, size.height)
        ..lineTo(size.width - r, size.height)
        ..quadraticBezierTo(
          size.width,
          size.height,
          size.width,
          size.height - r,
        )
        ..lineTo(size.width, size.height - cornerLen),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.cornerOpacity != cornerOpacity || old.scanPos != scanPos;
}
