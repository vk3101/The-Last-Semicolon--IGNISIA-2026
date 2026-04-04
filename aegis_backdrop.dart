import 'package:flutter/material.dart';

import '../theme/aegis_brand.dart';

class AegisBackdrop extends StatelessWidget {
  const AegisBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF2F8FF), Color(0xFFEAF3FF)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _GlowOrb(
            alignment: Alignment.topLeft,
            size: 340,
            colors: [Color(0x307AAAE8), Color(0x007AAAE8)],
            offset: Offset(-80, -110),
          ),
          const _GlowOrb(
            alignment: Alignment.topRight,
            size: 420,
            colors: [Color(0x366D9FE3), Color(0x006D9FE3)],
            offset: Offset(90, -130),
          ),
          const _GlowOrb(
            alignment: Alignment.bottomRight,
            size: 360,
            colors: [Color(0x209ABAE8), Color(0x009ABAE8)],
            offset: Offset(120, 90),
          ),
          Positioned(
            top: 72,
            right: -30,
            child: Transform.rotate(
              angle: 0.22,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: AegisBrand.primary.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: 120,
            child: Transform.rotate(
              angle: -0.24,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(
                    color: AegisBrand.secondary.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.alignment,
    required this.size,
    required this.colors,
    required this.offset,
  });

  final Alignment alignment;
  final double size;
  final List<Color> colors;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: offset,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: colors),
            ),
          ),
        ),
      ),
    );
  }
}
