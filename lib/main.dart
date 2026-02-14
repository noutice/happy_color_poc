import 'package:flutter/material.dart';
import 'package:happy_color_poc/parser.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Happy Color',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PictureModel? _picture;

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  Future<void> _loadSvg() async {
    try {
      final picture = await parseUniversalSvg('assets/b.svg');
      setState(() {
        _picture = picture;
      });
    } catch (e) {
      debugPrint('Error loading SVG: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_picture == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ColoringScreen(picture: _picture!);
  }
}

class ColoringScreen extends StatefulWidget {
  final PictureModel picture;

  const ColoringScreen({super.key, required this.picture});

  @override
  State<ColoringScreen> createState() => _ColoringScreenState();
}

class _ColoringScreenState extends State<ColoringScreen> {
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _paintKey = GlobalKey();
  bool _scaleInitialized = false;
  double _currentScale = 1.0;

  int? selectedColorId;
  int? focusedRegionId;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final m = _transformationController.value;
    final scale = ((m.storage[0].abs() + m.storage[5].abs()) / 2);
    // Update more frequently for smoother number size transitions (reduced threshold from 0.003 to 0.001)
    if (scale.isFinite && scale > 0 && (scale - _currentScale).abs() > 0.001) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentScale = scale);
      });
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details) {
    if (selectedColorId == null) return;

    final worldPosition = _transformationController.toScene(details.localPosition);

    for (final region in widget.picture.regions.reversed) {
      if (region.path.contains(worldPosition)) {
        if (region.colorId == selectedColorId && !region.isPainted) {
          setState(() {
            region.markFilled(widget.picture.palette[selectedColorId]!);
            focusedRegionId = region.id;
          });
        }
        break;
      }
    }
  }

  List<Region> get _highlightedRegions {
    if (selectedColorId == null) return [];
    return widget.picture.regions.where((r) => r.colorId == selectedColorId && !r.isPainted).toList();
  }

  Region? _findNextTarget() {
    if (selectedColorId == null) return null;

    final candidates = widget.picture.regions.where((r) => r.colorId == selectedColorId && !r.isPainted).toList();

    if (candidates.isEmpty) return null;

    if (focusedRegionId != null) {
      final idx = candidates.indexWhere((r) => r.id == focusedRegionId);
      if (idx >= 0 && idx + 1 < candidates.length) {
        return candidates[idx + 1];
      }
    }
    return candidates.first;
  }

  void _focusNextRegion() {
    final target = _findNextTarget();
    if (target == null) return;

    setState(() {
      focusedRegionId = target.id;
    });
  }

  void _fillAllRemaining() {
    if (selectedColorId == null) return;

    final toFill = widget.picture.regions.where((r) => r.colorId == selectedColorId && !r.isPainted).toList();
    if (toFill.isEmpty) return;

    setState(() {
      for (final region in toFill) {
        region.markFilled(widget.picture.palette[selectedColorId]!);
      }
      focusedRegionId = toFill.last.id;
    });
  }

  void _initializeScale(BoxConstraints constraints) {
    if (_scaleInitialized) return;

    final pictureWidth = widget.picture.width;
    final pictureHeight = widget.picture.height;

    final fitScaleX = constraints.maxWidth / pictureWidth;
    final fitScaleY = constraints.maxHeight / pictureHeight;
    // Always fit to screen so full picture is visible (no cutting)
    final scale = (fitScaleX < fitScaleY ? fitScaleX : fitScaleY).clamp(0.5, 5.0);

    // Scale around picture center, then center in viewport
    final cx = pictureWidth / 2;
    final cy = pictureHeight / 2;
    final vx = constraints.maxWidth / 2;
    final vy = constraints.maxHeight / 2;

    _transformationController.value =
        Matrix4.identity()
          ..translate(vx, vy)
          ..scale(scale)
          ..translate(-cx, -cy);

    _currentScale = scale;
    _scaleInitialized = true;
  }

  void _resetZoom() {
    setState(() => _scaleInitialized = false);
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = _highlightedRegions;
    final canGoNext = selectedColorId != null && highlighted.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text('Happy Color'),
        actions: [
          IconButton(
            tooltip: "Залить все оставшиеся",
            onPressed: canGoNext ? _fillAllRemaining : null,
            icon: const Icon(Icons.format_paint),
          ),
          IconButton(
            tooltip: "Следующий",
            onPressed: canGoNext ? _focusNextRegion : null,
            icon: const Icon(Icons.arrow_forward),
          ),
          IconButton(tooltip: "Сбросить зум", onPressed: _resetZoom, icon: const Icon(Icons.fit_screen)),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: widget.picture.regions.where((r) => r.isPainted).length / widget.picture.regions.length,
            backgroundColor: Colors.grey[300],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _initializeScale(constraints);
                return GestureDetector(
                  onTapUp: _handleTap,
                  behavior: HitTestBehavior.opaque,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.5,
                    maxScale: 10,
                    boundaryMargin: const EdgeInsets.all(100),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                      child: CustomPaint(
                        key: _paintKey,
                        size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
                        painter: ColoringPainter(
                          regions: widget.picture.regions,
                          selectedColorId: selectedColorId,
                          highlightedRegionIds: highlighted.map((e) => e.id).toSet(),
                          focusedRegionId: focusedRegionId,
                          zoomScale: _currentScale,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (selectedColorId != null) ...[
                        Text(
                          'Цвет $selectedColorId',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 20),
                        Text(
                          'Осталось: ${highlighted.length}',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                      ] else
                        const Text('Выберите цвет', style: TextStyle(fontSize: 18)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children:
                        widget.picture.palette.entries.map((entry) {
                          final isSelected = selectedColorId == entry.key;
                          final count =
                              widget.picture.regions.where((r) => r.colorId == entry.key && !r.isPainted).length;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedColorId = entry.key;
                                focusedRegionId = null;
                              });
                            },
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: entry.value,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  width: isSelected ? 3 : 1,
                                  color: isSelected ? Colors.black : Colors.grey,
                                ),
                                boxShadow:
                                    isSelected
                                        ? [
                                          BoxShadow(
                                            color: entry.value.withOpacity(0.5),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                        : null,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${entry.key}',
                                      style: TextStyle(
                                        color: _getContrastColor(entry.value),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (count > 0)
                                      Text(
                                        '$count',
                                        style: TextStyle(color: _getContrastColor(entry.value), fontSize: 10),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getContrastColor(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}

class ColoringPainter extends CustomPainter {
  final List<Region> regions;
  final int? selectedColorId;
  final Set<int> highlightedRegionIds;
  final int? focusedRegionId;
  final double zoomScale;

  /// Base font size in screen pixels - numbers scale inversely with zoom.
  /// This creates smooth scaling: zoom in = smaller numbers, zoom out = bigger numbers
  static const baseFontSizeScreen = 16.0;

  /// Minimum size threshold - numbers disappear when they would be smaller than this
  static const minVisibleFontSize = 5.0;

  /// For very small regions (e.g. color 5 decorative strokes), allow smaller font
  static const minFontSizeForSmallRegions = 3.0;

  /// Maximum font size cap to prevent numbers from becoming too large
  static const maxFontSize = 40.0;

  ColoringPainter({
    required this.regions,
    required this.selectedColorId,
    required this.highlightedRegionIds,
    required this.focusedRegionId,
    this.zoomScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint =
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

    final webPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;

    final focusWebPaint =
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    // First pass: draw all region fills, web patterns, and borders
    for (final region in regions) {
      final fillPaint =
          Paint()
            ..color = region.currentColor
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;

      canvas.drawPath(region.path, fillPaint);

      if (highlightedRegionIds.contains(region.id) && !region.isPainted) {
        _drawWebPattern(canvas, region.path, webPaint);
      }

      if (focusedRegionId == region.id && !region.isPainted) {
        _drawWebPattern(canvas, region.path, focusWebPaint);
      }

      canvas.drawPath(region.path, borderPaint);
    }

    // Second pass: draw all numbers ON TOP of the image so they are never lost
    final textPainter = TextPainter(textAlign: TextAlign.center, textDirection: TextDirection.ltr);
    for (final region in regions) {
      if (!region.isPainted) {
        final bounds = region.path.getBounds();
        // Allow even small regions (e.g. color 5 decorative strokes) to show numbers
        if (bounds.width > 1 && bounds.height > 1) {
          // Calculate desired font size: inversely proportional to zoom
          // When zooming IN (scale increases), font size DECREASES
          // When zooming OUT (scale decreases), font size INCREASES
          var desiredFontSize = baseFontSizeScreen / zoomScale;

          // Apply constraints to keep font size in reasonable range
          desiredFontSize = desiredFontSize.clamp(minVisibleFontSize, maxFontSize);

          // If the calculated font size is below minimum, don't show the number
          final pointsToTry = _findPointsInsidePath(region.path, bounds);
          final isSmallRegion = bounds.width < 10 || bounds.height < 10;
          // Try normal min font first, then smaller min for tiny regions (e.g. color 5)
          final minSizes = isSmallRegion ? [minVisibleFontSize, minFontSizeForSmallRegions] : [minVisibleFontSize];

          bool drawn = false;
          for (final minSize in minSizes) {
            if (desiredFontSize < minSize) continue;
            var tryFontSize = desiredFontSize.clamp(minSize, maxFontSize);
            for (final pointInside in pointsToTry) {
              final result = _calculateFontSizeAndOffset(
                region.path,
                pointInside,
                '${region.colorId}',
                tryFontSize,
                minFontSize: minSize,
              );
              if (result != null) {
                _drawNumberOnCanvas(canvas, textPainter, region, result);
                drawn = true;
                break;
              }
            }
            if (drawn) break;
          }
          // Last resort for tiny regions (e.g. color 5): draw at center, no path clip
          if (!drawn) {
            final fallback = _drawNumberFallback(region.path, bounds, '${region.colorId}');
            if (fallback != null) {
              _drawNumberOnCanvas(canvas, textPainter, region, fallback, clipToPath: false);
            }
          }
        }
      }
    }
  }

  void _drawNumberOnCanvas(
    Canvas canvas,
    TextPainter textPainter,
    Region region,
    ({double fontSize, Offset offset}) result, {
    bool clipToPath = true,
  }) {
    textPainter.text = TextSpan(
      text: '${region.colorId}',
      style: TextStyle(
        color: _getNumberColor(region),
        fontSize: result.fontSize,
        fontWeight: FontWeight.bold,
        shadows: const [Shadow(color: Colors.white, blurRadius: 3), Shadow(color: Colors.white, blurRadius: 8)],
      ),
    );
    textPainter.layout();
    if (clipToPath) canvas.save();
    if (clipToPath) canvas.clipPath(region.path);
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(result.offset.dx - 1, result.offset.dy, textPainter.width + 2, textPainter.height),
      const Radius.circular(3),
    );
    canvas.drawRRect(pillRect, Paint()..color = Colors.white.withOpacity(0.9));
    textPainter.paint(canvas, result.offset);
    if (clipToPath) canvas.restore();
  }

  /// Fallback for tiny regions: draw number at center, sized to fit bounds.
  ({double fontSize, Offset offset})? _drawNumberFallback(Path path, Rect bounds, String text) {
    final center = bounds.center;
    final minDim = bounds.width < bounds.height ? bounds.width : bounds.height;
    if (minDim < 1) return null;
    final fontSize = (minDim * 0.5).clamp(2.0, maxFontSize);
    final testPainter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    testPainter.layout();
    final left = center.dx - testPainter.width / 2;
    final top = center.dy - testPainter.height / 2;
    return (fontSize: fontSize, offset: Offset(left, top));
  }

  /// Draws a web-like mesh pattern inside the path (clipped to the path).
  void _drawWebPattern(Canvas canvas, Path path, Paint paint) {
    final bounds = path.getBounds();
    const spacing = 10.0;

    canvas.save();
    canvas.clipPath(path);

    // Diagonal lines (\)
    final diagLen = bounds.width + bounds.height;
    for (var i = -diagLen; i < diagLen * 2; i += spacing) {
      canvas.drawLine(
        Offset(bounds.left + i, bounds.top - diagLen),
        Offset(bounds.left + i + diagLen, bounds.top + diagLen),
        paint,
      );
    }
    // Diagonal lines (/)
    for (var i = -diagLen; i < diagLen * 2; i += spacing) {
      canvas.drawLine(
        Offset(bounds.right - i, bounds.top - diagLen),
        Offset(bounds.right - i - diagLen, bounds.top + diagLen),
        paint,
      );
    }

    canvas.restore();
  }

  /// Finds points inside the path within the inner margin area (15% from edges).
  List<Offset> _findPointsInsidePath(Path path, Rect bounds) {
    const margin = 0.15;
    final innerLeft = bounds.left + bounds.width * margin;
    final innerTop = bounds.top + bounds.height * margin;
    final innerRight = bounds.right - bounds.width * margin;
    final innerBottom = bounds.bottom - bounds.height * margin;

    if (innerRight <= innerLeft || innerBottom <= innerTop) return [bounds.center];

    final innerCenter = Offset((innerLeft + innerRight) / 2, (innerTop + innerBottom) / 2);

    final points = <Offset>[];
    if (path.contains(innerCenter)) points.add(innerCenter);

    const steps = 7;
    for (var i = 1; i < steps; i++) {
      for (var j = 1; j < steps; j++) {
        final p = Offset(
          innerLeft + (innerRight - innerLeft) * i / steps,
          innerTop + (innerBottom - innerTop) * j / steps,
        );
        if (path.contains(p)) points.add(p);
      }
    }
    if (points.isEmpty) return path.contains(bounds.center) ? [bounds.center] : [];
    return points;
  }

  Color _getNumberColor(Region region) {
    if (highlightedRegionIds.contains(region.id)) {
      return Colors.orange.shade800;
    }
    return Colors.black; // Strong contrast on white pill background
  }

  /// Finds font size and offset so the entire number fits INSIDE the path.
  /// maxFontSize: calculated from zoom (inverse scale). Will shrink if needed to fit.
  /// Returns null if the number cannot fit within the region boundaries at any size.
  ({double fontSize, Offset offset})? _calculateFontSizeAndOffset(
    Path path,
    Offset center,
    String text,
    double maxFontSize, {
    double minFontSize = minVisibleFontSize,
  }) {
    final bounds = path.getBounds();
    const margin = 0.15; // 15% margin from edges for better visibility
    final innerLeft = bounds.left + bounds.width * margin;
    final innerTop = bounds.top + bounds.height * margin;
    final innerRight = bounds.right - bounds.width * margin;
    final innerBottom = bounds.bottom - bounds.height * margin;
    final innerWidth = innerRight - innerLeft;
    final innerHeight = innerBottom - innerTop;

    // If the inner area is too small, don't show the number
    if (innerWidth <= 0 || innerHeight <= 0) return null;

    // Calculate the maximum font size that could fit in the region
    // Use 40% of the smaller dimension as upper bound for natural appearance
    final maxFitInRegion = (innerWidth < innerHeight ? innerWidth : innerHeight) * 0.40;

    // Start with the smaller of: zoom-based size OR max that fits in region
    var fontSize = (maxFontSize < maxFitInRegion ? maxFontSize : maxFitInRegion).clamp(
      minFontSize,
      ColoringPainter.maxFontSize,
    );

    // Fine-tune: iteratively shrink font size until it fits completely inside the path
    // Use smaller step size (0.25) for smoother scaling transitions
    while (fontSize >= minFontSize) {
      final testPainter = TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      testPainter.layout();

      final w = testPainter.width;
      final h = testPainter.height;

      // First check: does the text fit within the inner bounds?
      if (w > innerWidth || h > innerHeight) {
        fontSize -= 0.25; // Smaller step for smoother transitions
        continue;
      }

      // Calculate centered position
      final left = center.dx - w / 2;
      final top = center.dy - h / 2;

      // Second check: is the centered text within the inner area?
      if (left < innerLeft || top < innerTop || left + w > innerRight || top + h > innerBottom) {
        fontSize -= 0.25;
        continue;
      }

      // Third check: are all four corners of the text box inside the path?
      // This ensures the number is completely within the region
      final topLeft = Offset(left, top);
      final topRight = Offset(left + w, top);
      final bottomLeft = Offset(left, top + h);
      final bottomRight = Offset(left + w, top + h);

      if (path.contains(topLeft) &&
          path.contains(topRight) &&
          path.contains(bottomLeft) &&
          path.contains(bottomRight)) {
        // Found a size that fits! Return it.
        return (fontSize: fontSize, offset: Offset(left, top));
      }

      // Doesn't fit yet, try smaller
      fontSize -= 0.25;
    }

    // Could not find a size that fits within bounds
    return null;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
