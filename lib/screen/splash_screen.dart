import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_screen.dart';
import 'dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────
// SPLASH SCREEN
// ─────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg         = Color(0xFFF0F2F5);
  static const Color _ink        = Color(0xFF1A1D20);
  static const Color _muted      = Color(0xFF6C757D);

  // ── 1. Logo: blur + scale assembly (0 → 900ms) ─────────────
  late AnimationController _logoCtrl;
  late Animation<double>    _logoBlur;   // 18 → 0
  late Animation<double>    _logoScale;  // 0.3 → 1.0 with overshoot
  late Animation<double>    _logoOpacity;
  late Animation<double>    _clipRadius; // 0 → 1.0 (radial reveal)

  // ── 2. Particle ring orbiting logo (500ms → 2200ms) ─────────
  late AnimationController _ringCtrl;
  late Animation<double>    _ringAngle;    // full 2π rotation
  late Animation<double>    _ringOpacity;  // fade in then fade out

  // ── 3. Glow pulse after logo lands (950ms → forever) ────────
  late AnimationController _glowCtrl;
  late Animation<double>    _glowPulse;

  // ── 4. Bubble drift (0 → forever) ───────────────────────────
  late AnimationController _bubbleCtrl;
  late Animation<double>    _bubbleDrift;

  // ── 5. Tagline shimmer (2000ms → 3200ms) ────────────────────
  late AnimationController _shimmerCtrl;
  late Animation<double>    _shimmerPos; // 0.0 → 1.0 across text

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // ── Logo assembly ──────────────────────────────────────────
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));

    _logoBlur = Tween<double>(begin: 20.0, end: 0.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic));

    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.28, end: 1.10)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 78),
      TweenSequenceItem(
          tween: Tween(begin: 1.10, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 22),
    ]).animate(_logoCtrl);

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoCtrl,
            curve: const Interval(0.0, 0.35, curve: Curves.easeIn)));

    // Radial reveal: clip circle expands from 0 to full size
    _clipRadius = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl,
            curve: const Interval(0.1, 0.85, curve: Curves.easeOutQuart)));

    // ── Particle ring ──────────────────────────────────────────
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));

    _ringAngle = Tween<double>(begin: 0, end: math.pi * 2).animate(
        CurvedAnimation(parent: _ringCtrl, curve: Curves.easeInOut));

    _ringOpacity = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 20),
      TweenSequenceItem(
          tween: ConstantTween(1.0),
          weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 30),
    ]).animate(_ringCtrl);

    // ── Glow pulse ──────────────────────────────────────────────
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _glowPulse = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    // ── Bubble drift ────────────────────────────────────────────
    _bubbleCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 5))
      ..repeat(reverse: true);
    _bubbleDrift = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _bubbleCtrl, curve: Curves.easeInOut));

    // ── Tagline shimmer ──────────────────────────────────────────
    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _shimmerPos = Tween<double>(begin: -0.4, end: 1.4).animate(
        CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));

    // ── Sequence ─────────────────────────────────────────────────
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _logoCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _ringCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      _shimmerCtrl.forward();
    });

    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    await Future.delayed(const Duration(milliseconds: 4200));

    final prefs     = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? false;
    User? user       = FirebaseAuth.instance.currentUser;

    if (!rememberMe && user != null) {
      await FirebaseAuth.instance.signOut();
      user = null;
    }

    final canAutoLogin = user != null && user.emailVerified && rememberMe;
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: canAutoLogin ? const DashboardScreen() : const AuthScreen(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _ringCtrl.dispose();
    _glowCtrl.dispose();
    _bubbleCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [

          // ── Morphing bubble background ───────────────────────
          AnimatedBuilder(
            animation: _bubbleDrift,
            builder: (_, __) {
              final d = _bubbleDrift.value;
              return Stack(children: [
                Positioned(
                  top: -60 + d * 18,
                  right: -40 + d * 14,
                  child: CircleAvatar(
                    radius: 160 + d * 12,
                    backgroundColor: _yellow.withOpacity(0.30 + d * 0.08),
                  ),
                ),
                Positioned(
                  top: 160 - d * 10,
                  left: -80 + d * 8,
                  child: CircleAvatar(
                    radius: 110 + d * 8,
                    backgroundColor: const Color(0xFFE2E5E9),
                  ),
                ),
                Positioned(
                  bottom: -40 + d * 14,
                  right: -20,
                  child: CircleAvatar(
                    radius: 150 + d * 10,
                    backgroundColor: _yellow.withOpacity(0.14 + d * 0.06),
                  ),
                ),
                Positioned(
                  bottom: 110 - d * 8,
                  left: 10 + d * 6,
                  child: CircleAvatar(
                    radius: 90 + d * 6,
                    backgroundColor: const Color(0xFFD3D6DA),
                  ),
                ),
                // Extra small accent bubble — floats up
                Positioned(
                  bottom: 200 + d * 40,
                  left: 40 - d * 10,
                  child: CircleAvatar(
                    radius: 32 + d * 4,
                    backgroundColor: _yellow.withOpacity(0.14),
                  ),
                ),
              ]);
            },
          ),

          // ── Main content ─────────────────────────────────────
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                // ── Logo with particle ring + radial wipe + glow ─
                AnimatedBuilder(
                  animation: Listenable.merge(
                      [_logoCtrl, _ringCtrl, _glowCtrl]),
                  builder: (_, __) {
                    final glowReady = _logoCtrl.value > 0.85;
                    final glow      = glowReady ? _glowPulse.value : 0.0;

                    return SizedBox(
                      width: 180,
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [

                          // ── Glow halo ─────────────────────
                          if (glowReady)
                            Container(
                              width:  120 + glow * 30,
                              height: 120 + glow * 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _yellow.withOpacity(
                                        0.22 + glow * 0.22),
                                    blurRadius:   30 + glow * 28,
                                    spreadRadius: 2  + glow * 10,
                                  ),
                                ],
                              ),
                            ),

                          // ── Particle ring ─────────────────
                          if (_ringCtrl.value > 0)
                            ..._buildParticleRing(
                              angle:   _ringAngle.value,
                              opacity: _ringOpacity.value,
                              radius:  80,
                              count:   8,
                            ),

                          // ── Logo: radial clip + blur + scale ─
                          Transform.scale(
                            scale: _logoScale.value,
                            child: Opacity(
                              opacity: _logoOpacity.value,
                              child: ClipPath(
                                clipper: _RadialClipper(_clipRadius.value),
                                child: ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: _logoBlur.value,
                                    sigmaY: _logoBlur.value,
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      width:  120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // ── Spinning accent ring (thin border) ─
                          if (glowReady)
                            _SpinningRing(
                              size:    136,
                              color:   _yellow.withOpacity(0.35 + glow * 0.2),
                              strokeW: 1.5,
                            ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),

                // ── App name: "Campus" then " Sync" letter by letter ──
                _LetterRevealText(
                  text1: 'Campus',
                  text2: ' Sync',
                  color1: _ink,
                  color2: _yellow,
                  startDelay: 1050,
                ),

                const SizedBox(height: 10),

                // ── Tagline with shimmer sweep ────────────────
                AnimatedBuilder(
                  animation: _shimmerPos,
                  builder: (_, child) {
                    return ShaderMask(
                      shaderCallback: (rect) {
                        return LinearGradient(
                          begin: Alignment.centerLeft,
                          end:   Alignment.centerRight,
                          colors: [
                            _muted,
                            _muted,
                            Colors.white,
                            _muted,
                            _muted,
                          ],
                          stops: [
                            0.0,
                            (_shimmerPos.value - 0.15).clamp(0.0, 1.0),
                            _shimmerPos.value.clamp(0.0, 1.0),
                            (_shimmerPos.value + 0.15).clamp(0.0, 1.0),
                            1.0,
                          ],
                        ).createShader(rect);
                      },
                      child: child!,
                    );
                  },
                  child: const Text(
                    'Your college. Organised.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white, // shader overrides this
                      letterSpacing: 0.4,
                      fontFamily: 'Poppins',
                    ),
                  ),
                )
                .animate()
                .fade(delay: 1400.ms, duration: 500.ms),

                const SizedBox(height: 68),

                // ── Loading dots ──────────────────────────────
                _LoadingDots(color: _yellow),
              ],
            ),
          ),

          // ── Version ──────────────────────────────────────────
          Positioned(
            bottom: 32, left: 0, right: 0,
            child: const Text(
              'v1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _muted,
                letterSpacing: 0.7,
                fontFamily: 'Poppins',
              ),
            )
            .animate()
            .fade(delay: 2000.ms, duration: 600.ms),
          ),
        ],
      ),
    );
  }

  // ── Particle ring builder ────────────────────────────────────
  List<Widget> _buildParticleRing({
    required double angle,
    required double opacity,
    required double radius,
    required int count,
  }) {
    return List.generate(count, (i) {
      final particleAngle = angle + (i / count) * math.pi * 2;
      final x = math.cos(particleAngle) * radius;
      final y = math.sin(particleAngle) * radius;

      // Alternating sizes & opacities for depth
      final isLarge  = i % 3 == 0;
      final dotSize  = isLarge ? 6.0 : 4.0;
      final dotAlpha = (isLarge ? 0.85 : 0.55) * opacity;

      return Positioned(
        left: 90 + x - dotSize / 2,
        top:  90 + y - dotSize / 2,
        child: Container(
          width:  dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _yellow.withOpacity(dotAlpha),
            boxShadow: isLarge
                ? [BoxShadow(
                    color:      _yellow.withOpacity(dotAlpha * 0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )]
                : null,
          ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────
// RADIAL CLIPPER — expands the visible circle from 0 → full
// ─────────────────────────────────────────────────────────────
class _RadialClipper extends CustomClipper<Path> {
  final double progress; // 0.0 → 1.0
  _RadialClipper(this.progress);

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius =
        math.sqrt(math.pow(size.width / 2, 2) + math.pow(size.height / 2, 2));
    return Path()
      ..addOval(Rect.fromCircle(
          center: center, radius: maxRadius * progress.clamp(0.0, 1.0)));
  }

  @override
  bool shouldReclip(_RadialClipper old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────
// SPINNING RING — thin dashed ring that rotates continuously
// ─────────────────────────────────────────────────────────────
class _SpinningRing extends StatefulWidget {
  final double size;
  final Color  color;
  final double strokeW;
  const _SpinningRing(
      {required this.size, required this.color, required this.strokeW});

  @override
  State<_SpinningRing> createState() => _SpinningRingState();
}

class _SpinningRingState extends State<_SpinningRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spin,
      builder: (_, __) => Transform.rotate(
        angle: _spin.value * math.pi * 2,
        child: CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _DashedCirclePainter(
              color: widget.color, strokeW: widget.strokeW),
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color  color;
  final double strokeW;
  _DashedCirclePainter({required this.color, required this.strokeW});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = strokeW
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const dashCount    = 20;
    const dashAngle    = (math.pi * 2) / dashCount;
    const gapFraction  = 0.42; // fraction of each segment that is gap

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      final sweepAngle = dashAngle * (1 - gapFraction);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) =>
      old.color != color || old.strokeW != strokeW;
}

// ─────────────────────────────────────────────────────────────
// LETTER REVEAL TEXT — letters fly up one by one
// ─────────────────────────────────────────────────────────────
class _LetterRevealText extends StatefulWidget {
  final String text1, text2;
  final Color  color1, color2;
  final int    startDelay; // ms

  const _LetterRevealText({
    required this.text1,
    required this.text2,
    required this.color1,
    required this.color2,
    required this.startDelay,
  });

  @override
  State<_LetterRevealText> createState() => _LetterRevealTextState();
}

class _LetterRevealTextState extends State<_LetterRevealText>
    with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  late List<Animation<double>>   _fades;
  late List<Animation<Offset>>   _slides;

  @override
  void initState() {
    super.initState();
    final full  = widget.text1 + widget.text2;
    final count = full.length;
    const perLetter = 55; // ms between each letter

    _ctrls = List.generate(count, (_) => AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300)));

    _fades = _ctrls
        .map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: c, curve: Curves.easeOut)))
        .toList();

    _slides = _ctrls
        .map((c) => Tween<Offset>(
                begin: const Offset(0, 0.6), end: Offset.zero)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic)))
        .toList();

    for (int i = 0; i < count; i++) {
      Future.delayed(
          Duration(milliseconds: widget.startDelay + i * perLetter), () {
        if (mounted) _ctrls[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.text1 + widget.text2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(full.length, (i) {
        final ch    = full[i];
        final color = i < widget.text1.length ? widget.color1 : widget.color2;
        return SlideTransition(
          position: _slides[i],
          child: FadeTransition(
            opacity: _fades[i],
            child: Text(
              ch,
              style: TextStyle(
                fontSize:   34,
                fontWeight: FontWeight.w900,
                color:      color,
                letterSpacing: -0.5,
                height: 1.0,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LOADING DOTS
// ─────────────────────────────────────────────────────────────
class _LoadingDots extends StatelessWidget {
  final Color color;
  const _LoadingDots({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        )
        .animate(onPlay: (ctrl) => ctrl.repeat())
        .fadeIn(
          delay:    Duration(milliseconds: 1800 + i * 200),
          duration: const Duration(milliseconds: 380),
        )
        .then()
        .fadeOut(duration: const Duration(milliseconds: 380))
        .then()
        .fadeIn(duration: const Duration(milliseconds: 380));
      }),
    );
  }
}