import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';

import 'package:home_widget/home_widget.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/todo_bubble.dart';
import 'services/widget_service.dart';

@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  print('Widget Interaction URI: $uri');
  final uriString = uri?.toString().toLowerCase() ?? '';
  if (uriString.contains('popbubble') || uriString.startsWith('dopop://')) {
    final id = uri?.queryParameters['id'];
    print('Popping Bubble ID from Widget: $id');
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      
      // 1. HomeWidget 저장소를 통한 신호 전달 (가장 확실한 방법)
      final String? pendingJson = await HomeWidget.getWidgetData<String>('pending_popped_ids');
      List<String> pendingIds = [];
      if (pendingJson != null && pendingJson.isNotEmpty) {
        pendingIds = List<String>.from(jsonDecode(pendingJson));
      }
      if (!pendingIds.contains(id)) {
        pendingIds.add(id);
        await HomeWidget.saveWidgetData('pending_popped_ids', jsonEncode(pendingIds));
      }

      // 2. 즉시 SharedPreferences 업데이트 시도
      final keys = prefs.getKeys().where((k) => k.startsWith('bubbles_')).toList();
      for (final storageKey in keys) {
        final bubbleData = prefs.getString(storageKey) ?? '[]';
        List<dynamic> list = jsonDecode(bubbleData);
        bool changed = false;
        
        for (var item in list) {
          if (item['id'].toString() == id.toString()) {
            if (item['state'] != 3) {
              item['state'] = 3;
              changed = true;
            }
            break;
          }
        }
        
        if (changed) {
          await prefs.setString(storageKey, jsonEncode(list));
          final now = DateTime.now();
          if (storageKey == 'bubbles_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}') {
            final bubbles = list.map((e) => TodoBubble.fromJson(e)).toList();
            await WidgetService.updateWidgetData(bubbles);
          }
        }
      }
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // App Group ID 설정 (iOS/Android 공유 설정용)
  await HomeWidget.setAppGroupId('group.com.dopop.widget');
  
  // 위젯 백그라운드 콜백 등록
  HomeWidget.registerInteractivityCallback(backgroundCallback);
  
  runApp(const DoPopApp());
}

class DoPopApp extends StatelessWidget {
  const DoPopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DoPop',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4488FF),
          secondary: Color(0xFF88CCFF),
          surface: Color(0xFF0F1826),
        ),
        // 전역 폰트 적용 (NanumSquareRound)
        fontFamily: 'NanumSquareRound',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
