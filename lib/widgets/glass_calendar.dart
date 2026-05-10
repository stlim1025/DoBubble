import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:glassmorphism/glassmorphism.dart';

class GlassCalendar extends StatefulWidget {
  final DateTime initialDate;
  final DateTime today;
  final Function(DateTime) onDateSelected;

  final double width;
  final double height;
  final double borderRadius;
  final double animationValue;
  final bool Function(DateTime)? isDateEnabled;

  const GlassCalendar({
    super.key,
    required this.initialDate,
    required this.today,
    required this.onDateSelected,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.animationValue,
    this.isDateEnabled,
  });

  @override
  State<GlassCalendar> createState() => _GlassCalendarState();
}

class _GlassCalendarState extends State<GlassCalendar> {
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
          _monthPageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          HapticFeedback.lightImpact();
        } else if (details.primaryVelocity! < -200) {
          // 왼쪽 스와이프 -> 다음 달
          setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1));
          _monthPageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
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
        final isEnabled = widget.isDateEnabled?.call(date) ?? true;

        return InkWell(
          onTap: isEnabled ? () => widget.onDateSelected(date) : null,
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
                  color: !isEnabled 
                      ? Colors.white.withOpacity(0.15) 
                      : (isSelected ? Colors.white : (isToday ? Colors.blueAccent : Colors.white.withOpacity(0.8))),
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
