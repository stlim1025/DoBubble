import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../models/todo_bubble.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Map<String, List<TodoBubble>> _historyData = {};
  bool _isLoading = false; // 즉각적인 표시를 위해 초기값을 false로 설정
  final GlobalKey _todayKey = GlobalKey();
  String? _todayKeyStr; // 오늘 날짜 문자열 저장용

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 오늘 날짜 키 확인
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _todayKeyStr = todayKey;
    
    // 키 목록 가져오기
    final keys = prefs.getKeys().where((k) => k.startsWith('bubbles_')).map((k) => k.replaceFirst('bubbles_', '')).toList();
    if (!keys.contains(todayKey)) {
      keys.add(todayKey);
    }
    
    // 전체 날짜 최신순 정렬 (미래 날짜가 위로 감)
    keys.sort((a, b) => b.compareTo(a));

    for (var date in keys) {
      final jsonStr = prefs.getString('bubbles_$date');
      List<TodoBubble> bubbles = [];
      
      if (jsonStr != null) {
        try {
          final List<dynamic> decoded = jsonDecode(jsonStr);
          bubbles = decoded.map((item) => TodoBubble.fromJson(item)).toList();
          
          // 내부 정렬: 완료된 것(popped) 먼저, 미완료는 아래로
          bubbles.sort((a, b) {
            final aPopped = a.state == BubbleState.popped ? 0 : 1;
            final bPopped = b.state == BubbleState.popped ? 0 : 1;
            return aPopped.compareTo(bPopped);
          });
        } catch (e) {
          debugPrint('Error loading history for $date: $e');
        }
      }

      // 필터링 로직: 
      // 1. 오늘 날짜는 무조건 표시
      // 2. 오늘 이전 날짜는 데이터가 없어도 표시 (기록 보존)
      // 3. 오늘 이후(미래) 날짜는 비눗방울이 하나라도 있을 때만 표시
      if (date.compareTo(todayKey) > 0 && bubbles.isEmpty) {
        continue;
      }
      
      _historyData[date] = bubbles;
    }

    if (mounted) {
      setState(() {}); // 데이터 로드 후 화면 갱신

      // 오늘 날짜 위치로 스크롤
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_todayKey.currentContext != null) {
          Scrollable.ensureVisible(
            _todayKey.currentContext!,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'history_icon',
      child: Scaffold(
        body: Stack(
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
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(), // 애니메이션 중 스크롤 방지, 오버플로우만 허용
                child: SizedBox(
                  height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context),
                      Expanded(
                        child: _historyData.isEmpty 
                          ? _buildEmptyState()
                          : _buildHistoryList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
              ),
              const SizedBox(width: 8),
              const Text(
                '비눗방울 기록',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '톡! $poppedCount / $totalCount',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color(0xFF4488FF).withOpacity(0.6),
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 12),
          ...bubbles.map((b) => _buildBubbleItem(b)).toList(),
        ],
      ),
    );
  }

  Widget _buildBubbleItem(TodoBubble bubble) {
    final isPopped = bubble.state == BubbleState.popped;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: 54,
        borderRadius: 16,
        blur: 10,
        alignment: Alignment.centerLeft,
        border: 0.5,
        linearGradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(isPopped ? 0.12 : 0.05),
            Colors.white.withOpacity(isPopped ? 0.05 : 0.02),
          ],
        ),
        borderGradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(isPopped ? 0.3 : 0.1),
            Colors.white.withOpacity(0.05),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                isPopped ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: isPopped ? const Color(0xFF4488FF).withOpacity(0.8) : Colors.white24,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  bubble.task,
                  style: TextStyle(
                    color: isPopped ? Colors.white70 : Colors.white,
                    fontSize: 15,
                    decoration: isPopped ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white24,
                  ),
                ),
              ),
              if (bubble.isRepeating)
                Icon(Icons.sync_rounded, size: 14, color: Colors.white.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    return '${parts[1]}월 ${parts[2]}일';
  }
}
