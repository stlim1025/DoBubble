import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const DoBubbleApp());
}

class DoBubbleApp extends StatelessWidget {
  const DoBubbleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DoBubble',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.blueAccent,
        ),
        fontFamily: 'AppleSDGothicNeo', // iOS 스타일 폰트 (기본 폰트 사용)
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
