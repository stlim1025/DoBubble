import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:flutter/rendering.dart';
import '../models/todo_bubble.dart';
import '../widgets/glass_calendar.dart';

class HistoryScreen extends StatefulWidget {
  final Map<String, List<TodoBubble>>? initialData;
  const HistoryScreen({super.key, this.initialData});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with TickerProviderStateMixin {
  final Map<String, List<TodoBubble>> _historyData = {};
  bool _isLoading = true;
  final Map<String, GlobalKey> _sectionKeys = {}; // 날짜별 섹션 키 저장
  String? _todayKeyStr;
  final ScrollController _scrollController = ScrollController();
  // route 애니메이션 리스너 (Hero 완료 감지용)
  AnimationStatusListener? _routeAnimationListener;
  bool _scrolledToToday = false;

  // 달력 관련
  bool _isCalendarOpen = false;
  late AnimationController _calendarController;
  late Animation<double> _calendarAnimation;
  DateTime _selectedCalendarDate = DateTime.now();
  bool _showReturnToToday = false;

  @override
  void dispose() {
    _removeRouteListener();
    _scrollController.dispose();
    _calendarController.dispose();
    super.dispose();
  }

  void _removeRouteListener() {
    if (_routeAnimationListener != null) {
      ModalRoute.of(context)?.animation?.removeStatusListener(_routeAnimationListener!);
      _routeAnimationListener = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Route 애니메이션이 완전히 끝났을 때 스크롤 — 이미 구독했거나 이미 스크롤했으면 skip
    if (_routeAnimationListener != null || _scrolledToToday) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return;

    _routeAnimationListener = (AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _removeRouteListener();
        // 렌더링이 완료된 후 스크롤을 보장하기 위해 PostFrameCallback 사용
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
      }
    };
    animation.addStatusListener(_routeAnimationListener!);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _todayKeyStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _selectedCalendarDate = now;

    _calendarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _calendarAnimation = CurvedAnimation(
      parent: _calendarController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );
    
    _scrollController.addListener(_scrollListener);
    
    if (widget.initialData != null) {
      _historyData.addAll(widget.initialData!);
      _isLoading = false;
      // 데이터가 이미 있어도 스크롤은 didChangeDependencies의 route 리스너가 처리
    } else {
      _loadHistory();
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
      // 데이터 로드 후 오늘 날짜로 스크롤 시도 (애니메이션이 이미 끝났을 수도 있으므로)
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
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

  void _toggleCalendar() {
    setState(() {
      _isCalendarOpen = !_isCalendarOpen;
      if (_isCalendarOpen) {
        _calendarController.forward();
      } else {
        _calendarController.reverse();
      }
    });
    HapticFeedback.selectionClick();
  }

  void _onCalendarDateSelected(DateTime date) {
    setState(() {
      _isCalendarOpen = false;
      _calendarController.reverse();
      _selectedCalendarDate = date;
    });

    final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    _scrollToDate(dateKey);
    HapticFeedback.mediumImpact();
  }

  void _scrollListener() {
    if (_todayKeyStr == null) return;
    final ctx = _sectionKeys[_todayKeyStr!]?.currentContext;
    if (ctx == null) {
      if (!_showReturnToToday) setState(() => _showReturnToToday = true);
      return;
    }

    try {
      final RenderBox box = ctx.findRenderObject() as RenderBox;
      final position = box.localToGlobal(Offset.zero).dy;
      
      // 헤더 영역(약 100px)을 기준으로 위아래로 벗어나면 버튼 노출
      final bool shouldShow = (position < 80 || position > MediaQuery.of(context).size.height - 150);
      
      if (shouldShow != _showReturnToToday) {
        setState(() => _showReturnToToday = shouldShow);
      }
    } catch (_) {
      // RenderObject를 찾을 수 없는 경우 등 예외 처리
    }
  }

  bool _isDateActive(DateTime date) {
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _historyData.containsKey(key) && _historyData[key]!.isNotEmpty;
  }

  void _scrollToToday() {
    if (_scrolledToToday || _todayKeyStr == null) return;
    _scrollToDate(_todayKeyStr!, isInitialScroll: true);
  }

  void _scrollToDate(String dateKey, {int retryCount = 0, bool isInitialScroll = false}) {
    final ctx = _sectionKeys[dateKey]?.currentContext;
    if (ctx != null) {
      if (isInitialScroll) _scrolledToToday = true;
      
      // 상단 헤더에 가려지지 않도록 오프셋 계산 (헤더 높이 약 110px 제외)
      final RenderObject? renderObject = ctx.findRenderObject();
      if (renderObject is RenderBox) {
        final viewport = RenderAbstractViewport.of(renderObject);
        if (viewport != null) {
          final double headerOffset = 110.0; // 헤더 높이만큼 여백
          final double targetOffset = viewport.getOffsetToReveal(renderObject, 0.0).offset - headerOffset;
          
          _scrollController.animateTo(
            targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
          );
        }
      }
    } else if (retryCount < 5) {
      // 아직 렌더링이 안 되었을 수 있으므로 잠시 후 재시도
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _scrollToDate(dateKey, retryCount: retryCount + 1, isInitialScroll: isInitialScroll);
      });
    } else if (!isInitialScroll) {
      // 초기 자동 스크롤이 아닌 수동 선택 시에만 알림 표시
      _showGlassNotification('${dateKey.split('-')[1]}월 ${dateKey.split('-')[2]}일은 기록이 없어요.');
    }
  }

  Future<void> _cleanupFutureRepeatingTasks(String taskName) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('bubbles_')).toList();
    
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    for (var key in keys) {
      final dateStr = key.replaceFirst('bubbles_', '');
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
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
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
                bottom: false,
                child: Stack(
                  children: [
                    // 1. 전체 화면 리스트 (가장 아래 레이어)
                    Positioned.fill(
                      child: _historyData.isEmpty 
                        ? (_isLoading ? const SizedBox.shrink() : _buildEmptyState())
                        : _buildHistoryList(),
                    ),
                    
                    // 2. 상단 그라데이션 및 컨트롤 영역 (가장 위 레이어)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF0F172A),
                              const Color(0xFF0F172A).withOpacity(0.9),
                              const Color(0xFF0F172A).withOpacity(0.0),
                            ],
                            stops: const [0.0, 0.6, 1.0],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildHeader(context),
                            
                            // 인라인 달력
                            AnimatedBuilder(
                              animation: _calendarAnimation,
                              builder: (context, child) {
                                final controllerValue = _calendarController.value;
                                final curveValue = _calendarAnimation.value;
                                
                                final screenWidth = MediaQuery.of(context).size.width;
                                final targetWidth = screenWidth - 40;
                                final startWidth = 140.0;
                                
                                final targetHeight = 380.0;
                                final startHeight = 44.0;
                                
                                final currentWidth = lerpDouble(startWidth, targetWidth, curveValue)!;
                                final currentHeight = lerpDouble(startHeight, targetHeight, curveValue)!;
                                final currentRadius = lerpDouble(22, 28, curveValue)!;

                                return Align(
                                  heightFactor: curveValue.clamp(0.0, 1.0),
                                  alignment: Alignment.topCenter,
                                  child: ClipRect(
                                    child: Center(
                                      child: Opacity(
                                        opacity: controllerValue.clamp(0.0, 1.0),
                                        child: Padding(
                                          padding: const EdgeInsets.only(bottom: 20),
                                          child: GlassCalendar(
                                            initialDate: _selectedCalendarDate,
                                            today: DateTime.now(),
                                            onDateSelected: _onCalendarDateSelected,
                                            width: currentWidth,
                                            height: currentHeight,
                                            borderRadius: currentRadius,
                                            animationValue: controllerValue,
                                            isDateEnabled: _isDateActive,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // 오늘로 돌아가기 플로팅 버튼
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildReturnToTodayFloatingBtn(),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReturnToTodayFloatingBtn() {
    return AnimatedSlide(
      offset: _showReturnToToday ? Offset.zero : const Offset(0, 2),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: _showReturnToToday ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 30),
          child: _GlassPressButton(
            onTap: () {
              if (_todayKeyStr != null) {
                _scrollToDate(_todayKeyStr!);
              }
              HapticFeedback.mediumImpact();
            },
            child: GlassmorphicContainer(
              width: 140,
              height: 44,
              borderRadius: 22,
              blur: 15,
              alignment: Alignment.center,
              border: 1,
              linearGradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.05)],
              ),
              borderGradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.1)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.today_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    '오늘로 돌아가기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
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
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              // 달력 버튼 (왼쪽)
              _GlassPressButton(
                onTap: _toggleCalendar,
                child: GlassmorphicContainer(
                  width: 44,
                  height: 44,
                  borderRadius: 22,
                  blur: 15,
                  alignment: Alignment.center,
                  border: 1,
                  linearGradient: LinearGradient(
                    colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.05)],
                  ),
                  borderGradient: LinearGradient(
                    colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.1)],
                  ),
                  child: Icon(
                    _isCalendarOpen ? Icons.keyboard_arrow_up_rounded : Icons.calendar_today_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 닫기 버튼 (오른쪽)
              _GlassPressButton(
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(context);
                },
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
                  child: const Center(
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
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
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.only(left: 20, right: 20, top: 110, bottom: 20),
      child: Column(
        children: [
          ..._historyData.entries.map((entry) {
            // 섹션별 키 할당 (스크롤용)
            final key = _sectionKeys.putIfAbsent(entry.key, () => GlobalKey());
            return _buildDateSection(
              entry.key,
              entry.value,
              key: key,
            );
          }),
          // 오늘 날짜가 마지막 아이템일 때도 최상단에 위치할 수 있도록 여백 추가
          SizedBox(height: MediaQuery.of(context).size.height * 0.5),
        ],
      ),
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
                            fontWeight: FontWeight.w800,
                            fontFamily: 'NanumSquareRound',
                            decoration: null,
                            shadows: [
                              // 폰트 두께 보강용 미세 그림자
                              Shadow(offset: const Offset(-0.4, -0.4), color: Colors.white.withOpacity(0.2)),
                              Shadow(offset: const Offset(0.4, -0.4), color: Colors.white.withOpacity(0.2)),
                              Shadow(offset: const Offset(0.4, 0.4), color: Colors.white.withOpacity(0.2)),
                              Shadow(offset: const Offset(-0.4, 0.4), color: Colors.white.withOpacity(0.2)),
                            ],
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

// ── 글래스 버튼 눌림 이펙트 위젯 ──
class _GlassPressButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _GlassPressButton({required this.child, required this.onTap});

  @override
  State<_GlassPressButton> createState() => _GlassPressButtonState();
}

class _GlassPressButtonState extends State<_GlassPressButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glow;
  bool _pressed = false;
  bool _longPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _glow = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _down(_) {
    setState(() {
      _pressed = true;
      _longPressed = false;
    });
    _controller.forward();
    HapticFeedback.selectionClick();
  }

  void _up(_) {
    setState(() {
      _pressed = false;
      _longPressed = false;
    });
    _controller.reverse();
    widget.onTap();
  }

  void _cancel() {
    setState(() {
      _pressed = false;
      _longPressed = false;
    });
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      onLongPressStart: (_) {
        setState(() => _longPressed = true);
        HapticFeedback.heavyImpact();
      },
      onLongPressEnd: (_) => _cancel(),
      child: AnimatedScale(
        scale: _longPressed ? 1.25 : (_pressed ? 1.15 : 1.0),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: AnimatedBuilder(
          animation: _glow,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                child!,
                // 흰 글로우 오버레이
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: _glow.value,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.5),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
