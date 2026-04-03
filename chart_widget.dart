import 'dart:math' as math;

import 'package:flutter/material.dart';

class VitalChartCard extends StatelessWidget {
  const VitalChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.values,
    required this.lineColor,
    required this.unitLabel,
  });

  final String title;
  final String subtitle;
  final List<double> values;
  final Color lineColor;
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF11212D),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF5B6B76), height: 1.45),
          ),
          const SizedBox(height: 16),
          MiniTrendChart(
            title: unitLabel,
            values: values,
            lineColor: lineColor,
            height: 160,
            showLabels: true,
          ),
        ],
      ),
    );
  }
}

class MiniTrendChart extends StatelessWidget {
  const MiniTrendChart({
    super.key,
    required this.title,
    required this.values,
    required this.lineColor,
    this.height = 120,
    this.showLabels = false,
  });

  final String title;
  final List<double> values;
  final Color lineColor;
  final double height;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _TrendPainter(
          values: values,
          lineColor: lineColor,
          showLabels: showLabels,
          title: title,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.lineColor,
    required this.showLabels,
    required this.title,
  });

  final List<double> values;
  final Color lineColor;
  final bool showLabels;
  final String title;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.24),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);

    final gridPaint = Paint()
      ..color = const Color(0xFFD9E2E8)
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.length < 2) {
      return;
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(maxValue - minValue, 1.0);
    const horizontalPadding = 12.0;
    const verticalPadding = 16.0;
    final chartWidth = size.width - horizontalPadding * 2;
    final chartHeight = size.height - verticalPadding * 2;

    final path = Path();
    final fillPath = Path();

    for (var index = 0; index < values.length; index++) {
      final x = horizontalPadding + chartWidth * index / (values.length - 1);
      final normalized = (values[index] - minValue) / range;
      final y = size.height - verticalPadding - normalized * chartHeight;

      if (index == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height - verticalPadding);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(
      size.width - horizontalPadding,
      size.height - verticalPadding,
    );
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    final dotPaint = Paint()..color = lineColor;
    final lastX = horizontalPadding + chartWidth;
    final lastY =
        size.height -
        verticalPadding -
        ((values.last - minValue) / range) * chartHeight;
    canvas.drawCircle(Offset(lastX, lastY), 4.5, dotPaint);

    if (showLabels) {
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: '${values.last.toStringAsFixed(1)} $title',
          style: TextStyle(
            color: lineColor,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      )..layout(maxWidth: size.width);

      textPainter.paint(canvas, Offset(size.width - textPainter.width, 0));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.title != title;
  }
}
