import 'package:flutter/material.dart';
import 'dart:math';

enum BubbleState { blowing, floating, popping }

class TodoBubble {
  final String id;
  final String task;
  BubbleState state;
  Offset position;
  Offset velocity;
  double radius;

  TodoBubble({
    required this.id,
    required this.task,
    this.state = BubbleState.blowing,
    required this.position,
    required this.velocity,
    this.radius = 0.0,
  });

  void update(Size screenSize) {
    if (state == BubbleState.floating) {
      position += velocity;

      // 화면 경계 충돌 처리 (바운스)
      if (position.dx - radius < 0) {
        position = Offset(radius, position.dy);
        velocity = Offset(velocity.dx.abs(), velocity.dy);
      } else if (position.dx + radius > screenSize.width) {
        position = Offset(screenSize.width - radius, position.dy);
        velocity = Offset(-velocity.dx.abs(), velocity.dy);
      }

      if (position.dy - radius < 0) {
        position = Offset(position.dx, radius);
        velocity = Offset(velocity.dx, velocity.dy.abs());
      } else if (position.dy + radius > screenSize.height) {
        position = Offset(position.dx, screenSize.height - radius);
        velocity = Offset(velocity.dx, -velocity.dy.abs());
      }
    }
  }
}
