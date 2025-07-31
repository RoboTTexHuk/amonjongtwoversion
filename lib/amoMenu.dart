import 'package:flutter/material.dart';

import 'amoGame.dart' show ExampleWebWidget;



class GameSelectionScreen extends StatelessWidget {
  const GameSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset('assets/bg.png', fit: BoxFit.cover),
          ),
          // Main content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top icon
                InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExampleWebWidget(
                        "https://play.famobi.com/stones-of-pharaoh",
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: Image.asset(
                      'assets/icon1.png', // замените на свой путь
                      width: 260,
                      height: 260,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                // Bottom icon
                InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExampleWebWidget(
                        "https://play.famobi.com/mahjong-master-2",
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: Image.asset(
                      'assets/icon2.png', // замените на свой путь
                      width: 260,
                      height: 260,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
