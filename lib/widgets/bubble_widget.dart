import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../models/todo_bubble.dart';

class BubbleWidget extends StatefulWidget {
  final TodoBubble bubble;
  final AnimationController shimmerController;
  final VoidCallback onPop;
  final void Function(Offset position)? onLongPress;
  final bool isReadOnly;

  const BubbleWidget({
    super.key,
    required this.bubble,
    required this.shimmerController,
    required this.onPop,
    this.onLongPress,
    this.isReadOnly = false,
  });

  @override
  State<BubbleWidget> createState() => _BubbleWidgetState();
}

class _BubbleWidgetState extends State<BubbleWidget>
    with TickerProviderStateMixin {
  late AnimationController _blowController;
  late Animation<double> _blowAnimation;

  late AnimationController _popController;

  @override
  void initState() {
    super.initState();

    _blowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _blowAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _blowController, curve: Curves.easeOutBack),
    );

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    if (widget.bubble.state == BubbleState.blowing) {
      _blowController.forward().then((_) {
        if (mounted) {
          setState(() {
            widget.bubble.state = BubbleState.floating;
          });
        }
      });
    } else {
      _blowController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant BubbleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bubble.state == BubbleState.popping &&
        _popController.status == AnimationStatus.dismissed) {
      _popController.forward();
    }
  }

  @override
  void dispose() {
    _blowController.dispose();
    _popController.dispose();
    super.dispose();
  }

  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!widget.isReadOnly) HapticFeedback.selectionClick();
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        if (widget.bubble.state == BubbleState.floating && !widget.isReadOnly) {
          widget.onPop();
        }
      },
      onTapCancel: () => setState(() => _isPressed = false),
      onLongPress: widget.onLongPress != null ? () => widget.onLongPress!(widget.bubble.position) : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_blowController, _popController, widget.shimmerController]),
        builder: (context, child) {
          double currentScale = _blowAnimation.value;

          final phaseOffset = widget.bubble.id.hashCode % 1000 / 1000.0;
          final floatingOffset = math.sin((widget.shimmerController.value + phaseOffset) * math.pi * 2) * 4.0;

          final isPopping = widget.bubble.state == BubbleState.popping;
          final popProgress = _popController.value;

          double bodyOpacity = 1.0;
          double bodyScale = currentScale;
          if (isPopping) {
            final bodyPhase = (popProgress / 0.15).clamp(0.0, 1.0);
            bodyScale = currentScale * (1.0 - Curves.easeInBack.transform(bodyPhase) * 0.6);
            bodyOpacity = 1.0 - Curves.easeIn.transform(bodyPhase);
          }

          return Transform.translate(
            offset: Offset(0, floatingOffset),
            child: SizedBox(
              width: widget.bubble.radius * 2.5,
              height: widget.bubble.radius * 2.5,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (bodyOpacity > 0.01)
                    AnimatedScale(
                      scale: _isPressed ? 1.08 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutBack,
                      child: Transform.scale(
                        scale: bodyScale,
                        child: Opacity(
                          opacity: bodyOpacity,
                          child: _buildGlassBubbleBody(),
                        ),
                      ),
                    ),

                  if (isPopping)
                    ..._buildShockwave(),

                  if (isPopping)
                    ..._buildMembraneFragments(widget.bubble.tintColor),

                  if (isPopping)
                    ..._buildWaterDroplets(widget.bubble.tintColor),

                  if (isPopping && popProgress < 0.3)
                    _buildFlash(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlassBubbleBody() {
    final r = widget.bubble.radius;
    final tint = widget.bubble.tintColor;
    final shimmerVal = widget.shimmerController.value;

    return SizedBox(
      width: r * 2,
      height: r * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── 후면 광원 (Soft Glow) ──
          Container(
            width: r * 2.0,
            height: r * 2.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  tint.withOpacity(0.3),
                  tint.withOpacity(0.15),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ── 비눗방울 이미지 (Assets) ──
          ClipOval(
            child: Opacity(
              opacity: 0.9,
              child: Image.asset(
                'assets/images/Bubble.png',
                width: r * 2,
                height: r * 2,
                fit: BoxFit.contain,
                color: tint.withOpacity(0.1),
                colorBlendMode: BlendMode.srcATop,
              ),
            ),
          ),

          // ── 텍스트 ──
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.bubble.isRepeating)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Icon(
                      Icons.sync_rounded,
                      size: 10,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                Text(
                  widget.bubble.task,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Pretendard',
                    fontSize: math.max(11, r * 0.22),
                    letterSpacing: 0.3,
                    height: 1.3,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 4,
                      ),
                      Shadow(
                        color: tint.withOpacity(0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  maxLines: widget.bubble.isRepeating ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildShockwave() {
    final progress = _popController.value;
    final r = widget.bubble.radius;

    return List.generate(2, (i) {
      final delay = i * 0.08;
      final ringProgress = ((progress - delay) / (1.0 - delay)).clamp(0.0, 1.0);
      final expandScale = 1.0 + Curves.easeOutCubic.transform(ringProgress) * 1.2;
      final ringOpacity = (1.0 - Curves.easeInQuad.transform(ringProgress)) * 0.6;

      if (ringOpacity < 0.01) return const SizedBox.shrink();

      return Opacity(
        opacity: ringOpacity,
        child: Transform.scale(
          scale: expandScale,
          child: Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.8 - i * 0.3),
                width: 1.5 - i * 0.5,
              ),
            ),
          ),
        ),
      );
    });
  }

  List<Widget> _buildMembraneFragments(Color tint) {
    final progress = _popController.value;
    final r = widget.bubble.radius;

    return List.generate(12, (index) {
      final random = math.Random(index * 17 + widget.bubble.id.hashCode);
      final angle = (index / 12) * math.pi * 2 + random.nextDouble() * 0.5;
      final speedFactor = 0.6 + random.nextDouble() * 0.8;
      final burstPhase = Curves.easeOutQuart.transform(progress);
      final distance = r * 0.9 + burstPhase * r * 1.5 * speedFactor;
      final dx = math.cos(angle) * distance;
      var dy = math.sin(angle) * distance;
      dy += Curves.easeInQuad.transform(progress) * 80;

      final fragWidth = 3.0 + random.nextDouble() * 6.0;
      final fragHeight = 1.5 + random.nextDouble() * 2.5;
      final rotation = angle + burstPhase * (random.nextDouble() - 0.5) * 4;
      final opacity = (1.0 - progress * 1.5).clamp(0.0, 0.9);

      if (opacity < 0.01) return const SizedBox.shrink();

      final rainbowColors = [
        Colors.white,
        const Color(0xFFFF88DD),
        const Color(0xFF88DDFF),
        const Color(0xFFAAFF88),
        const Color(0xFFFFBB88),
        tint,
      ];
      final fragColor = rainbowColors[random.nextInt(rainbowColors.length)];

      return Positioned(
        child: Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: rotation,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: fragWidth,
                height: fragHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(fragHeight),
                  gradient: LinearGradient(
                    colors: [
                      fragColor.withOpacity(0.9),
                      Colors.white.withOpacity(0.6),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: fragColor.withOpacity(0.4),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  List<Widget> _buildWaterDroplets(Color tint) {
    final progress = _popController.value;
    final r = widget.bubble.radius;

    return List.generate(16, (index) {
      final random = math.Random(index * 31 + widget.bubble.id.hashCode);
      final angle = random.nextDouble() * math.pi * 2;
      final speedFactor = 0.3 + random.nextDouble() * 1.0;
      final size = 1.5 + random.nextDouble() * 3.5;
      final delayedProgress = ((progress - 0.05) / 0.95).clamp(0.0, 1.0);
      final burstDist = r * 0.5 + Curves.easeOutQuart.transform(delayedProgress) * 50 * speedFactor;
      final dx = math.cos(angle) * burstDist;
      var dy = math.sin(angle) * burstDist;
      dy += Curves.easeInCubic.transform(delayedProgress) * 120;
      final opacity = (1.0 - delayedProgress * 1.3).clamp(0.0, 1.0);

      if (opacity < 0.01) return const SizedBox.shrink();

      final colors = [
        Colors.white,
        const Color(0xFFFF88EE),
        const Color(0xFF88EEFF),
        tint,
      ];
      final pColor = colors[random.nextInt(colors.length)];

      return Positioned(
        child: Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: pColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: pColor.withOpacity(0.5),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildFlash() {
    final progress = _popController.value;
    final flashPhase = (progress / 0.15).clamp(0.0, 1.0);
    final flashOpacity = (1.0 - Curves.easeOut.transform(flashPhase)) * 0.7;
    final flashSize = widget.bubble.radius * (0.8 + flashPhase * 1.5);

    return Opacity(
      opacity: flashOpacity,
      child: Container(
        width: flashSize,
        height: flashSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withOpacity(0.9),
              Colors.white.withOpacity(0.3),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
      ),
    );
  }
}
