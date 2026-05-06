import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../models/todo_bubble.dart';

class BubbleWidget extends StatefulWidget {
  final TodoBubble bubble;
  final AnimationController shimmerController; // 공유 컨트롤러 수신
  final VoidCallback onPop;

  const BubbleWidget({
    super.key,
    required this.bubble,
    required this.shimmerController,
    required this.onPop,
  });

  @override
  State<BubbleWidget> createState() => _BubbleWidgetState();
}

class _BubbleWidgetState extends State<BubbleWidget>
    with TickerProviderStateMixin {
  late AnimationController _blowController;
  late Animation<double> _blowAnimation;

  late AnimationController _popController;

  // 미묘한 shimmer 애니메이션 (이제 외부에서 주입받음)

  @override
  void initState() {
    super.initState();

    // 불기 애니메이션 (후- 불어넣는 느낌, 빠르고 탄성있게)
    _blowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _blowAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _blowController, curve: Curves.easeOutBack),
    );

    // 터지기 애니메이션 - 매우 짧고 즉각적
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    // shimmer 루프 제거 (HomeScreen에서 관리)

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
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        if (widget.bubble.state == BubbleState.floating) {
          widget.onPop();
        }
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedBuilder(
        animation: Listenable.merge([_blowController, _popController, widget.shimmerController]),
        builder: (context, child) {
          double currentScale = _blowAnimation.value;

          // 둥둥 떠있는 느낌의 위아래 부유 효과
          final phaseOffset = widget.bubble.id.hashCode % 1000 / 1000.0;
          final floatingOffset = math.sin((widget.shimmerController.value + phaseOffset) * math.pi * 2) * 4.0;

          final isPopping = widget.bubble.state == BubbleState.popping;
          final popProgress = _popController.value;

          // 터질 때: 본체가 순간적으로 줄어들면서 사라짐 (0~15% 구간에서 완료)
          double bodyOpacity = 1.0;
          double bodyScale = currentScale;
          if (isPopping) {
            // 초반 15%에서 본체가 빠르게 쪼그라들며 사라짐
            final bodyPhase = (popProgress / 0.15).clamp(0.0, 1.0);
            bodyScale = currentScale * (1.0 - Curves.easeInBack.transform(bodyPhase) * 0.6);
            bodyOpacity = 1.0 - Curves.easeIn.transform(bodyPhase);
          }

          return Transform.translate(
            offset: Offset(0, floatingOffset),
            child: SizedBox(
              width: widget.bubble.radius * 2.5,  // 파티클 공간 확보
              height: widget.bubble.radius * 2.5,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // 1. 버블 본체 - 즉시 사라짐
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

                  // 2. 터질 때 충격파 링 (shockwave ring)
                  if (isPopping)
                    ..._buildShockwave(),

                  // 3. 터질 때 막 파편 (membrane fragments)
                  if (isPopping)
                    ..._buildMembraneFragments(widget.bubble.tintColor),

                  // 4. 물방울 파티클
                  if (isPopping)
                    ..._buildWaterDroplets(widget.bubble.tintColor),

                  // 5. 터지는 순간 섬광
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
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── 1. 메인 구체 (완전 투명한 중앙, 뚜렷하고 매우 얇은 가장자리 띠) ──
              Container(
                width: r * 2,
                height: r * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent, // 완전히 투명하게
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3), // 얇고 투명한 유리 테두리
                    width: 0.5,
                  ),
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.0,
                    colors: [
                      Colors.white.withOpacity(0.0), // 안쪽은 완전 투명
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.05),
                      Colors.white.withOpacity(0.3), // 가장자리만 살짝 반사
                    ],
                    stops: const [0.0, 0.8, 0.95, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.05),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              // ── 2. 우측 하단 오묘한 반사광 (거의 투명하게) ──
              Container(
                width: r * 2,
                height: r * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(0.6, 0.6),
                    radius: 0.8,
                    colors: [
                      const Color(0xFFDDA0DD).withOpacity(0.15 + shimmerVal * 0.05),
                      const Color(0xFF88FFCC).withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),

              // ── 3. 좌측 상단 강한 하이라이트 (Specular) - 유리의 광택 느낌 ──
              Container(
                width: r * 2,
                height: r * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.6, -0.6),
                    radius: 0.6,
                    colors: [
                      Colors.white.withOpacity(0.8), // 작지만 아주 강한 빛
                      Colors.white.withOpacity(0.1),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.3, 1.0],
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
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: math.max(11, r * 0.22),
                        letterSpacing: 0.3,
                        height: 1.3,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 4,
                          ),
                          Shadow(
                            color: tint.withOpacity(0.6),
                            blurRadius: 10,
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
        ),
      ),
    );
  }

  // ── 충격파 링: 버블 외곽선이 바깥으로 팽창하며 퍼지는 효과 ──
  List<Widget> _buildShockwave() {
    final progress = _popController.value;
    final r = widget.bubble.radius;

    // 두 개의 링이 시간차로 퍼져나감
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

  // ── 막 파편: 비눗방울 표면 조각이 바깥으로 날아가는 효과 ──
  List<Widget> _buildMembraneFragments(Color tint) {
    final progress = _popController.value;
    final r = widget.bubble.radius;

    return List.generate(12, (index) {
      final random = math.Random(index * 17 + widget.bubble.id.hashCode);

      // 비눗방울 표면(가장자리)에서 시작
      final angle = (index / 12) * math.pi * 2 + random.nextDouble() * 0.5;
      final speedFactor = 0.6 + random.nextDouble() * 0.8;

      // 바깥으로 빠르게 날아감
      final burstPhase = Curves.easeOutQuart.transform(progress);
      final distance = r * 0.9 + burstPhase * r * 1.5 * speedFactor;

      final dx = math.cos(angle) * distance;
      var dy = math.sin(angle) * distance;
      // 중력으로 아래로 처짐
      dy += Curves.easeInQuad.transform(progress) * 80;

      // 파편 크기: 호 모양으로 표현 (작은 곡선 조각)
      final fragWidth = 3.0 + random.nextDouble() * 6.0;
      final fragHeight = 1.5 + random.nextDouble() * 2.5;
      final rotation = angle + burstPhase * (random.nextDouble() - 0.5) * 4;

      // 투명도: 빠르게 사라짐
      final opacity = (1.0 - progress * 1.5).clamp(0.0, 0.9);

      if (opacity < 0.01) return const SizedBox.shrink();

      // 비눗방울 막 특유의 무지개 색상
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

  // ── 물방울 파티클: 터진 후 잔여 물방울이 퍼지며 떨어짐 ──
  List<Widget> _buildWaterDroplets(Color tint) {
    final progress = _popController.value;
    final r = widget.bubble.radius;

    return List.generate(16, (index) {
      final random = math.Random(index * 31 + widget.bubble.id.hashCode);

      final angle = random.nextDouble() * math.pi * 2;
      final speedFactor = 0.3 + random.nextDouble() * 1.0;
      final size = 1.5 + random.nextDouble() * 3.5;

      // 시작은 약간 지연 (막 파편 후에 물방울이 나옴)
      final delayedProgress = ((progress - 0.05) / 0.95).clamp(0.0, 1.0);

      // 바깥으로 퍼지며
      final burstDist = r * 0.5 + Curves.easeOutQuart.transform(delayedProgress) * 50 * speedFactor;
      final dx = math.cos(angle) * burstDist;
      // 중력의 영향을 많이 받음 (물방울이 아래로 쏟아짐)
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

  // ── 터지는 순간 섬광 ──
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
