import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
