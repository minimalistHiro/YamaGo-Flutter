import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerIconFactory {
  const MarkerIconFactory({
    this.width = 96,
    this.height = 132,
  });

  final double width;
  final double height;

  Future<BitmapDescriptor> create({
    required Color color,
    required IconData icon,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final fillPaint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.fill;
    final strokePaint = ui.Paint()
      ..color = color.darken()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4;
    final center = ui.Offset(width / 2, width / 2);
    canvas.drawCircle(center, width / 2, fillPaint);
    canvas.drawCircle(center, width / 2 - 2, strokePaint);

    final tailPath = ui.Path()
      ..moveTo(width / 2, height)
      ..lineTo(width * 0.2, width * 0.75)
      ..lineTo(width * 0.8, width * 0.75)
      ..close();
    canvas.drawPath(tailPath, fillPaint);
    canvas.drawPath(tailPath, strokePaint);

    final textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );
    final textSpan = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: width * 0.65,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    );
    textPainter.text = textSpan;
    textPainter.layout();
    final iconOffset = ui.Offset(
      center.dx - (textPainter.width / 2),
      center.dy - (textPainter.height / 2),
    );
    textPainter.paint(canvas, iconOffset);

    final picture = recorder.endRecording();
    final image =
        await picture.toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final buffer = bytes?.buffer.asUint8List();
    if (buffer == null) {
      throw StateError('Failed to encode marker image');
    }
    return BitmapDescriptor.fromBytes(buffer);
  }
}

extension MarkerIconColorUtils on Color {
  Color darken([double amount = 0.2]) {
    final hsl = HSLColor.fromColor(this);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }
}
