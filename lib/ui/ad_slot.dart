import 'package:flutter/material.dart';

/// Placeholder for the ad shown between levels (300×250 medium rectangle,
/// the standard size for AdMob and web portals). Swap the child for the real
/// ad widget once an ad network is wired in.
class AdSlot extends StatelessWidget {
  const AdSlot({super.key});

  static const size = Size(300, 250);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ADVERTISEMENT', style: TextStyle(fontSize: 9, letterSpacing: 2, color: Colors.white.withValues(alpha: 0.35))),
        const SizedBox(height: 4),
        FittedBox(
          child: Container(
            key: const Key('ad-slot'),
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text('Ad space', style: TextStyle(color: Colors.white.withValues(alpha: 0.2))),
          ),
        ),
      ],
    );
  }
}
