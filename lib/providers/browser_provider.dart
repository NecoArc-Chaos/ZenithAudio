import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final browserVisibilityProvider = StateProvider<bool>((ref) => false);

enum BrowserTab { samples, presets, projects }

final browserTabProvider = StateProvider<BrowserTab>((ref) => BrowserTab.samples);

final recentProjectsProvider = FutureProvider<List<String>>((ref) async {
  if (kIsWeb) return [];
  try {
    final dir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${dir.path}/.projects');
    if (!await projectDir.exists()) return [];
    return projectDir
        .listSync()
        .where((e) => e is File && e.path.endsWith('.zap'))
        .map((e) => File(e.path).name)
        .toList();
  } catch (_) {
    return [];
  }
});
