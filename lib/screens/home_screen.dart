import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo_bubble.dart';
import '../widgets/bubble_widget.dart';
import 'history_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:glassmorphism/glassmorphism.dart';

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
  int _selectedPriority = 1;
  bool _isRepeating = false;
  final List<TodoBubble> _repeatingTemplates = [];

  // 날짜 관련
  DateTime _today = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  final Map<String, List<TodoBubble>> _bubblesCache = {};
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
    _loadBubbles();
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
            _loadBubbles();
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
    await _saveBubbles();
    final diff = page - _initialPage;
    setState(() {
      _currentPage = page;
      _selectedDate = DateTime(_today.year, _today.month, _today.day + diff);
      // _bubbles는 현재 선택된 날짜의 버블들을 가리킴 (기존 로직 호환성 유지)
      _bubbles = _bubblesByDate[_dateKey(_selectedDate)] ?? [];
    });
    
    if (!_bubblesByDate.containsKey(_dateKey(_selectedDate))) {
      _loadBubblesForDate(_selectedDate);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _saveBubbles();
    }
  }

  Future<void> _loadBubbles() async {
    _loadBubblesForDate(_selectedDate);
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
          final random = Random();
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
  }

  void _updatePhysics() {
    if (!mounted) return;

    final now = DateTime.now();
    if (_lastPhysicsTime != null) {
      if (now.difference(_lastPhysicsTime!).inMilliseconds < 16) return;
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

    // 최적화: 모든 날짜가 아닌 현재 보이고 있는 페이지와 양옆 페이지의 버블만 연산
    final currentKey = _dateKey(_selectedDate);
    final prevKey = _dateKey(_selectedDate.subtract(const Duration(days: 1)));
    final nextKey = _dateKey(_selectedDate.add(const Duration(days: 1)));
    
    for (final key in [prevKey, currentKey, nextKey]) {
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
            final dist = sqrt(distSq);
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

    final random = Random();
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

  void _popBubble(TodoBubble bubble) async {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (isKeyboardOpen) return; // 키보드가 열려있으면 터뜨릴 수 없음

    HapticFeedback.mediumImpact();

    setState(() {
      bubble.state = BubbleState.popping;
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

  void _toggleRepeat(TodoBubble bubble, Offset startPos) {
    if (!bubble.isRepeating) return;

    setState(() => _morphingBubbleId = bubble.id);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent, // 배경 어둡게 하지 않음
      transitionDuration: const Duration(milliseconds: 550),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCirc, // 닫힐 때는 더 빠르게 빨려 들어가는 느낌
        );
        
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        
        // 실시간 현재 비눗방울 위치 찾기 (닫힐 때 위치 동기화)
        Offset currentBubblePos = startPos;
        try {
          final liveBubble = _bubbles.firstWhere((b) => b.id == bubble.id);
          currentBubblePos = liveBubble.position;
        } catch (_) {}

        // 다이얼로그 크기 충분히 확보 (오버플로우 방지)
        const dialogWidth = 320.0;
        const dialogHeight = 280.0; // 높이 축소 (하단 빈 공간 제거)
        // _screenSize를 직접 사용하여 HomeScreen의 좌표계와 일치시킴
        final targetPos = Offset(_screenSize.width / 2, _screenSize.height / 2);

        // 닫힐 때는 실시간 위치(currentBubblePos)로, 열릴 때는 시작 위치(startPos) 기반으로  lerp
        // 사실 항상 currentBubblePos를 사용하면 됨
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
                blur: 18, // 25 -> 18 (15~20 사이 최적값)
                alignment: Alignment.center,
                border: 0.5, // 1.2 -> 0.5 (날카로운 단면 질감)
                linearGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.06)],
                ),
                borderGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.5), // 상단 밝게
                    Colors.black.withOpacity(0.2), // 하단 어둡게 (단면 질감)
                  ],
                ),
                child: Material(
                  color: Colors.transparent, // 텍스트의 노란 밑줄(No Material) 이슈 해결
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(), // 오버플로우 발생 시 스크롤 가능하도록 변경
                    child: Opacity(
                      opacity: ((curve.value - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: Container(
                        height: dialogHeight,
                        padding: const EdgeInsets.all(20.0),
                        child: _buildDialogContent(context, bubble),
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
      // 애니메이션이 완전히 끝날 때까지 약간의 여유(520ms)를 두고 비눗방울 표시
      Future.delayed(const Duration(milliseconds: 520), () {
        if (mounted) {
          setState(() => _morphingBubbleId = null);
        }
      });
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
            _bubblesCache.remove(dateStr);
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
                  child: AnimatedBuilder(
                    animation: _bgAnim,
                    builder: (context, child) {
                      return Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color.lerp(const Color(0xFF0F172A), const Color(0xFF1E1B4B), _bgAnim.value)!,
                                  Color.lerp(const Color(0xFF1E1B4B), const Color(0xFF0B1120), _bgAnim.value)!,
                                ],
                              ),
                            ),
                          ),
                          // Animated glowing orbs
                          Positioned(
                            top: 100 + 50 * sin(_bgAnim.value * pi),
                            left: -100,
                            child: _buildGlowOrb(const Color(0xFF4488FF), 400, 0.6),
                          ),
                          Positioned(
                            bottom: -150,
                            right: -100 + 50 * cos(_bgAnim.value * pi),
                            child: _buildGlowOrb(const Color(0xFF88CCFF), 500, 0.4),
                          ),
                          Positioned(
                            top: MediaQuery.of(context).size.height * 0.4,
                            right: -50,
                            child: _buildGlowOrb(const Color(0xFF6366F1), 300, 0.5),
                          ),
                        ],
                      );
                    },
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
                physics: const BouncingScrollPhysics(),
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
                                  return Positioned(
                                    left: bubble.position.dx - bubble.radius,
                                    top: bubble.position.dy - bubble.radius,
                                    child: BubbleWidget(
                                      key: ValueKey(bubble.id),
                                      bubble: bubble,
                                      shimmerController: _shimmerController,
                                      onPop: () => _popBubble(bubble),
                                      onLongPress: bubble.isRepeating ? (pos) => _toggleRepeat(bubble, pos) : null,
                                      isReadOnly: false, // 이제 과거 날짜도 터뜨릴 수 있음
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
                          child: _GlassCalendar(
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
                bottom: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: _buildGlassChip('과거 기록도 터뜨릴 수 있어요! ✨', width: 220),
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
      _selectedDate = date;
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
        _loadBubbles();
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

    return InteractiveGlassWidget(
      onTap: onTap,
      onLongPress: onLongPress,
      child: button,
    );
  }

  Widget _buildGlassDateChip(String label, VoidCallback onTap) {
    return InteractiveGlassWidget(
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
    return InteractiveGlassWidget(
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
    return InteractiveGlassWidget(
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
    
    return InteractiveGlassWidget(
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

class _GlassCalendar extends StatefulWidget {
  final DateTime initialDate;
  final DateTime today;
  final Function(DateTime) onDateSelected;

  final double width;
  final double height;
  final double borderRadius;
  final double animationValue;

  const _GlassCalendar({
    required this.initialDate,
    required this.today,
    required this.onDateSelected,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.animationValue,
  });

  @override
  State<_GlassCalendar> createState() => _GlassCalendarState();
}

class _GlassCalendarState extends State<_GlassCalendar> {
  late DateTime _viewMonth;
  late PageController _monthPageController;
  final int _initialMonthPage = 1200;

  @override
  void initState() {
    super.initState();
    _viewMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
    _monthPageController = PageController(initialPage: _initialMonthPage);
  }

  @override
  void dispose() {
    _monthPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! > 200) {
          // 오른쪽 스와이프 -> 이전 달
          setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1));
          HapticFeedback.lightImpact();
        } else if (details.primaryVelocity! < -200) {
          // 왼쪽 스와이프 -> 다음 달
          setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1));
          HapticFeedback.lightImpact();
        }
      },
      child: GlassmorphicContainer(
        width: widget.width,
        height: widget.height,
        borderRadius: widget.borderRadius,
        blur: 20 * widget.animationValue.clamp(0.0, 1.0),
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.04)],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.1)],
        ),
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              height: 380, 
              width: widget.width,
              child: OverflowBox(
                minWidth: 350, 
                maxWidth: 350,
                minHeight: 380,
                maxHeight: 380,
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: ((widget.animationValue * 380 - 100) / 280).clamp(0.0, 1.0),
                  child: Column(
                    children: [
                      _buildHeader(_viewMonth), // 상단 헤더는 고정
                      _buildWeekdays(),         // 요일 표시도 고정
                      Expanded(
                        child: PageView.builder(
                          controller: _monthPageController,
                          onPageChanged: (index) {
                            final diff = index - _initialMonthPage;
                            setState(() {
                              _viewMonth = DateTime(widget.initialDate.year, widget.initialDate.month + diff);
                            });
                            HapticFeedback.selectionClick();
                          },
                          itemBuilder: (context, index) {
                            final diff = index - _initialMonthPage;
                            final month = DateTime(widget.initialDate.year, widget.initialDate.month + diff);
                            return _buildDaysGrid(month);
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(DateTime month) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildNavBtn(Icons.chevron_left_rounded, () {
            _monthPageController.previousPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }),
          Text(
            '${month.year}년 ${month.month}월',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          _buildNavBtn(Icons.chevron_right_rounded, () {
            _monthPageController.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNavBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildWeekdays() {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: days.map((d) => SizedBox(
          width: 30,
          child: Center(
            child: Text(d, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildDaysGrid(DateTime month) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstDay = DateTime(month.year, month.month, 1).weekday - 1;
    final totalCells = firstDay + daysInMonth;
    
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        if (index < firstDay) return const SizedBox.shrink();
        
        final day = index - firstDay + 1;
        final date = DateTime(month.year, month.month, day);
        final isToday = date.year == widget.today.year && date.month == widget.today.month && date.day == widget.today.day;
        final isSelected = date.year == widget.initialDate.year && date.month == widget.initialDate.month && date.day == widget.initialDate.day;

        return InkWell(
          onTap: () => widget.onDateSelected(date),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withOpacity(0.2) : (isToday ? Colors.blueAccent.withOpacity(0.2) : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              border: isSelected ? Border.all(color: Colors.white.withOpacity(0.5)) : (isToday ? Border.all(color: Colors.blueAccent.withOpacity(0.5)) : null),
            ),
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  color: isSelected ? Colors.white : (isToday ? Colors.blueAccent : Colors.white.withOpacity(0.8)),
                  fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class InteractiveGlassWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const InteractiveGlassWidget({
    super.key, 
    required this.child, 
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<InteractiveGlassWidget> createState() => _InteractiveGlassWidgetState();
}

class _InteractiveGlassWidgetState extends State<InteractiveGlassWidget>
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
