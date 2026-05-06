import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../models/todo_bubble.dart';

class BubbleWidget extends StatefulWidget {
  final TodoBubble bubble;
  final VoidCallback onPop;

  const BubbleWidget({
    super.key,
    required this.bubble,
    required this.onPop,
  });

  @override
  State<BubbleWidget> createState() => _BubbleWidgetState();
}

class _BubbleWidgetState extends State<BubbleWidget> with TickerProviderStateMixin {
  late AnimationController _blowController;
  late Animation<double> _blowAnimation;
  
  late AnimationController _popController;
  late Animation<double> _popScaleAnimation;
  late Animation<double> _popOpacityAnimation;

  @override
  void initState() {
    super.initState();

    // 불기 애니메이션
    _blowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _blowAnimation = Tween<double>(begin: 0.1, end: 1.0).animate(
      CurvedAnimation(parent: _blowController, curve: Curves.elasticOut),
    );

    // 터지기 애니메이션
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _popScaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _popController, curve: Curves.easeOut),
    );
    _popOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _popController, curve: Curves.easeOut),
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
    if (widget.bubble.state == BubbleState.popping && oldWidget.bubble.state != BubbleState.popping) {
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
        animation: Listenable.merge([_blowController, _popController]),
        builder: (context, child) {
          double currentScale = _blowAnimation.value;
          double currentOpacity = 1.0;

          if (widget.bubble.state == BubbleState.popping) {
            currentScale = _popScaleAnimation.value;
            currentOpacity = _popOpacityAnimation.value;
          }

          return Transform.scale(
            scale: currentScale,
            child: Opacity(
              opacity: currentOpacity,
              child: _buildGlassBubble(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlassBubble() {
    return SizedBox(
      width: widget.bubble.radius * 2,
      height: widget.bubble.radius * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glassmorphism 배경
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.5,
                  ),
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.4),
                      Colors.transparent,
                      Colors.white.withOpacity(0.1),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                    center: const Alignment(-0.3, -0.3), // 약간의 하이라이트 효과
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.1),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // 빛 반사 효과 (하이라이트)
          Positioned(
            top: widget.bubble.radius * 0.2,
            left: widget.bubble.radius * 0.2,
            child: Container(
              width: widget.bubble.radius * 0.6,
              height: widget.bubble.radius * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.ellipse,
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.6),
                    Colors.white.withOpacity(0.0),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),

          // 텍스트 (할 일 내용)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              widget.bubble.task,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 4,
                  )
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 터지는 파티클 효과 (popping 상태일 때)
          if (widget.bubble.state == BubbleState.popping)
            ..._buildParticles(),
        ],
      ),
    );
  }

  List<Widget> _buildParticles() {
    return List.generate(8, (index) {
      final angle = index * (math.pi * 2 / 8);
      final distance = (_popScaleAnimation.value - 1) * 100;
      return Positioned(
        child: Transform.translate(
          offset: Offset(
            math.cos(angle) * distance,
            math.sin(angle) * distance,
          ),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(_popOpacityAnimation.value),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    });
  }
}
