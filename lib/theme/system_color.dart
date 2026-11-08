import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

Future<Color?> loadSystemSeedColor() async {
  if (!Platform.isAndroid) return null;
  try {
    final palette = await DynamicColorPlugin.getCorePalette();
    if (palette == null) return null;
    return Color(palette.primary.get(50));
  } catch (_) {
    return null;
  }
}
