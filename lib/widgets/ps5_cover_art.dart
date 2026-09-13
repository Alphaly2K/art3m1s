import 'dart:io';

import 'package:flutter/material.dart';

import '../adaptive/ps5_chrome.dart';
import '../models/game_entry.dart';

class Ps5CoverArt extends StatelessWidget {
  const Ps5CoverArt({super.key, required this.entry, this.borderRadius = 5});

  final GameEntry entry;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final coverPath = entry.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(
          File(coverPath),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Ps5CoverFallback(title: entry.displayNameOrName),
        ),
      );
    }
    return Ps5CoverFallback(title: entry.displayNameOrName);
  }
}

class Ps5CoverFallback extends StatelessWidget {
  const Ps5CoverFallback({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final initial = title.trim().isEmpty ? 'A' : title.trim()[0].toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF0C1723)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              initial,
              style: TextStyle(
                color: Ps5Colors.accent.withValues(alpha: 0.22),
                fontSize: 70,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Ps5Colors.text.withValues(alpha: 0.78),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
