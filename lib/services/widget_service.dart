import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:home_widget/home_widget.dart';
import '../models/todo_bubble.dart';
import '../widgets/home_widget_view.dart';

class WidgetService {
  static Uint8List? _cachedBubbleBytes;
  static const String _groupId = 'group.com.dopop.widget';

  static Future<void> updateWidgetData(List<TodoBubble> bubbles) async {
    // iOS App Group 설정
    await HomeWidget.setAppGroupId(_groupId);

    // 1. 중요도 순으로 정렬 (1이 가장 높음)
    final sortedBubbles = List<TodoBubble>.from(bubbles);
    sortedBubbles.sort((a, b) => a.priority.compareTo(b.priority));
    
    // 최대 9개까지만 관리 (그리드 크기)
    final displayBubbles = sortedBubbles.take(9).toList();
    
    final totalCount = bubbles.length;
    final remainingCount = bubbles.where((b) => b.state != BubbleState.popped && b.state != BubbleState.popping).length;

    // 2. 데이터 저장 (텍스트 위젯용)
    await HomeWidget.saveWidgetData('total_bubbles', totalCount);
    await HomeWidget.saveWidgetData('remaining_bubbles', remainingCount);
    
    // 버블 ID 목록 저장 (iOS 인터랙티브 위젯에서 터치 영역 계산을 위해 사용)
    final bubbleIds = displayBubbles.map((b) => b.id).toList();
    await HomeWidget.saveWidgetData('bubble_ids', bubbleIds.join(','));
    
    // 터진 버블 ID 초기화 (iOS에서 처리 완료된 신호 확인용)
    await HomeWidget.saveWidgetData('popped_bubble_id', '');
    
    // 2. 이미지 에셋 캐싱 로드
    if (_cachedBubbleBytes == null) {
      try {
        final ByteData data = await rootBundle.load('assets/images/Bubble.png');
        _cachedBubbleBytes = data.buffer.asUint8List();
        // 로드 시에만 안정화를 위해 잠깐 대기
        await Future.delayed(Duration.zero);
      } catch (e) {
        debugPrint('Error loading bubble asset for widget: $e');
      }
    }
    
    final bubbleBytes = _cachedBubbleBytes;

    // 3. 이미지 스냅샷 생성
    // Small
    await HomeWidget.renderFlutterWidget(
      HomeWidgetView(
        bubbles: displayBubbles, 
        totalCount: totalCount, 
        remainingCount: remainingCount, 
        size: WidgetSize.small,
        bubbleImageBytes: bubbleBytes,
      ),
      key: 'snapshot_small',
      logicalSize: const Size(200, 200),
    );
    
    // Medium
    await HomeWidget.renderFlutterWidget(
      HomeWidgetView(
        bubbles: displayBubbles, 
        totalCount: totalCount, 
        remainingCount: remainingCount, 
        size: WidgetSize.medium,
        bubbleImageBytes: bubbleBytes,
      ),
      key: 'snapshot_medium',
      logicalSize: const Size(400, 250),
    );

    // Large
    await HomeWidget.renderFlutterWidget(
      HomeWidgetView(
        bubbles: displayBubbles, 
        totalCount: totalCount, 
        remainingCount: remainingCount, 
        size: WidgetSize.large,
        bubbleImageBytes: bubbleBytes,
      ),
      key: 'snapshot_large',
      logicalSize: const Size(400, 500),
    );

    // 위젯 갱신 요청
    final providers = [
      'BubbleWidgetProviderSmall',
      'BubbleWidgetProviderMedium',
      'BubbleWidgetProviderLarge',
    ];

    for (final provider in providers) {
      await HomeWidget.updateWidget(
        androidName: provider,
        iOSName: 'BubbleWidget',
      );
    }
  }
}
