import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/ui.dart';

/// Splash inicial (solo al abrir la app) con entrada y flotación ligera.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1300),
  });
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () {
      if (mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, Color(0xFFF59E0B)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FadeTransition(
                opacity: _enter,
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _enter,
                    curve: Curves.easeOutBack,
                  ),
                  child: AnimatedBuilder(
                    animation: _float,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(0, math.sin(_float.value * math.pi) * -10),
                      child: child,
                    ),
                    child: const BeeLogo(size: 150),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FadeTransition(
                opacity: _enter,
                child: const Column(
                  children: [
                    Text(
                      'BIFFY',
                      style: TextStyle(
                        fontFamily: AppTypography.heading,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: AppColors.text,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Comida que llega volando',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
