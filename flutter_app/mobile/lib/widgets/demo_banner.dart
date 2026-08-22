import 'package:flutter/material.dart';

class DemoBanner extends StatelessWidget {
  final Widget child;

  const DemoBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: IgnorePointer(
              child: Container(
                color: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Text(
                  'Demo — local data, sync off',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
