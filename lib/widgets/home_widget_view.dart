import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/todo_bubble.dart';

enum WidgetSize { small, medium, large }

class HomeWidgetView extends StatelessWidget {
  final List<TodoBubble> bubbles;
  final int totalCount;
  final int remainingCount;
  final WidgetSize size;
  final Uint8List? bubbleImageBytes;

  const HomeWidgetView({
    super.key,
    required this.bubbles,
    required this.totalCount,
    required this.remainingCount,
    this.size = WidgetSize.large,
    this.bubbleImageBytes,
  });

  @override
  Widget build(BuildContext context) {
    double width = 400;
    double height = 500;
    if (size == WidgetSize.small) { width = 200; height = 200; }
    if (size == WidgetSize.medium) { width = 400; height = 250; }

    return MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        devicePixelRatio: 1.0,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF0B1120)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 12,
                  right: 12,
                  child: _buildProgressChip(),
                ),
                Positioned.fill(
                  top: 40,
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: _buildContent(width - 20, height - 50),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(double availableWidth, double availableHeight) {
    if (size == WidgetSize.small) {
      final listBubbles = bubbles.where((b) => b.state != BubbleState.popped && b.state != BubbleState.popping).take(3).toList();
      return Column(
        children: listBubbles.map((b) => _buildBubbleListItem(b)).toList(),
      );
    } else {
      return Stack(
        children: bubbles.asMap().entries.map((entry) {
          final int index = entry.key;
          final TodoBubble b = entry.value;
          
          // 중간 위젯은 6개, 대형 위젯은 9개로 제한
          final int maxCount = (size == WidgetSize.medium) ? 6 : 9;
          if (index >= maxCount) return const SizedBox.shrink();
          
          final bool isPopped = b.state == BubbleState.popped || b.state == BubbleState.popping;
          final int row = index ~/ 3;
          final int col = index % 3;
          final double slotWidth = availableWidth / 3;
          final double slotHeight = availableHeight / 3;
          
          final double centerX = slotWidth * (col + 0.5);
          final double centerY = slotHeight * (row + 0.5);
          
          double radius = (size == WidgetSize.medium) ? 35.0 : 45.0;
          if (b.priority == 1) radius *= 1.2;
          if (b.priority >= 3) radius *= 0.8;

          final int seed = b.id.hashCode;
          final double jX = ((seed % 20) - 10).toDouble();
          final double jY = (((seed ~/ 20) % 14) - 7).toDouble();

          return Positioned(
            left: (centerX + jX) - radius,
            top: (centerY + jY) - radius,
            child: Opacity(
              opacity: isPopped ? 0.0 : 1.0,
              child: _buildBubbleCircle(b, radius),
            ),
          );
        }).toList(),
      );
    }
  }

  Widget _buildBubbleCircle(TodoBubble b, double radius) {
    final double diameter = radius * 2;
    final Color tint = b.tintColor;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. 배경 글로우 (강화)
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withOpacity(0.2),
              gradient: RadialGradient(
                colors: [tint.withOpacity(0.8), tint.withOpacity(0.3)],
                stops: const [0.2, 1.0],
              ),
            ),
          ),
          
          // 2. 비눗방울 이미지 (안전하게 로드)
          _buildBubbleImage(diameter),
          
          // 3. 텍스트
          Padding(
            padding: EdgeInsets.all(radius * 0.25),
            child: Center(
              child: Text(
                b.task,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: radius * 0.3,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 2)],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleImage(double diameter) {
    // MemoryImage나 AssetImage가 백그라운드 렌더링 시 가끔 예외를 일으키므로 안전하게 처리
    try {
      return Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: (bubbleImageBytes != null)
                ? MemoryImage(bubbleImageBytes!) as ImageProvider
                : const AssetImage('assets/images/Bubble.png'),
            fit: BoxFit.contain,
            opacity: 0.8,
          ),
        ),
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildBubbleListItem(TodoBubble b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: b.tintColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: b.tintColor.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: b.tintColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              b.task,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$remainingCount / $totalCount',
        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
