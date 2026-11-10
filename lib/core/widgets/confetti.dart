import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Lanza confeti sobre toda la app (al confirmar un pedido o al entregarlo).
/// No se muestra si el teléfono pide reducir animaciones.
void celebrate(BuildContext context) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _ConfettiBurst(onDone: entry.remove));
  overlay.insert(entry);
}

/// Overlay privado que anima el confeti y se borra al terminar.
class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst({required this.onDone});
  final VoidCallback onDone;

  /// Crea el estado de la animación de confeti.
  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

/// Estado que controla la animación de confeti de duración fija.
class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  // Dura un tiempo fijo y se borra solo (una animación infinita colgaría los tests).
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward().whenComplete(widget.onDone);

  final _pieces = List.generate(70, (i) => _Piece(Random(i)));

  /// Libera el controlador de animación.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Dibuja el confeti sobre toda la pantalla sin bloquear toques.
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_pieces, _controller.value),
        ),
      ),
    );
  }
}

/// Un papelito: sale del centro con una dirección, velocidad, color y giro al azar.
class _Piece {
  _Piece(Random r)
    : angle = r.nextDouble() * 2 * pi,
      speed = 150 + r.nextDouble() * 200,
      spin = (r.nextDouble() - 0.5) * 12,
      size = 6 + r.nextDouble() * 6,
      color = _colors[r.nextInt(_colors.length)];

  static const _colors = [
    AppColors.primary,
    AppColors.secondary,
    AppColors.success,
    AppColors.error,
    Colors.white,
  ];

  final double angle;
  final double speed;
  final double spin;
  final double size;
  final Color color;
}

/// Pintor que dibuja cada papelito en su posición actual.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  /// Dibuja los papelitos con gravedad y desvanecimiento.
  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.4);
    final paint = Paint();
    for (final p in pieces) {
      // Sale disparado hacia afuera y la "gravedad" lo hace caer.
      final pos =
          origin +
          Offset(cos(p.angle), sin(p.angle) - 0.6) * p.speed * t +
          Offset(0, 420 * t * t);
      paint.color = p.color.withValues(alpha: 1 - t);
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(p.spin * t)
        ..drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          ),
          paint,
        )
        ..restore();
    }
  }

  /// Repinta mientras avance la animación.
  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
