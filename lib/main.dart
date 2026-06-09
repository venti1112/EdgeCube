import 'package:flutter/material.dart';

import 'home_shell.dart';

void main() {
  runApp(const EdgeCubeApp());
}

class EdgeCubeApp extends StatelessWidget {
  const EdgeCubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EdgeCube',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const HomeShell(),
    );
  }
}
