import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/instrument.dart';
import '../services/file_service.dart';

final browserVisibilityProvider = StateProvider<bool>((ref) => false);

enum BrowserTab { samples, presets, projects }

final browserTabProvider = StateProvider<BrowserTab>((ref) => BrowserTab.samples);

final recentProjectsProvider = FutureProvider<List<File>>((ref) async {
  if (kIsWeb) return [];
  try {
    final dir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${dir.path}/.projects');
    if (!await projectDir.exists()) return [];
    return projectDir
        .listSync()
        .where((e) => e is File && e.path.endsWith('.zap'))
        .map((e) => File(e.path))
        .toList();
  } catch (_) {
    return [];
  }
});

final browserPresetsProvider = Provider<List<(String, IconData)>>((ref) {
  return InstrumentPreset.allPresets
      .map((p) => (p.name, p.icon))
      .toList();
});

final selectedSamplesDirProvider = StateProvider<String?>((ref) => null);

Future<List<File>> _listAudioFiles(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) return [];
  final allowed = <String>{'.wav', '.mp3', '.flac', '.aac', '.ogg', '.m4a'};
  return dir
      .listSync()
      .where((e) => e is File && allowed.contains(e.path.toLowerCase()))
      .map((e) => File(e.path))
      .toList();
}

final browserSamplesProvider = FutureProvider<List<File>>((ref) async {
  if (kIsWeb) return [];
  final selected = ref.read(selectedSamplesDirProvider);
  if (selected != null) {
    return _listAudioFiles(selected);
  }
  try {
    final dir = await getApplicationDocumentsDirectory();
    final samplesDir = Directory('${dir.path}/ZenithAudio/samples');
    if (!await samplesDir.exists()) return [];
    return _listAudioFiles(samplesDir.path);
  } catch (_) {
    return [];
  }
});
