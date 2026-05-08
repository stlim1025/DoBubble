import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../models/todo_bubble.dart';

class HistoryScreen extends StatefulWidget {
  final Map<String, List<TodoBubble>>? initialData;
  const HistoryScreen({super.key, this.initialData});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Map<String, List<TodoBubble>> _historyData = {};
  bool _isLoading = true;
  final GlobalKey _todayKey = GlobalKey();
  String? _todayKeyStr;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _todayKeyStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    if (widget.initialData != null) {
      _historyData.addAll(widget.initialData!);
      _isLoading = false;
      // 초기 데이터가 있으면 즉시 스크롤 시도 (모핑/전환 효과와 동기화)
      _scrollToToday();
    } else {
      _loadHistory();
    }
  }

  void _scrollToToday() {
    if (!mounted) return;
    
    // 1. 레이아웃 준비 즉시 시작 (전환 애니메이션과 동기화)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // 충분히 긴 시간 동안 부드럽게 이동 (선형에 가까운 곡선 사용)
        _performScroll(duration: const Duration(milliseconds: 1500), curve: Curves.easeOutCubic);
      }
    });

    // 2. 전환 애니메이션이 딱 끝나는 시점(750ms)에 '즉시(Duration.zero)' 위치를 한 번 더 고정
    // 이미 1번 스크롤이 진행 중이거나 거의 도착한 상태이므로, 
    // 여기서 즉시 고정해버리면 시스템에 의한 '맨 위로 튕김' 현상을 원천 차단할 수 있습니다.
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted) {
        _performScroll(duration: Duration.zero);
      }
    });
  }

  void _performScroll({required Duration duration, Curve curve = Curves.easeOutQuart}) {
    if (!mounted) return;
    if (_todayKey.currentContext != null) {
      Scrollable.ensureVisible(
        _todayKey.currentContext!,
        duration: duration,
        curve: curve,
        alignment: 0.0,
      );
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _todayKeyStr = todayKey;
    
    final keys = prefs.getKeys().where((k) => k.startsWith('bubbles_')).map((k) => k.replaceFirst('bubbles_', '')).toList();
    if (!keys.contains(todayKey)) keys.add(todayKey);
    keys.sort((a, b) => b.compareTo(a));

    for (var date in keys) {
      final jsonStr = prefs.getString('bubbles_$date');
      List<TodoBubble> bubbles = [];
      if (jsonStr != null) {
        try {
          final List<dynamic> decoded = jsonDecode(jsonStr);
          bubbles = decoded.map((item) => TodoBubble.fromJson(item)).toList();
          bubbles.sort((a, b) {
            final aPopped = a.state == BubbleState.popped ? 0 : 1;
            final bPopped = b.state == BubbleState.popped ? 0 : 1;
            return aPopped.compareTo(bPopped);
          });
        } catch (_) {}
      }
      if (date.compareTo(todayKey) > 0 && bubbles.isEmpty) continue;
      _historyData[date] = bubbles;
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _scrollToToday();
    }
  }

  Future<void> _toggleBubbleState(String date, TodoBubble bubble) async {
    setState(() {
      if (bubble.state == BubbleState.popped) {
        bubble.state = BubbleState.floating;
      } else {
        bubble.state = BubbleState.popped;
      }
    });
    
    final prefs = await SharedPreferences.getInstance();
    final bubbles = _historyData[date];
    if (bubbles != null) {
      final jsonStr = jsonEncode(bubbles.map((b) => b.toJson()).toList());
      await prefs.setString('bubbles_$date', jsonStr);
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _deleteBubble(String date, TodoBubble bubble) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _historyData[date]?.removeWhere((b) => b.id == bubble.id);
    });
    
    final bubbles = _historyData[date];
    if (bubbles != null) {
      final jsonStr = jsonEncode(bubbles.map((b) => b.toJson()).toList());
      await prefs.setString('bubbles_$date', jsonStr);
    }
    HapticFeedback.mediumImpact();
  }

  Future<void> _toggleRepeat(String date, TodoBubble bubble) async {
    setState(() {
      bubble.isRepeating = !bubble.isRepeating;
    });
    
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 해당 날짜의 버블 데이터 업데이트
    final bubbles = _historyData[date];
    if (bubbles != null) {
      final jsonStr = jsonEncode(bubbles.map((b) => b.toJson()).toList());
      await prefs.setString('bubbles_$date', jsonStr);
    }

    // 2. 전역 반복 템플릿(repeating_templates) 동기화
    final templatesJson = prefs.getString('repeating_templates');
    List<TodoBubble> templates = [];
    if (templatesJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(templatesJson);
        templates = decoded.map((item) => TodoBubble.fromJson(item)).toList();
      } catch (_) {}
    }

    if (bubble.isRepeating) {
      // 반복 설정 시 템플릿에 추가 (중복 확인)
      if (!templates.any((t) => t.task == bubble.task)) {
        templates.add(bubble);
      }
    } else {
      // 반복 해제 시 템플릿에서 삭제 및 미래 데이터 정리
      templates.removeWhere((t) => t.task == bubble.task);
      await _cleanupFutureRepeatingTasks(bubble.task);
    }

    await prefs.setString('repeating_templates', jsonEncode(templates.map((t) => t.toJson()).toList()));
    
    _showGlassNotification(bubble.isRepeating ? '매일매일 반복될 거예요!' : '이제 더 이상 반복되지 않아요.');
    HapticFeedback.selectionClick();
  }

  void _showGlassNotification(String message) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    
    entry = OverlayEntry(
      builder: (context) => _GlassNotification(
        message: message,
        onComplete: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (entry.mounted) entry.remove();
    });
  }

  Future<void> _cleanupFutureRepeatingTasks(String taskName) async {
    // ... (기존 구현 유지)
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('bubbles_')).toList();
    
    // 오늘 날짜 계산
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    for (var key in keys) {
      final dateStr = key.replaceFirst('bubbles_', '');
      // 오늘 포함 이후 날짜만 처리
      if (dateStr.compareTo(todayKey) >= 0) {
        final jsonStr = prefs.getString(key);
        if (jsonStr != null) {
          try {
            final List<dynamic> decoded = jsonDecode(jsonStr);
            final bubbles = decoded.map((item) => TodoBubble.fromJson(item)).toList();
            
            final initialCount = bubbles.length;
            bubbles.removeWhere((b) => b.task == taskName);
            
            if (bubbles.length != initialCount) {
              await prefs.setString(key, jsonEncode(bubbles.map((b) => b.toJson()).toList()));
              // 만약 현재 메모리에 로드된 데이터라면 업데이트
              if (_historyData.containsKey(dateStr)) {
                setState(() {
                  _historyData[dateStr] = bubbles;
                });
              }
            }
          } catch (_) {}
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Hero(
        tag: 'history_transition',
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F172A), Color(0xFF0B1120)],
                  ),
                ),
              ),
              SafeArea(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxWidth: MediaQuery.of(context).size.width,
                  maxHeight: MediaQuery.of(context).size.height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context),
                      Expanded(
                        child: _historyData.isEmpty 
                          ? (_isLoading ? const SizedBox.shrink() : _buildEmptyState())
                          : _buildHistoryList(),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 20,
                child: GlassmorphicContainer(
                  width: 44,
                  height: 44,
                  borderRadius: 22,
                  blur: 15,
                  alignment: Alignment.center,
                  border: 1,
                  linearGradient: LinearGradient(
                    colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.1)],
                  ),
                  borderGradient: LinearGradient(
                    colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.1)],
                  ),
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(22),
                    child: const Center(
                      child: Icon(Icons.close_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '비눗방울 기록',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '터뜨린 할 일들을 확인할 수 있어요',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bubble_chart_outlined, size: 64, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text(
            '아직 기록된 비눗방울이 없어요.',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      controller: _scrollController,
      key: const PageStorageKey('history_list'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _historyData.length,
      itemBuilder: (context, index) {
        final date = _historyData.keys.elementAt(index);
        final bubbles = _historyData[date]!;
        return _buildDateSection(date, bubbles, key: date == _todayKeyStr ? _todayKey : null);
      },
    );
  }

  Widget _buildDateSection(String date, List<TodoBubble> bubbles, {Key? key}) {
    final poppedCount = bubbles.where((b) => b.state == BubbleState.popped).length;
    final totalCount = bubbles.length;
    final progress = totalCount > 0 ? poppedCount / totalCount : 0.0;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(date),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '톡! $poppedCount / $totalCount',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF4488FF).withOpacity(0.6)),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 12),
          ...bubbles.map((b) => _buildBubbleItem(date, b)).toList(),
        ],
      ),
    );
  }

  Widget _buildBubbleItem(String date, TodoBubble bubble) {
    return _SlidableBubbleItem(
      key: Key('bubble_${bubble.id}_$date'),
      bubble: bubble,
      onToggle: () => _toggleBubbleState(date, bubble),
      onDelete: () => _deleteBubble(date, bubble),
      onToggleRepeat: () => _toggleRepeat(date, bubble),
    );
  }

  String _formatDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    return '${parts[1]}월 ${parts[2]}일';
  }
}

class _SlidableBubbleItem extends StatefulWidget {
  final TodoBubble bubble;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onToggleRepeat;

  const _SlidableBubbleItem({
    super.key,
    required this.bubble,
    required this.onToggle,
    required this.onDelete,
    required this.onToggleRepeat,
  });

  @override
  State<_SlidableBubbleItem> createState() => _SlidableBubbleItemState();
}

class _SlidableBubbleItemState extends State<_SlidableBubbleItem> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragExtent = 0;
  final double _actionThreshold = 80;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent += details.delta.dx;
      // 너무 많이 밀리지 않도록 제한
      if (_dragExtent > 100) _dragExtent = 100;
      if (_dragExtent < -100) _dragExtent = -100;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_dragExtent > _actionThreshold) {
      widget.onToggleRepeat();
    } else if (_dragExtent < -_actionThreshold) {
      widget.onDelete();
    }
    
    // 원래 위치로 복구
    _controller.forward(from: 0).then((_) {
      if (mounted) {
        setState(() => _dragExtent = 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPopped = widget.bubble.state == BubbleState.popped;
    final priorityColor = TodoBubble.getPriorityColor(widget.bubble.priority);
    final double offset = _controller.isAnimating 
        ? Tween<double>(begin: _dragExtent, end: 0.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)).value
        : _dragExtent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── 배경 버튼 (Pill shape) ──
          // ... (기존 버튼 코드 유지)
          if (offset > 0) // 오른쪽으로 밀 때 (반복 설정)
            Positioned(
              left: 0,
              child: Container(
                width: offset.abs(),
                height: 54,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Transform.scale(
                    scale: (offset.abs() / 40).clamp(0.0, 1.0),
                    child: Opacity(
                      opacity: (offset.abs() / 40).clamp(0.0, 1.0),
                      child: Icon(
                        widget.bubble.isRepeating ? Icons.sync_disabled_rounded : Icons.sync_rounded,
                        color: Colors.blueAccent,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (offset < -5) // 왼쪽으로 밀 때 (삭제)
            Positioned(
              right: 0,
              child: Container(
                width: offset.abs(),
                height: 54,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Transform.scale(
                    scale: (offset.abs() / 40).clamp(0.0, 1.0),
                    child: Opacity(
                      opacity: (offset.abs() / 40).clamp(0.0, 1.0),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── 메인 할 일 카드 ──
          Transform.translate(
            offset: Offset(offset, 0),
            child: GestureDetector(
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              onTap: widget.onToggle,
              child: GlassmorphicContainer(
                width: double.infinity,
                height: 54,
                borderRadius: 16,
                blur: 10,
                alignment: Alignment.center,
                border: 1,
                linearGradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(isPopped ? 0.05 : 0.1),
                    Colors.white.withOpacity(isPopped ? 0.02 : 0.05),
                  ],
                ),
                borderGradient: LinearGradient(
                  colors: [
                    priorityColor.withOpacity(isPopped ? 0.2 : 0.5),
                    Colors.white.withOpacity(0.05),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        isPopped ? Icons.check_circle_rounded : Icons.circle_outlined,
                        color: isPopped ? priorityColor.withOpacity(0.6) : priorityColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.bubble.task,
                          style: TextStyle(
                            color: isPopped ? Colors.white38 : Colors.white.withOpacity(0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Pretendard',
                            decoration: null,
                          ),
                        ),
                      ),
                      if (widget.bubble.isRepeating)
                        const Icon(Icons.sync_rounded, size: 16, color: Colors.white24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassNotification extends StatefulWidget {
  final String message;
  final VoidCallback onComplete;

  const _GlassNotification({required this.message, required this.onComplete});

  @override
  State<_GlassNotification> createState() => _GlassNotificationState();
}

class _GlassNotificationState extends State<_GlassNotification> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );
    _offset = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120,
      left: 40,
      right: 40,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _offset,
          child: Material(
            color: Colors.transparent,
            child: GlassmorphicContainer(
              width: double.infinity,
              height: 52,
              borderRadius: 26,
              blur: 20,
              alignment: Alignment.center,
              border: 1,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.1)],
              ),
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Pretendard',
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
