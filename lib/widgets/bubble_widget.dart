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
  late Animation<double> _popScaleAnimation;
  late Animation<double> _popOpacityAnimation;

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

    // 터지기 애니메이션 (빵! 하고 터지는 느낌)
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _popScaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _popController, curve: Curves.easeOutExpo),
    );
    _popOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _popController, curve: Curves.easeInQuad),
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (widget.bubble.state == BubbleState.floating) {
          widget.onPop();
        }
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_blowController, _popController, widget.shimmerController]),
        builder: (context, child) {
          double currentScale = _blowAnimation.value;
          double currentOpacity = 1.0;

          if (widget.bubble.state == BubbleState.popping) {
            currentScale = _popScaleAnimation.value;
            currentOpacity = _popOpacityAnimation.value;
          }

          // 둥둥 떠있는 느낌의 위아래 부유 효과 (shimmerController와 고유 ID 활용하여 비동기화)
          final phaseOffset = widget.bubble.id.hashCode % 1000 / 1000.0;
          final floatingOffset = math.sin((widget.shimmerController.value + phaseOffset) * math.pi * 2) * 4.0;

          return Transform.translate(
            offset: Offset(0, floatingOffset),
            child: SizedBox(
              width: widget.bubble.radius * 2,
              height: widget.bubble.radius * 2,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // 1. 버블 본체 (전체 스케일/투명도 영향 받음)
                  Transform.scale(
                    scale: currentScale,
                    child: Opacity(
                      opacity: currentOpacity,
                      child: _buildGlassBubbleBody(),
                    ),
                  ),

                  // 2. 파티클 (본체의 투명도에 영향 받지 않고 불규칙하게 터짐)
                  if (widget.bubble.state == BubbleState.popping)
                    ..._buildParticles(widget.bubble.tintColor),
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
          // ── 1. 메인 구체 (완전 투명한 중앙, 뚜렷하고 얇은 가장자리 띠) ──
          Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3), // 선명하고 얇은 외곽선
                width: 0.5,
              ),
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.0,
                colors: [
                  Colors.transparent, // 중앙 85%는 완전 투명!
                  Colors.transparent,
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.7), // 가장자리 5% 구간에서 급격히 밝아짐
                ],
                stops: const [0.0, 0.85, 0.95, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.05),
                  blurRadius: 8,
                ),
              ],
            ),
          ),

          // ── 2. 우측 하단 오묘한 반사광 (핑크/민트) ──
          Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(0.6, 0.6), // 우측 하단에 치우침
                radius: 0.8, // 넘어가면 완전 투명해지도록 제한
                colors: [
                  const Color(0xFFDDA0DD).withOpacity(0.3 + shimmerVal * 0.1),
                  const Color(0xFF88FFCC).withOpacity(0.1),
                  Colors.transparent, // 중앙/좌측 상단 침범 금지!
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ── 3. 좌측 상단 부드럽지만 강한 하이라이트 (Specular) ──
          Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.6, -0.6), // 좌측 상단에 강하게 치우침
                radius: 0.7, // 넘어가면 투명해지도록 작게 제한
                colors: [
                  Colors.white.withOpacity(0.8), // 아주 밝고 강렬한 빛
                  Colors.white.withOpacity(0.2),
                  Colors.transparent, // 중앙/우측 하단 침범 금지!
                ],
                stops: const [0.0, 0.4, 1.0],
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
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                Text(
                  widget.bubble.task,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.90),
                    fontWeight: FontWeight.w600,
                    fontSize: math.max(11, r * 0.22),
                    letterSpacing: 0.3,
                    height: 1.3,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 8,
                      ),
                      Shadow(
                        color: tint.withOpacity(0.35),
                        blurRadius: 12,
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


  List<Widget> _buildParticles(Color tint) {
    return List.generate(24, (index) { // 파티클 수 최적화 (45 -> 24)
      final random = math.Random(index + widget.bubble.id.hashCode);
      
      final randomAngle = random.nextDouble() * math.pi * 2;
      final speedFactor = 0.4 + random.nextDouble() * 1.2;
      final size = 1.5 + random.nextDouble() * 4.0;
      
      final progress = _popController.value;
      
      // 초반에 바깥으로 흩어지는 힘
      final burstDistance = (widget.bubble.radius * 0.6) + 
                       (Curves.easeOutQuart.transform(progress) * 70 * speedFactor);
      
      final dx = math.cos(randomAngle) * burstDistance;
      var dy = math.sin(randomAngle) * burstDistance;

      // 비눗방울이 터진 후 물방울 잔여물이 아래로 떨어지는 중력 효과
      dy += Curves.easeInCubic.transform(progress) * 160; 
      
      final colors = [
        Colors.white, 
        const Color(0xFFFF88EE), 
        const Color(0xFF88EEEE), 
        tint
      ];
      final pColor = colors[random.nextInt(colors.length)];

      return Positioned(
        child: Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: (1.0 - progress * 1.2).clamp(0.0, 1.0),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: pColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: pColor.withOpacity(0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
