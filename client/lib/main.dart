import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'pages/canvas_page.dart';
import 'pages/home_page.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: '/room/:code',
      builder: (_, state) {
        final code = state.pathParameters['code']!.toUpperCase();
        return CanvasPage(roomCode: code);
      },
    ),
  ],
);

void main() {
  usePathUrlStrategy();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'paintcoop',
      theme: ThemeData.dark(),
      routerConfig: _router,
    );
  }
}
