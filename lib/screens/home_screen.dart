import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo_bubble.dart';
import '../widgets/bubble_widget.dart';
import 'package:audioplayers/audioplayers.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<TodoBubble> _bubbles = [];
  final TextEditingController _taskController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final AudioPlayer _audioPlayer = AudioPlayer();

  late AnimationController _gameLoopController;
  late AnimationController _bgAnimController;
  late Animation<double> _bgAnim;
  late AnimationController _shimmerController; // 공유 shimmer 컨트롤러
  Size _screenSize = Size.zero; // 화면 크기 캐싱
  int _selectedPriority = 1; // 기본 중요도 (1~4)
  bool _isRepeating = false; // 반복 여부
  final List<TodoBubble> _repeatingTemplates = []; // 반복 할일 템플릿

  bool _isInputFocused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBubbles();

    // 게임 루프 (물리 업데이트)
    _gameLoopController = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )..addListener(_updatePhysics);
    _gameLoopController.forward();

    // 배경 그라데이션 애니메이션
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgAnimController, curve: Curves.easeInOut);

    // 공유 shimmer 루프 (모든 버블이 이 컨트롤러를 공유)
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _focusNode.addListener(() {
      setState(() {
        _isInputFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveBubbles();
    _gameLoopController.dispose();
    _bgAnimController.dispose();
    _shimmerController.dispose();
    _taskController.dispose();
    _focusNode.dispose();
    _audioPlayer.dispose();
    super.dispose();
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
    final prefs = await SharedPreferences.getInstance();
    final String? bubblesJson = prefs.getString('saved_bubbles');
    final String? repeatingJson = prefs.getString('repeating_templates');
    final String? lastDateStr = prefs.getString('last_open_date');
    
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    
    List<TodoBubble> loadedBubbles = [];
    List<TodoBubble> repeatingTemplates = [];

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
        debugPrint('Error loading bubbles: $e');
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

    // 날짜가 바뀌었는지 확인
    bool isNewDay = false;
    if (lastDateStr != null) {
      final lastDate = DateTime.parse(lastDateStr);
      if (lastDate.isBefore(todayMidnight)) {
        isNewDay = true;
      }
    } else {
      isNewDay = true;
    }

    if (isNewDay) {
      // 1. 반복 안 하는 옛날 버블 삭제
      loadedBubbles.removeWhere((b) => !b.isRepeating && b.createdAt.isBefore(todayMidnight));
      
      // 2. 반복 하는 버블들 보충 (이미 있으면 중복 생성 안 함)
      for (var template in _repeatingTemplates) {
        bool exists = loadedBubbles.any((b) => b.task == template.task && b.isRepeating);
        if (!exists) {
          // 새로운 위치와 속도로 재생성
          final random = Random();
          final startX = _screenSize.width / 2 + (random.nextDouble() - 0.5) * 40;
          final startY = _screenSize.height / 2; // 중앙 부근에서 생성
          
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
      
      // 날짜 업데이트 저장
      await prefs.setString('last_open_date', now.toIso8601String());
    }

    setState(() {
      _bubbles.clear();
      _bubbles.addAll(loadedBubbles);
    });
  }

  Future<void> _saveBubbles() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 현재 활성 버블 저장
    final String bubblesJson = jsonEncode(_bubbles.where((b) => b.state != BubbleState.popping).map((b) => b.toJson()).toList());
    await prefs.setString('saved_bubbles', bubblesJson);
    
    // 반복 할일 템플릿 저장
    final String repeatingJson = jsonEncode(_repeatingTemplates.map((b) => b.toJson()).toList());
    await prefs.setString('repeating_templates', repeatingJson);
  }

  void _updatePhysics() {
    if (!mounted) return;
    for (var bubble in _bubbles) {
      if (bubble.state != BubbleState.popping) { // 불기 중에도 이동
        bubble.update(_screenSize);
      }
    }

    // 버블 간 충돌 감지 (탄성 충돌)
    for (int i = 0; i < _bubbles.length; i++) {
      for (int j = i + 1; j < _bubbles.length; j++) {
        final a = _bubbles[i];
        final b = _bubbles[j];
        if (a.state == BubbleState.popping || b.state == BubbleState.popping) continue;

        final dx = b.position.dx - a.position.dx;
        final dy = b.position.dy - a.position.dy;
        final distSq = dx * dx + dy * dy;
        final minDist = a.radius + b.radius;

        if (distSq < minDist * minDist && distSq > 0) {
          final dist = sqrt(distSq);
          final nx = dx / dist; // 충돌 법선 벡터
          final ny = dy / dist;

          // 겹침 보정 (두 버블을 서로 밀어냄)
          final overlap = (minDist - dist) / 2.0;
          a.position = Offset(a.position.dx - nx * overlap, a.position.dy - ny * overlap);
          b.position = Offset(b.position.dx + nx * overlap, b.position.dy + ny * overlap);

          // 충돌 방향의 상대 속도 계산
          final dvx = a.velocity.dx - b.velocity.dx;
          final dvy = a.velocity.dy - b.velocity.dy;
          final dot = dvx * nx + dvy * ny;

          // 서로 가까워지는 경우만 처리 (이미 멀어지는 경우 무시)
          if (dot > 0) {
            const restitution = 0.75; // 반발 계수 (0=완전비탄성, 1=완전탄성)
            final impulse = dot * restitution;
            a.velocity = Offset(a.velocity.dx - impulse * nx, a.velocity.dy - impulse * ny);
            b.velocity = Offset(b.velocity.dx + impulse * nx, b.velocity.dy + impulse * ny);

            // 충돌 후 속도 상한 재적용
            for (final bubble in [a, b]) {
              final spd = bubble.velocity.distance;
              if (spd > 1.5) {
                bubble.velocity = bubble.velocity / spd * 1.5;
              }
            }
          }
        }
      }
    }

    // setState() 호출 제거 -> AnimatedBuilder가 처리하도록 변경
  }

  void _addTodo(String task) {
    if (task.trim().isEmpty) return;

    HapticFeedback.lightImpact();

    final random = Random();
    final startX = _screenSize.width / 2 + (random.nextDouble() - 0.5) * 40;
    final startY = _screenSize.height - MediaQuery.of(context).viewInsets.bottom - 120;

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
    HapticFeedback.heavyImpact();

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
          _bubbles.removeWhere((b) => b.id == bubble.id);
        });
        _saveBubbles();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── 배경 및 빈 공간 터치 처리 ──
          Positioned.fill(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
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
                      // Animated glowing orbs for the glass effect
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

          // ── 비눗방울들 ──
          AnimatedBuilder(
            animation: _gameLoopController,
            builder: (context, _) {
              return Stack(
                children: _bubbles.map((bubble) {
                  return Positioned(
                    left: bubble.position.dx - bubble.radius,
                    top: bubble.position.dy - bubble.radius,
                    child: BubbleWidget(
                      key: ValueKey(bubble.id),
                      bubble: bubble,
                      shimmerController: _shimmerController,
                      onPop: () => _popBubble(bubble),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          // ── 우측 상단 카운트 칩 ──
          if (_bubbles.isNotEmpty)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16, right: 20),
                  child: _buildGlassChip('🫧 ${_bubbles.length}'),
                ),
              ),
            ),

          // ── 하단 입력창 ──
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset > 0 ? bottomInset + 16 : 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildBottomInputBar(),
            ),
          ),
        ],
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

  Widget _buildGlassChip(String label) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.20),
                Colors.white.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomInputBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(_isInputFocused ? 0.25 : 0.15),
                Colors.white.withOpacity(_isInputFocused ? 0.10 : 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(_isInputFocused ? 0.35 : 0.20),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 중요도 선택 버튼들
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ...[1, 2, 3, 4].map((p) => _buildPriorityButton(p)).toList(),
                    const SizedBox(width: 12),
                    _buildRepeatToggle(),
                  ],
                ),
              ),
              Row(
                children: [
                  // 텍스트 입력 필드
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
                ],
              ),
            ],
          ),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isInputFocused
                    ? [
                        const Color(0xFF4488FF).withOpacity(0.4),
                        const Color(0xFF2255CC).withOpacity(0.2),
                      ]
                    : [
                        Colors.white.withOpacity(0.1),
                        Colors.transparent,
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _isInputFocused
                    ? const Color(0xFF88BBFF).withOpacity(0.3)
                    : Colors.white.withOpacity(0.1),
                width: 1,
              ),
              boxShadow: _isInputFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4488FF).withOpacity(0.2),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: Icon(
              Icons.bubble_chart_rounded,
              color: _isInputFocused
                  ? Colors.white
                  : Colors.white.withOpacity(0.5),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRepeatToggle() {
    return InteractiveGlassWidget(
      onTap: () {
        setState(() => _isRepeating = !_isRepeating);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(_isRepeating ? 0.15 : 0.03),
              border: Border.all(
                color: Colors.white.withOpacity(_isRepeating ? 0.4 : 0.1),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
        ),
      ),
    );
  }

  Widget _buildPriorityButton(int priority) {
    final isSelected = _selectedPriority == priority;
    // 비눗방울 크기 시각화 (버튼 크기를 살짝 다르게)
    final size = 24.0 + (4 - priority) * 4.0;
    
    return InteractiveGlassWidget(
      onTap: () {
        setState(() => _selectedPriority = priority);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(isSelected ? 0.15 : 0.03),
                border: Border.all(
                  color: Colors.white.withOpacity(isSelected ? 0.4 : 0.1),
                  width: isSelected ? 1.5 : 1,
                ),
                boxShadow: isSelected ? [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.1),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ] : [],
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: size * 0.7,
                  height: size * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withOpacity(isSelected ? 0.8 : 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$priority',
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InteractiveGlassWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const InteractiveGlassWidget({super.key, required this.child, required this.onTap});

  @override
  State<InteractiveGlassWidget> createState() => _InteractiveGlassWidgetState();
}

class _InteractiveGlassWidgetState extends State<InteractiveGlassWidget> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
