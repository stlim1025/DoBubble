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

  // 자연스러운 움직임을 위한 변수들
  double _time = 0.0;
  final double _windFreqX; // X축 흔들림 주파수
  final double _windFreqY; // Y축 흔들림 주파수
  final double _windAmpX;  // X축 흔들림 세기
  final double _windAmpY;  // Y축 흔들림 세기
  final double _phaseX;    // X축 위상차
  final double _phaseY;    // Y축 위상차
  final double _driftSpeed; // 기본 부력 속도

  // 글라스모피즘 색상 (버블마다 살짝 다른 색조)
  final Color tintColor;
  final int priority; // 1 (가장 중요) ~ 4
  final bool isRepeating;
  final DateTime createdAt;

  TodoBubble({
    required this.id,
    required this.task,
    this.state = BubbleState.blowing,
    required this.position,
    required this.velocity,
    this.radius = 60.0,
    this.priority = 1,
    this.isRepeating = false,
    DateTime? createdAt,
    Color? tintColor,
  })  : createdAt = createdAt ?? DateTime.now(),
        _windFreqX = 0.005 + Random().nextDouble() * 0.007,
        _windFreqY = 0.003 + Random().nextDouble() * 0.005,
        _windAmpX = 0.25 + Random().nextDouble() * 0.30,
        _windAmpY = 0.25 + Random().nextDouble() * 0.30,
        _phaseX = Random().nextDouble() * pi * 2,
        _phaseY = Random().nextDouble() * pi * 2,
        _driftSpeed = 0.0,
        tintColor = tintColor ?? _randomTint();

  static Color _randomTint() {
    final tints = [
      const Color(0xFF88CCFF), // 청록
      const Color(0xFFAABBFF), // 라벤더
      const Color(0xFF99EEFF), // 민트
      const Color(0xFFCCBBFF), // 퍼플
      const Color(0xFF88DDCC), // 에메랄드
    ];
    return tints[Random().nextInt(tints.length)];
  }

  void update(Size screenSize, {double? bottomLimit}) {
    if (state == BubbleState.popping) return;

    _time += 1.0;

    // 바람 흔들림 (사인파 합성으로 불규칙한 흔들림 연출)
    final windX = _windAmpX * sin(_time * _windFreqX + _phaseX)
        + _windAmpX * 0.4 * sin(_time * _windFreqX * 2.3 + _phaseX * 1.5);
    final windY = _windAmpY * sin(_time * _windFreqY + _phaseY)
        + _windAmpY * 0.3 * sin(_time * _windFreqY * 1.7 + _phaseY * 0.8);

    // 바람 기반 속도 업데이트 (느리고 한가롭게)
    velocity = Offset(
      velocity.dx * 0.970 + windX * 0.025,
      velocity.dy * 0.970 + windY * 0.025,
    );

    // 상태에 따른 속도 상한 (불기 중일 땐 조금 더 빠르고 시원하게)
    final speedLimit = state == BubbleState.blowing ? 3.5 : 1.2;
    final speed = velocity.distance;
    if (speed > speedLimit) {
      velocity = velocity / speed * speedLimit;
    }

    position += velocity;

    // 화면 경계 - 부드럽게 밀어내기 (바운스 대신 반발력)
    const margin = 20.0;
    if (position.dx - radius < margin) {
      velocity = Offset(velocity.dx.abs() * 0.6 + 0.5, velocity.dy);
      position = Offset(radius + margin, position.dy);
    } else if (position.dx + radius > screenSize.width - margin) {
      velocity = Offset(-velocity.dx.abs() * 0.6 - 0.5, velocity.dy);
      position = Offset(screenSize.width - radius - margin, position.dy);
    }

    final effectiveBottom = bottomLimit ?? screenSize.height;
    if (position.dy - radius < margin) {
      velocity = Offset(velocity.dx, velocity.dy.abs() * 0.6 + 0.4);
      position = Offset(position.dx, radius + margin);
    } else if (position.dy + radius > effectiveBottom - margin) {
      velocity = Offset(velocity.dx, -velocity.dy.abs() * 0.6 - 0.4);
      position = Offset(position.dx, effectiveBottom - radius - margin);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task': task,
      'state': state.index,
      'position': {'dx': position.dx, 'dy': position.dy},
      'velocity': {'dx': velocity.dx, 'dy': velocity.dy},
      'radius': radius,
      'tintColor': tintColor.value,
      'priority': priority,
      'isRepeating': isRepeating,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TodoBubble.fromJson(Map<String, dynamic> json) {
    return TodoBubble(
      id: json['id'],
      task: json['task'],
      state: BubbleState.values[json['state'] ?? 1],
      position: Offset((json['position']['dx'] as num).toDouble(), (json['position']['dy'] as num).toDouble()),
      velocity: Offset((json['velocity']['dx'] as num).toDouble(), (json['velocity']['dy'] as num).toDouble()),
      radius: (json['radius'] as num).toDouble(),
      tintColor: json['tintColor'] != null ? Color(json['tintColor']) : null,
      priority: json['priority'] ?? 1,
      isRepeating: json['isRepeating'] ?? false,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
    );
  }
}
