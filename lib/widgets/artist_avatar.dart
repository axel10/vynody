import 'package:flutter/material.dart';

class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({super.key, required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CircleAvatar(
        radius: diameter / 2,
        backgroundColor: theme.colorScheme.tertiaryContainer.withValues(
          alpha: 0.8,
        ),
        child: Icon(
          Icons.person_rounded,
          size: diameter * 0.52,
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }
}
