import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:xml/xml.dart';

/// SVG parsing models and logic. No imports from main.dart to avoid circular dependency.
class PictureModel {
  final double width;
  final double height;
  final List<Region> regions;
  final Map<int, Color> palette;

  PictureModel({required this.width, required this.height, required this.regions, required this.palette});
}

class Region {
  final int id;
  final int colorId;
  final Path path;
  Color currentColor;
  bool _filled;

  Region({required this.id, required this.colorId, required this.path, Color? currentColor, bool filled = false})
    : currentColor = currentColor ?? Colors.white,
      _filled = filled;

  bool get isPainted => _filled;

  void markFilled(Color color) {
    currentColor = color;
    _filled = true;
  }
}

Future<PictureModel> parseUniversalSvg(String assetPath) async {
  final raw = await rootBundle.loadString(assetPath);
  final document = XmlDocument.parse(raw);
  final root = document.rootElement;

  // Получаем размеры из viewBox или width/height
  double width = 500;
  double height = 500;

  final viewBox = root.getAttribute('viewBox');
  if (viewBox != null) {
    final parts = viewBox.trim().split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
    if (parts.length == 4) {
      width = double.tryParse(parts[2]) ?? 500;
      height = double.tryParse(parts[3]) ?? 500;
    }
  } else {
    final w = root.getAttribute('width');
    final h = root.getAttribute('height');
    if (w != null) width = _parseSize(w);
    if (h != null) height = _parseSize(h);
  }

  int regionId = 1;
  int nextColorId = 1;

  final Map<String, int> colorMap = {};
  final Map<int, Color> palette = {};
  final List<Region> regions = [];

  void parseNode(XmlElement element, vm.Matrix4 parentMatrix) {
    vm.Matrix4 currentMatrix = vm.Matrix4.copy(parentMatrix);

    final transform = element.getAttribute('transform');
    if (transform != null) {
      currentMatrix = currentMatrix.multiplied(_parseTransform(transform));
    }

    Path? path;
    String? fill;

    switch (element.name.local) {
      case 'path':
        final d = element.getAttribute('d');
        if (d != null && d.isNotEmpty) {
          path = parseSvgPathData(d);
          fill = element.getAttribute('fill');
        }
        break;

      case 'rect':
        final x = double.tryParse(element.getAttribute('x') ?? '0') ?? 0;
        final y = double.tryParse(element.getAttribute('y') ?? '0') ?? 0;
        final w = double.tryParse(element.getAttribute('width') ?? '0') ?? 0;
        final h = double.tryParse(element.getAttribute('height') ?? '0') ?? 0;
        path = Path()..addRect(Rect.fromLTWH(x, y, w, h));
        fill = element.getAttribute('fill');
        break;

      case 'circle':
        final cx = double.tryParse(element.getAttribute('cx') ?? '0') ?? 0;
        final cy = double.tryParse(element.getAttribute('cy') ?? '0') ?? 0;
        final r = double.tryParse(element.getAttribute('r') ?? '0') ?? 0;
        path = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
        fill = element.getAttribute('fill');
        break;

      case 'ellipse':
        final cx = double.tryParse(element.getAttribute('cx') ?? '0') ?? 0;
        final cy = double.tryParse(element.getAttribute('cy') ?? '0') ?? 0;
        final rx = double.tryParse(element.getAttribute('rx') ?? '0') ?? 0;
        final ry = double.tryParse(element.getAttribute('ry') ?? '0') ?? 0;
        path = Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2));
        fill = element.getAttribute('fill');
        break;

      case 'polygon':
      case 'polyline':
        final pointsStr = element.getAttribute('points');
        if (pointsStr != null) {
          final points = _parsePoints(pointsStr);
          if (points.isNotEmpty) {
            path = Path()..addPolygon(points, element.name.local == 'polygon');
            fill = element.getAttribute('fill');
          }
        }
        break;
    }

    if (path != null && fill != null && fill != 'none' && fill.isNotEmpty) {
      final transformedPath = path.transform(currentMatrix.storage);

      // Normalize fill for consistent color mapping (e.g. #4F46A3 vs #4f46a3)
      final normalizedFill = fill.toLowerCase().trim();
      if (!colorMap.containsKey(normalizedFill)) {
        colorMap[normalizedFill] = nextColorId;
        palette[nextColorId] = parseSvgColor(fill);
        nextColorId++;
      }

      regions.add(Region(id: regionId++, colorId: colorMap[normalizedFill]!, path: transformedPath));
    }

    for (final child in element.children.whereType<XmlElement>()) {
      parseNode(child, currentMatrix);
    }
  }

  parseNode(root, vm.Matrix4.identity());

  return PictureModel(width: width, height: height, regions: regions, palette: palette);
}

double _parseSize(String value) {
  final numStr = value.replaceAll(RegExp(r'[^0-9.]'), '');
  return double.tryParse(numStr) ?? 500;
}

List<Offset> _parsePoints(String pointsStr) {
  final points = <Offset>[];
  final coords = pointsStr.trim().split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();

  for (int i = 0; i < coords.length - 1; i += 2) {
    final x = double.tryParse(coords[i]) ?? 0;
    final y = double.tryParse(coords[i + 1]) ?? 0;
    points.add(Offset(x, y));
  }
  return points;
}

vm.Matrix4 _parseTransform(String transform) {
  final matrix = vm.Matrix4.identity();

  final translateMatch = RegExp(r'translate\(([^)]+)\)').firstMatch(transform);
  if (translateMatch != null) {
    final values = translateMatch.group(1)!.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
    final dx = double.tryParse(values[0]) ?? 0;
    final dy = values.length > 1 ? double.tryParse(values[1]) ?? 0 : 0.0;
    matrix.translate(dx, dy);
  }

  final scaleMatch = RegExp(r'scale\(([^)]+)\)').firstMatch(transform);
  if (scaleMatch != null) {
    final values = scaleMatch.group(1)!.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
    final sx = double.tryParse(values[0]) ?? 1;
    final sy = values.length > 1 ? double.tryParse(values[1]) ?? sx : sx;
    matrix.scale(sx, sy);
  }

  final rotateMatch = RegExp(r'rotate\(([^)]+)\)').firstMatch(transform);
  if (rotateMatch != null) {
    final values = rotateMatch.group(1)!.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
    final angle = double.tryParse(values[0]) ?? 0;
    final cx = values.length > 1 ? double.tryParse(values[1]) ?? 0 : 0.0;
    final cy = values.length > 2 ? double.tryParse(values[2]) ?? 0 : 0.0;

    if (cx != 0 || cy != 0) {
      matrix.translate(cx, cy);
      matrix.rotateZ(angle * 3.14159265359 / 180);
      matrix.translate(-cx, -cy);
    } else {
      matrix.rotateZ(angle * 3.14159265359 / 180);
    }
  }

  final matrixMatch = RegExp(r'matrix\(([^)]+)\)').firstMatch(transform);
  if (matrixMatch != null) {
    final values = matrixMatch.group(1)!.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
    if (values.length == 6) {
      final a = double.tryParse(values[0]) ?? 1;
      final b = double.tryParse(values[1]) ?? 0;
      final c = double.tryParse(values[2]) ?? 0;
      final d = double.tryParse(values[3]) ?? 1;
      final e = double.tryParse(values[4]) ?? 0;
      final f = double.tryParse(values[5]) ?? 0;

      matrix.multiply(vm.Matrix4(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1));
    }
  }

  return matrix;
}

Color parseSvgColor(String fill) {
  if (fill == 'none' || fill.isEmpty) {
    return Colors.transparent;
  }

  if (fill.startsWith('#')) {
    String hex = fill.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) {
      return Color(int.parse('0xff$hex'));
    }
  }

  final rgbMatch = RegExp(r'rgba?\(([^)]+)\)').firstMatch(fill);
  if (rgbMatch != null) {
    final parts = rgbMatch.group(1)!.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
    final r = int.tryParse(parts[0]) ?? 0;
    final g = int.tryParse(parts[1]) ?? 0;
    final b = int.tryParse(parts[2]) ?? 0;
    final a = parts.length > 3 ? (double.tryParse(parts[3]) ?? 1) * 255 : 255;
    return Color.fromARGB(a.toInt(), r, g, b);
  }

  final colorMap = {
    'white': Colors.white,
    'black': Colors.black,
    'red': Colors.red,
    'green': Colors.green,
    'blue': Colors.blue,
    'yellow': Colors.yellow,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'pink': Colors.pink,
    'brown': Colors.brown,
    'gray': Colors.grey,
    'grey': Colors.grey,
    'cyan': Colors.cyan,
    'lime': Colors.lime,
    'indigo': Colors.indigo,
    'teal': Colors.teal,
    'amber': Colors.amber,
    'deeporange': Colors.deepOrange,
    'deeppurple': Colors.deepPurple,
    'lightblue': Colors.lightBlue,
    'lightgreen': Colors.lightGreen,
  };

  final lowerFill = fill.toLowerCase().replaceAll(' ', '');
  if (colorMap.containsKey(lowerFill)) {
    return colorMap[lowerFill]!;
  }

  return Colors.grey;
}
