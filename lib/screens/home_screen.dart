import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo_bubble.dart';
import '../widgets/bubble_widget.dart';
import '../widgets/glass_calendar.dart';
import 'history_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../services/widget_service.dart';
import 'package:home_widget/home_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  List<TodoBubble> _bubbles = [];
  final TextEditingController _taskController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final AudioPlayer _audioPlayer = AudioPlayer();

  late AnimationController _gameLoopController;
  late AnimationController _bgAnimController;
  late Animation<double> _bgAnim;
  late AnimationController _shimmerController;
  Size _screenSize = Size.zero;
  double _lastBottomLimit = 0.0;
  double _lastTopLimit = 0.0;
  int _selectedPriority = 1;
  bool _isRepeating = false;
  final List<TodoBubble> _repeatingTemplates = [];

  // 날짜 관련
  DateTime _today = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  Timer? _midnightTimer;

  bool _isInputFocused = false;
  String? _morphingBubbleId; // 현재 팝업으로 변환 중인 비눗방울 ID
  DateTime? _lastPhysicsTime; // 물리 연산 프레임 제한용
  
  // PageView 관련
  late PageController _pageController;
  static const int _initialPage = 10000;
  int _currentPage = _initialPage;
  final Map<String, List<TodoBubble>> _bubblesByDate = {}; // 날짜별 버블 데이터 캐시
  bool _isCalendarOpen = false; // 달력 확장 여부
  late AnimationController _calendarController;
  late Animation<double> _calendarAnimation;
  bool _isDraggingBubble = false;

  // 날짜 헬퍼
  DateTime get _todayDate => DateTime(_today.year, _today.month, _today.day);
  DateTime get _selectedDateNorm => DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  bool get _isViewingToday => _dateKey(_selectedDate) == _dateKey(_today);
  bool get _isViewingPast => _selectedDateNorm.isBefore(_todayDate);
  bool get _isViewingFuture => _selectedDateNorm.isAfter(_todayDate);

  String get _dateDisplayText {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final d = _selectedDate;
    final wd = weekdays[d.weekday - 1];
    if (_isViewingToday) return '${d.month}월 ${d.day}일 (${wd}) · 오늘';
    final diff = _selectedDateNorm.difference(_todayDate).inDays;
    if (diff == -1) return '${d.month}월 ${d.day}일 (${wd}) · 어제';
    if (diff == 1) return '${d.month}월 ${d.day}일 (${wd}) · 내일';
    return '${d.month}월 ${d.day}일 (${wd})';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _initialPage);
    _today = DateTime.now();
    _selectedDate = _today;
    _loadInitialBubbles();
    _setupMidnightTimer();

    _gameLoopController = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )..addListener(_updatePhysics);
    _gameLoopController.forward();

    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgAnimController, curve: Curves.easeInOut);

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _focusNode.addListener(() {
      setState(() {
        _isInputFocused = _focusNode.hasFocus;
      });
    });

    _calendarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _calendarAnimation = CurvedAnimation(
      parent: _calendarController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _saveBubbles();
    _gameLoopController.dispose();
    _bgAnimController.dispose();
    _shimmerController.dispose();
    _taskController.dispose();
    _focusNode.dispose();
    _audioPlayer.dispose();
    _calendarController.dispose();
    super.dispose();
  }

  void _setupMidnightTimer() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final duration = tomorrow.difference(now);
    _midnightTimer = Timer(duration, () {
      if (mounted) {
        final wasViewingToday = _isViewingToday;
        setState(() {
          _today = DateTime.now();
          if (wasViewingToday) {
            _selectedDate = _today;
            _loadInitialBubbles();
          }
        });
        _setupMidnightTimer();
      }
    });
  }

  void _navigateDate(int direction) async {
    await _saveBubbles();
    _pageController.animateToPage(
      _currentPage + direction,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuart,
    );
  }

  void _onPageChanged(int page) async {
    // 이동 전 현재 날짜의 상태를 저장
    await _saveBubbles();
    
    final diff = page - _initialPage;
    final newDate = DateTime(_today.year, _today.month, _today.day + diff);
    
    setState(() {
      _currentPage = page;
      _selectedDate = newDate;
      // 메모리에 이미 있는 경우 즉시 반영
      _bubbles = _bubblesByDate[_dateKey(newDate)] ?? [];
    });
    
    // 3일치(어제, 오늘, 내일) 데이터만 남기고 나머지는 메모리에서 정리 (발열 방지 최적화)
    _maintainThreeDayCache(newDate);
  }

  /// 현재 날짜를 기준으로 전날, 오늘, 다음날 3일치 데이터만 유지하고 나머지는 캐시에서 제거합니다.
  Future<void> _maintainThreeDayCache(DateTime centerDate) async {
    final currentKey = _dateKey(centerDate);
    final prevKey = _dateKey(centerDate.subtract(const Duration(days: 1)));
    final nextKey = _dateKey(centerDate.add(const Duration(days: 1)));
    final requiredKeys = {prevKey, currentKey, nextKey};

    // 1. 필요한 3일치 데이터 중 로드되지 않은 것 로드
    for (final key in requiredKeys) {
      if (!_bubblesByDate.containsKey(key)) {
        final parts = key.split('-');
        if (parts.length == 3) {
          final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          await _loadBubblesForDate(date);
        }
      }
    }

    // 2. 3일치를 제외한 나머지 날짜는 메모리에서 해제
    final keysToRemove = _bubblesByDate.keys.where((k) => !requiredKeys.contains(k)).toList();
    for (final key in keysToRemove) {
      _bubblesByDate.remove(key);
    }
    
    // 현재 선택된 날짜의 버블 리스트 참조 갱신
    if (mounted) {
      setState(() {
        _bubbles = _bubblesByDate[currentKey] ?? [];
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 앱으로 돌아왔을 때 위젯 등 외부에서 변경된 데이터 반영
      _loadInitialBubbles();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _saveBubbles();
    }
  }

  Future<void> _loadInitialBubbles() async {
    // 0. 위젯에서 전달된 완료 신호 먼저 처리
    try {
      // Android/Common (pending_popped_ids)
      final String? pendingJson = await HomeWidget.getWidgetData<String>('pending_popped_ids');
      List<String> poppedIds = [];
      
      if (pendingJson != null && pendingJson.isNotEmpty && pendingJson != 'null') {
        final dynamic decoded = jsonDecode(pendingJson);
        if (decoded is List) {
          poppedIds.addAll(List<String>.from(decoded));
        }
      }
      
      // iOS Interactive Widget (popped_bubble_id)
      final String? iosPoppedId = await HomeWidget.getWidgetData<String>('popped_bubble_id');
      if (iosPoppedId != null && iosPoppedId.isNotEmpty) {
        if (!poppedIds.contains(iosPoppedId)) {
          poppedIds.add(iosPoppedId);
        }
        // iOS 신호 확인 완료
        await HomeWidget.saveWidgetData('popped_bubble_id', '');
      }

      if (poppedIds.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs.getKeys().where((k) => k.startsWith('bubbles_')).toList();
        
        bool anyChanged = false;
        for (final id in poppedIds) {
          for (final key in keys) {
            final data = prefs.getString(key);
            if (data != null) {
              List<dynamic> list = jsonDecode(data);
              bool changed = false;
              for (var item in list) {
                if (item['id'].toString() == id) {
                  if (item['state'] != 3) {
                    item['state'] = 3;
                    changed = true;
                    anyChanged = true;
                  }
                  break;
                }
              }
              if (changed) {
                await prefs.setString(key, jsonEncode(list));
              }
            }
          }
        }
        
        // 처리 완료 후 신호 비우기
        if (anyChanged) {
          await HomeWidget.saveWidgetData('pending_popped_ids', '');
        }
      }
    } catch (e) {
      debugPrint('Error processing pending widget pops: $e');
    }

    // 앱 시작 시 어제, 오늘, 내일 3일치를 미리 로드
    final today = _today;
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    
    await _loadBubblesForDate(yesterday);
    await _loadBubblesForDate(today);
    await _loadBubblesForDate(tomorrow);
  }

  Future<void> _loadBubblesForDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = 'bubbles_${_dateKey(date)}';
    final String? bubblesJson = prefs.getString(key);
    final String? repeatingJson = prefs.getString('repeating_templates');
    
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    
    List<TodoBubble> loadedBubbles = [];

    if (bubblesJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(bubblesJson);
        for (var item in decoded) {
          final bubble = TodoBubble.fromJson(item);
          if (bubble.state != BubbleState.popping) {
            loadedBubbles.add(bubble);
          }
        }
      } catch (e) {
        debugPrint('Error loading bubbles for $key: $e');
      }
    }

    if (repeatingJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(repeatingJson);
        _repeatingTemplates.clear();
        for (var item in decoded) {
          _repeatingTemplates.add(TodoBubble.fromJson(item));
        }
      } catch (e) {
        debugPrint('Error loading repeating templates: $e');
      }
    }

    // 오늘 혹은 미래 날짜일 경우 반복 할일 보충
    final currentTargetDate = DateTime(date.year, date.month, date.day);
    if (_dateKey(date) == _dateKey(now) || date.isAfter(now)) {
      // 반복 하는 버블들 보충 (이미 있으면 중복 생성 안 함)
      for (var template in _repeatingTemplates) {
        // 시작 날짜가 있고 현재 로드하려는 날짜가 시작 날짜보다 이전이면 패스
        if (template.repeatStartDate != null) {
          final startDate = DateTime(template.repeatStartDate!.year, template.repeatStartDate!.month, template.repeatStartDate!.day);
          if (currentTargetDate.isBefore(startDate)) {
            continue;
          }
        }

        bool exists = loadedBubbles.any((b) => b.task == template.task && b.isRepeating);
        if (!exists) {
          final random = math.Random();
          final startX = _screenSize.width / 2 + (random.nextDouble() - 0.5) * 40;
          final startY = _screenSize.height / 2;
          
          loadedBubbles.add(TodoBubble(
            id: DateTime.now().millisecondsSinceEpoch.toString() + template.id,
            task: template.task,
            priority: template.priority,
            isRepeating: true,
            radius: template.radius,
            position: Offset(startX, startY),
            velocity: Offset((random.nextDouble() - 0.5) * 2, -1.0 - random.nextDouble()),
            state: BubbleState.blowing,
          ));
        }
      }

      // 오늘 날짜인 경우에만 마지막 접속일 갱신
      if (_dateKey(date) == _dateKey(now)) {
        await prefs.setString('last_open_date', now.toIso8601String());
      }
    }

    setState(() {
      final key = _dateKey(date);
      _bubblesByDate[key] = loadedBubbles;
      if (key == _dateKey(_selectedDate)) {
        _bubbles = loadedBubbles;
      }
    });
  }

  Future<void> _saveBubbles() async {
    final prefs = await SharedPreferences.getInstance();
    final String key = 'bubbles_${_dateKey(_selectedDate)}';
    
    // 모든 버블 저장 (popped 포함)
    final String bubblesJson = jsonEncode(_bubbles.map((b) => b.toJson()).toList());
    await prefs.setString(key, bubblesJson);
    
    // 반복 할일 템플릿 저장 (항상 공통)
    final String repeatingJson = jsonEncode(_repeatingTemplates.map((b) => b.toJson()).toList());
    await prefs.setString('repeating_templates', repeatingJson);

    // 위젯 갱신 (오늘 날짜인 경우에만)
    if (_isViewingToday) {
      await WidgetService.updateWidgetData(_bubbles);
    }
  }

  void _updatePhysics() {
    if (!mounted) return;

    final now = DateTime.now();
    if (_lastPhysicsTime != null) {
      // 프레임 레이트 제한 (최대 30fps) - 발열 방지를 위해 더 완화
    if (now.difference(_lastPhysicsTime!).inMilliseconds < 35) return;
    }
    _lastPhysicsTime = now;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    const inputBarHeight = 110.0;
    final inputBarBottom = bottomInset > 0 ? bottomInset + 16 : 32.0;
    
    // 키보드가 올라와 있을 때는 하단 충돌 제한을 해제하여 비눗방울이 갇히지 않게 함
    final bottomLimit = bottomInset > 0 
        ? _screenSize.height + 100 
        : _screenSize.height - inputBarBottom - inputBarHeight;
    
    final topLimit = MediaQuery.of(context).padding.top + 70.0;
    
    _lastBottomLimit = bottomLimit;
    _lastTopLimit = topLimit;

    // 현재 스와이프 중인지 확인 (소수점 자리가 있으면 스와이프 중)
    double pageOffset = _currentPage.toDouble();
    if (_pageController.hasClients && _pageController.position.haveDimensions) {
      pageOffset = _pageController.page ?? _currentPage.toDouble();
    }
    final bool isSwiping = (pageOffset - pageOffset.round()).abs() > 0.01;

    final currentKey = _dateKey(_selectedDate);
    final List<String> keysToUpdate = [currentKey];

    // 스와이프 중일 때만 인접한 페이지의 물리 연산 수행
    if (isSwiping) {
      keysToUpdate.add(_dateKey(_selectedDate.subtract(const Duration(days: 1))));
      keysToUpdate.add(_dateKey(_selectedDate.add(const Duration(days: 1))));
    }
    
    for (final key in keysToUpdate) {
      final bubbles = _bubblesByDate[key];
      if (bubbles == null || bubbles.isEmpty) continue;

      for (int i = 0; i < bubbles.length; i++) {
        final bubble = bubbles[i];
        if (bubble.state != BubbleState.popping && bubble.state != BubbleState.popped) { 
          bubble.update(_screenSize, bottomLimit: bottomLimit, topLimit: topLimit);
        }
      }
      
      for (int i = 0; i < bubbles.length; i++) {
        final a = bubbles[i];
        if (a.state == BubbleState.popping || a.state == BubbleState.popped) continue;

        for (int j = i + 1; j < bubbles.length; j++) {
          final b = bubbles[j];
          if (b.state == BubbleState.popping || b.state == BubbleState.popped) continue;

          final dx = b.position.dx - a.position.dx;
          final dy = b.position.dy - a.position.dy;
          final distSq = dx * dx + dy * dy;
          final minDist = a.radius + b.radius;

          if (distSq < minDist * minDist && distSq > 0) {
            final dist = math.sqrt(distSq);
            final nx = dx / dist;
            final ny = dy / dist;

            final overlap = (minDist - dist) / 2.0;
            a.position = Offset(a.position.dx - nx * overlap, a.position.dy - ny * overlap);
            b.position = Offset(b.position.dx + nx * overlap, b.position.dy + ny * overlap);

            final dvx = a.velocity.dx - b.velocity.dx;
            final dvy = a.velocity.dy - b.velocity.dy;
            final dot = dvx * nx + dvy * ny;

            if (dot > 0) {
              const restitution = 0.75;
              final impulse = dot * restitution;
              a.velocity = Offset(a.velocity.dx - impulse * nx, a.velocity.dy - impulse * ny);
              b.velocity = Offset(b.velocity.dx + impulse * nx, b.velocity.dy + impulse * ny);

              final spdA = a.velocity.distance;
              if (spdA > 1.5) a.velocity = a.velocity / spdA * 1.5;
              final spdB = b.velocity.distance;
              if (spdB > 1.5) b.velocity = b.velocity / spdB * 1.5;
            }
          }
        }
      }
    }
  }

  void _addTodo(String task) {
    if (task.trim().isEmpty) return;

    HapticFeedback.lightImpact();

    final random = math.Random();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final inputBarBottom = bottomInset > 0 ? bottomInset + 16 : 32.0;
    final startX = _screenSize.width / 2 + (random.nextDouble() - 0.5) * 40;
    final startY = _screenSize.height - inputBarBottom - 160; // 입력창 위쪽에서 생성

    final velocityX = (random.nextDouble() - 0.5) * 1.5;
    final velocityY = -random.nextDouble() * 2.0 - 1.5;

    // 중요도에 따른 반지름 결정 (1:최대, 4:최소)
    double radius;
    switch (_selectedPriority) {
      case 1: radius = 85.0; break;
      case 2: radius = 70.0; break;
      case 3: radius = 55.0; break;
      case 4: radius = 40.0; break;
      default: radius = 60.0;
    }

    final newBubble = TodoBubble(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      task: task.trim(),
      position: Offset(startX, startY),
      velocity: Offset(velocityX, velocityY),
      radius: radius,
      priority: _selectedPriority,
      isRepeating: _isRepeating,
      repeatStartDate: _isRepeating ? _selectedDateNorm : null, // 해당 날짜 이후부터 반복
      state: BubbleState.blowing,
    );

    setState(() {
      _bubbles.add(newBubble);
      if (_isRepeating) {
        _repeatingTemplates.add(newBubble);
      }
      _isRepeating = false; // 추가 후 초기화
    });
    
    _saveBubbles();
    _taskController.clear();
  }


  void _showBubbleEditDialog(TodoBubble bubble, Offset startPos) {
    setState(() {
      _morphingBubbleId = bubble.id;
      _isDraggingBubble = false; // 드래그 중이었다면 상태 해제
      bubble.velocity = Offset.zero; // 속도 초기화
    });
    
    final TextEditingController editController = TextEditingController(text: bubble.task);
    int selectedPriority = bubble.priority;
    bool isRepeating = bubble.isRepeating;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.3), // 배경을 살짝 어둡게
      transitionDuration: const Duration(milliseconds: 550),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCirc,
        );
        
        // 전달받은 startPos(글로벌 좌표)를 그대로 사용 (데이터 좌표로 덮어쓰지 않음)
        Offset currentBubblePos = startPos;

        const dialogWidth = 320.0;
        const dialogHeight = 440.0; // 높이 상향 (아이콘 및 여백)
        final targetPos = Offset(_screenSize.width / 2, _screenSize.height / 2);

        final currentPos = Offset.lerp(currentBubblePos, targetPos, curve.value)!;
        final currentWidth = lerpDouble(bubble.radius * 2, dialogWidth, curve.value)!;
        final currentHeight = lerpDouble(bubble.radius * 2, dialogHeight, curve.value)!;
        final currentRadius = lerpDouble(bubble.radius, 32, curve.value)!;
        
        return Stack(
          children: [
            Positioned(
              left: currentPos.dx - currentWidth / 2,
              top: currentPos.dy - currentHeight / 2,
              child: GlassmorphicContainer(
                width: currentWidth,
                height: currentHeight,
                borderRadius: currentRadius,
                blur: 20,
                alignment: Alignment.center,
                border: 0.8,
                linearGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.08)],
                ),
                borderGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withOpacity(0.5), Colors.white.withOpacity(0.1)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(currentRadius),
                  child: OverflowBox(
                    minWidth: dialogWidth,
                    maxWidth: dialogWidth,
                    minHeight: dialogHeight,
                    maxHeight: dialogHeight,
                    alignment: Alignment.topCenter,
                    child: Material(
                      color: Colors.transparent,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Container(
                          width: dialogWidth,
                          height: dialogHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0), // 24 -> 20
                          child: Opacity(
                            opacity: ((curve.value - 0.2) / 0.8).clamp(0.0, 1.0), // 좀 더 부드럽게
                            child: StatefulBuilder(
                            builder: (context, setDialogState) {
                              return Column(
                                children: [
                                  const Icon(Icons.edit_note_rounded, color: Colors.white, size: 38),
                                  const SizedBox(height: 8), // 10 -> 8
                                  const Text(
                                    '할 일 수정',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16), // 20 -> 16
                                
                                // 텍스트 수정 필드
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                                  ),
                                  child: TextField(
                                    controller: editController,
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Pretendard'),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      hintText: '무엇을 해야 하나요?',
                                      hintStyle: TextStyle(color: Colors.white38),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20), // 24 -> 20
                                
                                // 중요도 라벨
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4, bottom: 8), // 10 -> 8
                                    child: Text(
                                      '중요도',
                                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                                
                                // 중요도 선택
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [1, 2, 3, 4].map((p) {
                                    final isSel = selectedPriority == p;
                                    final color = TodoBubble.getPriorityColor(p);
                                    return GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setDialogState(() => selectedPriority = p);
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        width: 56, // 58 -> 56으로 소폭 축소하여 오버플로우 방지
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: isSel ? color.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSel ? color : Colors.white.withOpacity(0.1),
                                            width: isSel ? 2 : 1,
                                          ),
                                          boxShadow: isSel ? [
                                            BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)
                                          ] : null,
                                        ),
                                        child: Center(
                                          child: Text(
                                            'P$p',
                                            style: TextStyle(
                                              color: isSel ? Colors.white : Colors.white38,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 20), // 24 -> 20
                                
                                // 반복 여부 토글
                                _buildDialogToggle('매일 반복', isRepeating, (v) => setDialogState(() => isRepeating = v)),
                                
                                const Spacer(),
                                
                                // 하단 버튼
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () {
                                          FocusScope.of(context).unfocus();
                                          Navigator.pop(context);
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                        child: const Text('취소', style: TextStyle(color: Colors.white60, fontSize: 16)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () {
                                          FocusScope.of(context).unfocus();
                                          _updateBubble(bubble, editController.text, selectedPriority, isRepeating);
                                          Navigator.pop(context);
                                          _showGlassNotification('수정 완료! ✨');
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueAccent.withOpacity(0.8),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        ),
                                        child: const Text('저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }
                        ),
                        ),
                      ),
                    ),
                  ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      FocusScope.of(context).unfocus(); // 팝업이 닫힐 때 확실히 키보드 내리기
      Future.delayed(const Duration(milliseconds: 520), () {
        if (mounted) {
          setState(() => _morphingBubbleId = null);
        }
      });
    });
  }

  Widget _buildDialogToggle(String label, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            value ? Icons.sync_rounded : Icons.sync_disabled_rounded,
            color: value ? Colors.blueAccent : Colors.white38,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label, 
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blueAccent,
            activeTrackColor: Colors.blueAccent.withOpacity(0.3),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // 공간 절약
          ),
        ],
      ),
    );
  }


  void _updateBubble(TodoBubble bubble, String newTask, int newPriority, bool newRepeating) {
    setState(() {
      final oldTask = bubble.task;
      final oldRepeating = bubble.isRepeating;

      // 1. 버블 자체 속성 변경
      final List<TodoBubble> list = _bubbles;
      final idx = list.indexWhere((b) => b.id == bubble.id);
      if (idx != -1) {
        final b = list[idx];
        // 텍스트 업데이트
        final taskValue = newTask.trim().isEmpty ? b.task : newTask.trim();
        
        // 중요도 변경에 따른 반지름 업데이트
        double newRadius;
        switch (newPriority) {
          case 1: newRadius = 85.0; break;
          case 2: newRadius = 70.0; break;
          case 3: newRadius = 55.0; break;
          case 4: newRadius = 40.0; break;
          default: newRadius = 60.0;
        }

        list[idx] = TodoBubble(
          id: b.id,
          task: taskValue,
          state: b.state,
          position: b.position,
          velocity: b.velocity,
          radius: newRadius,
          priority: newPriority,
          isRepeating: newRepeating,
          repeatStartDate: newRepeating ? (b.repeatStartDate ?? _selectedDateNorm) : null,
          createdAt: b.createdAt,
          tintColor: TodoBubble.getPriorityColor(newPriority),
        );
      }

      // 2. 반복 템플릿 관리
      if (oldRepeating && !newRepeating) {
        _repeatingTemplates.removeWhere((t) => t.task == oldTask);
        _cleanupFutureRepeatingTasks(oldTask);
      } else if (!oldRepeating && newRepeating) {
        _repeatingTemplates.add(list[idx]);
      } else if (oldRepeating && newRepeating) {
        // 기존 반복 수정
        final tIdx = _repeatingTemplates.indexWhere((t) => t.task == oldTask);
        if (tIdx != -1) _repeatingTemplates[tIdx] = list[idx];
        // 만약 이름이 바뀌었다면 이전 이름의 미래 데이터 정리 (옵션)
      }
    });
    _saveBubbles();
  }

  void _popBubble(TodoBubble bubble) async {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (isKeyboardOpen) return; // 키보드가 열려있으면 터뜨릴 수 없음

    HapticFeedback.mediumImpact();

    setState(() {
      bubble.state = BubbleState.popping;
      _isDraggingBubble = false; // 터뜨릴 때 드래그 상태 해제하여 스와이프 복구
    });

    try {
      // 짧고 맑은 '톡' 소리 재생
      // assets/sounds/pop.mp3 파일이 준비되었다고 가정
      await _audioPlayer.play(AssetSource('sounds/pop.mp3'));
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }

    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) {
        setState(() {
          // 제거 대신 상태만 popped로 변경하여 데이터 유지
          bubble.state = BubbleState.popped;
        });
        _saveBubbles();
      }
    });
  }


  Future<void> _cleanupFutureRepeatingTasks(String taskName) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('bubbles_')).toList();
    
    // 현재 선택된 날짜와 같거나 이후인 모든 날짜 데이터에서 해당 할 일 삭제
    final selectedKey = _dateKey(_selectedDate);
    
    for (var key in keys) {
      final dateStr = key.replaceFirst('bubbles_', '');
      if (dateStr.compareTo(selectedKey) >= 0) {
        final jsonStr = prefs.getString(key);
        if (jsonStr != null) {
          final List<dynamic> decoded = jsonDecode(jsonStr);
          final bubbles = decoded.map((item) => TodoBubble.fromJson(item)).toList();
          
          final initialCount = bubbles.length;
          bubbles.removeWhere((b) => b.task == taskName);
          
          if (bubbles.length != initialCount) {
            await prefs.setString(key, jsonEncode(bubbles.map((b) => b.toJson()).toList()));
            // 캐시에서도 삭제
            _bubblesByDate.remove(dateStr);
          }
        }
      }
    }
    
    // 현재 화면의 비눗방울에서도 삭제 (만약 현재 날짜가 선택된 날짜와 같다면)
    setState(() {
      _bubbles.removeWhere((b) => b.task == taskName);
    });
  }

  Widget _buildDialogContent(BuildContext context, TodoBubble bubble) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.sync_disabled_rounded, color: Colors.white, size: 36),
        const SizedBox(height: 16),
        const Text(
          '반복 해제',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '\"${bubble.task}\"\n이 할 일을 더 이상 반복하지 않을까요?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 15,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('취소', style: TextStyle(color: Colors.white60)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  final taskToDelete = bubble.task;
                  setState(() {
                    _repeatingTemplates.removeWhere((t) => t.task == taskToDelete);
                  });
                  _saveBubbles();
                  _cleanupFutureRepeatingTasks(taskToDelete); // 미래 데이터 정리
                  Navigator.pop(context);
                  _showGlassNotification('이제 더 이상 반복되지 않아요.');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.8),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('해제하기'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
            // ── 배경 및 빈 공간 터치 처리 ──
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  FocusScope.of(context).unfocus();
                  if (_isCalendarOpen) {
                    _showCalendarDialog(); // 애니메이션과 함께 닫기
                  }
                },

                behavior: HitTestBehavior.opaque,
                child: RepaintBoundary(
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF0F172A),
                              Color(0xFF0B1120),
                            ],
                          ),
                        ),
                      ),
                      // 정적인 광원 (연산량 감소)
                      Positioned(
                        top: 100,
                        left: -100,
                        child: _buildGlowOrb(const Color(0xFF4488FF), 400, 0.4),
                      ),
                      Positioned(
                        bottom: -150,
                        right: -100,
                        child: _buildGlowOrb(const Color(0xFF88CCFF), 500, 0.3),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 비눗방울들 (PageView) ──
            IgnorePointer(
              ignoring: bottomInset > 0,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: _isDraggingBubble ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  final diff = index - _initialPage;
                  final date = DateTime(_today.year, _today.month, _today.day + diff);
                  final dateKey = _dateKey(date);
                  
                  // 해당 날짜의 버블 데이터가 없으면 로드 시도
                  if (!_bubblesByDate.containsKey(dateKey)) {
                    _loadBubblesForDate(date);
                    return const SizedBox.shrink();
                  }

                  final bubbles = _bubblesByDate[dateKey]!;
                  final isCurrentPage = index == _currentPage;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      // 실제 렌더링 영역의 너비를 물리 엔진에 반영
                      final actualSize = Size(constraints.maxWidth, constraints.maxHeight);
                      
                      return AnimatedBuilder(
                        animation: _pageController,
                        builder: (context, child) {
                          double value = 1.0;
                          if (_pageController.position.haveDimensions) {
                            value = _pageController.page! - index;
                            value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                          }

                          return Transform.scale(
                            scale: value,
                            child: Opacity(
                              opacity: value,
                              child: AnimatedBuilder(
                                animation: _gameLoopController,
                                builder: (context, _) {
                                  return Stack(
                                    children: bubbles
                                        .where((b) => b.state != BubbleState.popped && b.id != _morphingBubbleId)
                                        .map((bubble) {
                                      // 물리 연산은 _updatePhysics에서 일괄 처리하므로 여기서는 위치만 표시
                                      
                                      return Positioned(
                                        left: bubble.position.dx - (bubble.radius * 1.25),
                                        top: bubble.position.dy - (bubble.radius * 1.25),
                                        child: BubbleWidget(
                                          key: ValueKey(bubble.id),
                                          bubble: bubble,
                                          shimmerController: _shimmerController,
                                          onPop: () => _popBubble(bubble),
                                          onLongPress: (pos) => _showBubbleEditDialog(bubble, pos),
                                          onDragStart: (pos) => _handleBubbleDragStart(bubble),
                                          onPanDown: () => _handleBubblePanDown(),
                                          onTapUp: () => _handleBubbleInteractionEnd(),
                                          onTapCancel: () => _handleBubbleInteractionEnd(),
                                          onPanCancel: () => _handleBubbleInteractionEnd(),
                                          onDragUpdate: (pos) => _handleBubbleDragUpdate(bubble, pos),
                                          onDragEnd: (vel) => _handleBubbleDragEnd(bubble, vel),
                                          isReadOnly: false, 
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      );
                    }
                  );
                },
              ),
            ),

            // ── 상단 정보 바 ──
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 이전날 버튼
                        _buildNavButton(Icons.chevron_left_rounded, () => _navigateDate(-1)),
                        
                        // 오늘 날짜 칩 및 기록 버튼 (중첩)
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildNavButton(Icons.list_alt_rounded, () {
                                // 일반 탭 시 기본 이동
                                _goToHistory(context);
                              }, onLongPress: () {
                                // 꾹 눌렀을 때도 동일하게 이동 (요청 사항)
                                _goToHistory(context);
                                HapticFeedback.heavyImpact();
                              }),
                              const SizedBox(width: 12),
                              _buildGlassDateChip(_dateDisplayText, () {
                                _showCalendarDialog();
                              }),
                            ],
                          ),
                        ),

                        // 다음날 버튼
                        _buildNavButton(Icons.chevron_right_rounded, () => _navigateDate(1)),
                      ],
                    ),
                  ),
                  
                  // 인라인 달력 (날짜로부터 쭈욱 늘어나는 모핑 애니메이션)
                  AnimatedBuilder(
                    animation: _calendarAnimation,
                    builder: (context, child) {
                      if (_calendarController.value == 0) return const SizedBox.shrink();
                      
                      final controllerValue = _calendarController.value;
                      final curveValue = _calendarAnimation.value;
                      
                      final screenWidth = MediaQuery.of(context).size.width;
                      final targetWidth = screenWidth - 40;
                      final startWidth = 200.0; // Date Chip 너비
                      
                      final targetHeight = 380.0;
                      final startHeight = 44.0; // Date Chip 높이
                      
                      final currentWidth = lerpDouble(startWidth, targetWidth, curveValue)!;
                      final currentHeight = lerpDouble(startHeight, targetHeight, curveValue)!;
                      final currentRadius = lerpDouble(25, 28, curveValue)!;

                      return Opacity(
                        opacity: controllerValue.clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: GlassCalendar(
                            initialDate: _selectedDate,
                            today: _today,
                            onDateSelected: _onCalendarDateSelected,
                            width: currentWidth,
                            height: currentHeight,
                            borderRadius: currentRadius,
                            animationValue: controllerValue,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ── 우측 하단 카운트 칩 (달력 열릴 때 위치 조정) ──
            if (_bubbles.any((b) => b.state != BubbleState.popped && b.state != BubbleState.popping))
              AnimatedBuilder(
                animation: _calendarAnimation,
                builder: (context, child) {
                  return Positioned(
                    top: MediaQuery.of(context).padding.top + 72 + (_calendarAnimation.value * 390),
                    right: 20,
                    child: child!,
                  );
                },
                child: GlassmorphicContainer(
                  width: 68,
                  height: 34,
                  borderRadius: 17,
                  blur: 15,
                  alignment: Alignment.center,
                  border: 0.8,
                  linearGradient: LinearGradient(
                    colors: [Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.08)],
                  ),
                  borderGradient: LinearGradient(
                    colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.1)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bubble_chart_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${_bubbles.where((b) => b.state != BubbleState.popped && b.state != BubbleState.popping).length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── 하단 입력창 ──
            if (!_isViewingPast)
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomInset > 0 ? bottomInset + 16 : 32,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: RepaintBoundary(child: _buildBottomInputBar()),
                ),
              ),
            
            // 과거 날짜 안내 메시지
            if (_isViewingPast)
              Positioned(
                bottom: bottomInset > 0 ? bottomInset + 16 : 50,
                left: 0,
                right: 0,
                child: Center(
                  child: _buildGlassChip('과거 기록도 터뜨릴 수 있어요! ✨', width: 220),
                ),
              ),
            
            // 오늘로 돌아가기 버튼
            if (!_isViewingToday)
              Positioned(
                bottom: _isViewingPast 
                    ? (bottomInset > 0 ? bottomInset + 80 : 100)
                    : (bottomInset > 0 ? bottomInset + 165 : 165),
                left: 0,
                right: 0,
                child: Center(
                  child: _buildReturnToTodayBtn(),
                ),
              ),
          ],
        ),
    );
  }

  void _showCalendarDialog() {
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
    });
    
    final diff = DateTime(date.year, date.month, date.day)
        .difference(DateTime(_today.year, _today.month, _today.day))
        .inDays;
    
    _pageController.animateToPage(
      _initialPage + diff,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuart,
    );
    
    HapticFeedback.mediumImpact();
  }

  Widget _buildReturnToTodayBtn() {
    return _GlassPressButton(
      onTap: () {
        // 즉시 setState를 하지 않고 PageView 애니메이션에 맡깁니다.
        // (즉시 변경 시 데이터 저장 로직과 충돌하여 UI 깜빡임 발생)
        _pageController.animateToPage(
          _initialPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutQuart,
        );
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
    );
  }

  void _goToHistory(BuildContext context) async {
    _focusNode.unfocus(); // 이동 전 키보드 해제
    await _saveBubbles();
    if (!mounted) return;

    // 이동 전에 데이터를 미리 로드하여 애니메이션 중에도 리스트가 바로 보이게 함
    final historyData = await _getHistoryData();
    if (!mounted) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => HistoryScreen(initialData: historyData),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 0.12); // 살짝 아래에서 위로
          const end = Offset.zero;
          const curve = Curves.easeOutQuart;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: offsetAnimation,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    ).then((_) {
      if (mounted) {
        FocusScope.of(context).unfocus();
        _bubblesByDate.clear();
        _loadInitialBubbles();
      }
    });
  }

  Future<Map<String, List<TodoBubble>>> _getHistoryData() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, List<TodoBubble>> historyData = {};
    
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
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
      historyData[date] = bubbles;
    }
    return historyData;
  }

  void _handleBubblePanDown() {
    setState(() {
      _isDraggingBubble = true;
    });
  }

  void _handleBubbleInteractionEnd() {
    if (_isDraggingBubble) {
      setState(() {
        _isDraggingBubble = false;
      });
    }
  }

  void _handleBubbleDragStart(TodoBubble bubble) {
    setState(() {
      _isDraggingBubble = true;
      bubble.velocity = Offset.zero;
    });
  }

  void _handleBubbleDragUpdate(TodoBubble bubble, Offset globalPos) {
    // 손으로 잡고 이동하는 기능을 제거하기 위해 위치 업데이트를 하지 않습니다.
    // 대신 드래그 중임을 유지하여 PageView 스크롤을 방지합니다.
  }

  void _handleBubbleDragEnd(TodoBubble bubble, Offset velocity) {
    setState(() {
      _isDraggingBubble = false;
      // Flick 속도 적용 (비율 대폭 상향 300 -> 120)
      double vx = velocity.dx / 120;
      double vy = velocity.dy / 120;
      
      final speed = math.sqrt(vx * vx + vy * vy);
      if (speed > 10.0) {
        vx = (vx / speed) * 10.0;
        vy = (vy / speed) * 10.0;
      } else if (speed > 0.05 && speed < 0.8) {
        // 저속 발사 시 최소 속도(0.8)를 보장하여 '안 날아가는' 느낌 해결
        vx = (vx / speed) * 0.8;
        vy = (vy / speed) * 0.8;
      }
      
      bubble.velocity = Offset(vx, vy);
    });
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap, {VoidCallback? onLongPress}) {
    final bool isHistoryIcon = icon == Icons.list_alt_rounded;
    
    Widget button = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.1),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Icon(icon, color: Colors.white.withOpacity(0.8)),
    );

    // 기록 아이콘인 경우 Hero 태그 부여
    if (isHistoryIcon) {
      button = Hero(
        tag: 'history_transition',
        child: Material(
          color: Colors.transparent,
          child: button,
        ),
      );
    }

    return _GlassPressButton(
      onTap: onTap,
      onLongPress: onLongPress,
      child: button,
    );
  }

  Widget _buildGlassDateChip(String label, VoidCallback onTap) {
    return _GlassPressButton(
      onTap: onTap,
      child: GlassmorphicContainer(
        width: 200, // 넓이 대략 설정
        height: 44,
        borderRadius: 25,
        blur: 15,
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.05)],
        ),
        borderGradient: LinearGradient(
          colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.1)],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlowOrb(Color color, double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.18 * opacity),
            color.withOpacity(0.0),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassChip(String label, {double width = 70}) {
    return GlassmorphicContainer(
      width: width,
      height: 32,
      borderRadius: 20,
      blur: 10,
      alignment: Alignment.center,
      border: 0.5,
      linearGradient: LinearGradient(
        colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.05)],
      ),
      borderGradient: LinearGradient(
        colors: [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.1)],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomInputBar() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;

    return GlassmorphicContainer(
      width: _screenSize.width - 40,
      height: 120, 
      borderRadius: 28,
      blur: 20,
      alignment: Alignment.center,
      border: 1,
      linearGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(_isInputFocused ? 0.15 : 0.08),
          Colors.white.withOpacity(_isInputFocused ? 0.08 : 0.04),
        ],
      ),
      borderGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.4),
          Colors.white.withOpacity(0.1),
        ],
      ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(), // 애니메이션 중 오버플로우 방지
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              // 위젯 구조 안정화를 위해 Opacity와 IgnorePointer 사용 (제거 시 포커스 잃음 방지)
              // 중요도/반복 옵션 바 애니메이션 개선
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: 1.0,
                child: IgnorePointer(
                  ignoring: false,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.fastOutSlowIn,
                    height: 52,
                    child: ClipRect(
                      child: OverflowBox(
                        minHeight: 52,
                        maxHeight: 52,
                        alignment: Alignment.bottomCenter, // 상단에서 슬라이드되며 나타나는 효과
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ...[1, 2, 3, 4].map((p) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: _buildPriorityButton(p),
                              )).toList(),
                              const SizedBox(width: 20),
                              _buildRepeatToggle(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _taskController,
                        focusNode: _focusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.2,
                        ),
                        decoration: InputDecoration(
                          hintText: '할 일을 입력하세요...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (value) {
                          _addTodo(value);
                          _focusNode.requestFocus();
                        },
                        textInputAction: TextInputAction.send,
                        cursorColor: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    _buildSendButton(),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              ],
            ),
          ),
    );
  }

  Widget _buildSendButton() {
    return _GlassPressButton(
      onTap: () {
        _addTodo(_taskController.text);
        _focusNode.unfocus();
      },
      child: GlassmorphicContainer(
        width: 44,
        height: 44,
        borderRadius: 22,
        blur: 10,
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          colors: _isInputFocused
              ? [const Color(0xFF4488FF).withOpacity(0.4), const Color(0xFF2255CC).withOpacity(0.2)]
              : [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)],
        ),
        borderGradient: LinearGradient(
          colors: _isInputFocused
              ? [const Color(0xFF88BBFF).withOpacity(0.5), const Color(0xFF4488FF).withOpacity(0.2)]
              : [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.1)],
        ),
        child: Center(
          child: Icon(
            Icons.bubble_chart_rounded,
            color: _isInputFocused ? Colors.white : Colors.white.withOpacity(0.5),
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildRepeatToggle() {
    return _GlassPressButton(
      onTap: () => setState(() => _isRepeating = !_isRepeating),
      child: GlassmorphicContainer(
        width: 60,
        height: 36,
        borderRadius: 16,
        blur: 10,
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          colors: _isRepeating
              ? [Colors.white.withOpacity(0.25), Colors.white.withOpacity(0.1)]
              : [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.02)],
        ),
        borderGradient: LinearGradient(
          colors: [Colors.white.withOpacity(_isRepeating ? 0.6 : 0.2), Colors.white.withOpacity(0.1)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isRepeating ? Icons.sync_rounded : Icons.sync_disabled_rounded,
              size: 16,
              color: _isRepeating ? Colors.white : Colors.white.withOpacity(0.5),
            ),
            const SizedBox(width: 4),
            Text(
              '매일',
              style: TextStyle(
                color: _isRepeating ? Colors.white : Colors.white.withOpacity(0.5),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityButton(int priority) {
    final bool selected = _selectedPriority == priority;
    final Color priorityColor = TodoBubble.getPriorityColor(priority);
    
    return _GlassPressButton(
      onTap: () => setState(() => _selectedPriority = priority),
      child: GlassmorphicContainer(
        width: 36,
        height: 36,
        borderRadius: 18,
        blur: 10,
        alignment: Alignment.center,
        border: selected ? 2.0 : 1.0,
        linearGradient: LinearGradient(
          colors: selected
              ? [priorityColor.withOpacity(0.4), priorityColor.withOpacity(0.1)]
              : [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.04)],
        ),
        borderGradient: LinearGradient(
          colors: selected
              ? [priorityColor.withOpacity(0.8), priorityColor.withOpacity(0.3)]
              : [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)],
        ),
        child: Center(
          child: Text(
            '$priority',
            style: TextStyle(
              color: selected ? Colors.white : Colors.white.withOpacity(0.4),
              fontSize: 14,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              shadows: selected ? [
                Shadow(
                  color: priorityColor.withOpacity(0.8),
                  blurRadius: 8,
                ),
              ] : null,
            ),
          ),
        ),
      ),
    );
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


class _GlassPressButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _GlassPressButton({
    super.key, 
    required this.child, 
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_GlassPressButton> createState() => _GlassPressButtonState();
}

class _GlassPressButtonState extends State<_GlassPressButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  bool _isLongPressed = false;
  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _glowAnim = CurvedAnimation(parent: _glowController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _onDown(_) {
    HapticFeedback.selectionClick();
    setState(() {
      _isPressed = true;
      _isLongPressed = false;
    });
    _glowController.forward();
  }

  void _onUp(_) {
    setState(() {
      _isPressed = false;
      _isLongPressed = false;
    });
    _glowController.reverse();
    widget.onTap();
  }

  void _onCancel() {
    setState(() {
      _isPressed = false;
      _isLongPressed = false;
    });
    _glowController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onDown,
      onTapUp: _onUp,
      onTapCancel: _onCancel,
      onLongPressStart: (_) {
        setState(() => _isLongPressed = true);
        HapticFeedback.heavyImpact();
        if (widget.onLongPress != null) widget.onLongPress!();
      },
      onLongPressEnd: (_) => _onCancel(),
      child: AnimatedScale(
        scale: _isLongPressed ? 1.25 : (_isPressed ? 1.15 : 1.0),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                child!,
                // 글래스 하이라이트 오버레이
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: _glowAnim.value,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.45),
                              Colors.white.withOpacity(0.0),
                            ],
                            stops: const [0.0, 1.0],
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
