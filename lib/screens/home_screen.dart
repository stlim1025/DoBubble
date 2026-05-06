import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui';
import '../models/todo_bubble.dart';
import '../widgets/bubble_widget.dart';
import 'package:audioplayers/audioplayers.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final List<TodoBubble> _bubbles = [];
  final TextEditingController _taskController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  late AnimationController _gameLoopController;

  @override
  void initState() {
    super.initState();
    _gameLoopController = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )..addListener(_updatePhysics);
    _gameLoopController.forward();
  }

  @override
  void dispose() {
    _gameLoopController.dispose();
    _taskController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _updatePhysics() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    bool needsUpdate = false;

    for (var bubble in _bubbles) {
      if (bubble.state == BubbleState.floating) {
        bubble.update(size);
        needsUpdate = true;
      }
    }

    if (needsUpdate) {
      setState(() {});
    }
  }

  void _addTodo(String task) {
    if (task.trim().isEmpty) return;

    final size = MediaQuery.of(context).size;
    final random = Random();
    
    // 비눗방울 초기 속도 (천천히 움직임)
    final velocityX = (random.nextDouble() - 0.5) * 2;
    final velocityY = -random.nextDouble() * 2 - 1;

    final newBubble = TodoBubble(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      task: task.trim(),
      position: Offset(size.width / 2, size.height - 100), // 하단에서 시작
      velocity: Offset(velocityX, velocityY),
      radius: 60.0,
      state: BubbleState.blowing,
    );

    setState(() {
      _bubbles.add(newBubble);
    });

    _taskController.clear();
  }

  void _popBubble(TodoBubble bubble) async {
    setState(() {
      bubble.state = BubbleState.popping;
    });

    // 뾱 사운드 재생 (로컬 에셋 또는 임시 소리)
    // 실제로는 assets/sounds/pop.mp3 등을 사용
    // 지금은 오류 방지를 위해 play 호출은 주석 처리 또는 try-catch로 감쌉니다
    try {
      // await _audioPlayer.play(AssetSource('sounds/pop.mp3'));
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }

    // 터지는 애니메이션을 위해 잠시 대기
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() {
        _bubbles.removeWhere((b) => b.id == bubble.id);
      });
    });
  }

  void _showAddTodoDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white.withOpacity(0.1),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '새로운 할 일',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _taskController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '할 일을 입력하세요',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onSubmitted: (value) {
                        Navigator.pop(context);
                        _addTodo(value);
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _addTodo(_taskController.text);
                      },
                      child: const Text('비눗방울 불기'),
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 배경 그라데이션
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          
          // 비눗방울들
          ..._bubbles.map((bubble) {
            return Positioned(
              left: bubble.position.dx - bubble.radius,
              top: bubble.position.dy - bubble.radius,
              child: BubbleWidget(
                bubble: bubble,
                onPop: () => _popBubble(bubble),
              ),
            );
          }).toList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTodoDialog,
        backgroundColor: Colors.white.withOpacity(0.2),
        elevation: 0,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
