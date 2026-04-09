import 'package:flutter/material.dart';
import 'pages/canvas_page.dart';
import 'pages/home_page.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if the URL has ?room=CODE — e.g. from a shared invite link
    final roomCode = Uri.base.queryParameters['room']?.toUpperCase();

    return MaterialApp(
      title: 'VectorStream',
      theme: ThemeData.dark(),
      home: roomCode != null && roomCode.length == 6
          ? CanvasPage(roomCode: roomCode)
          : const HomePage(),
    );
  }
}
