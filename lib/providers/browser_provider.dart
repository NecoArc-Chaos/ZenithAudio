import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

final selectedSamplesDirProvider = StateProvider<String?>((ref) {
  final prefs = ref.watch(_browserPrefsProvider.future);
  return prefs.then((p) => p.selectedSamplesDir);
});

final browserBookmarksProvider = StateProvider<List<String>>((ref) {
  final prefs = ref.watch(_browserPrefsProvider.future);
  return prefs.then((p) => List.from(p.bookmarkedDirs));
});

/// Persist the currently selected samples directory.
Future<void> persistSelectedSamplesDir(String? dir) async {
  if (kIsWeb) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (dir != null) {
      prefs.setString('browser_selected_samples_dir', dir);
    } else {
      prefs.remove('browser_selected_samples_dir');
    }
  } catch (_) {}
}

/// Persist the bookmarked directories list.
Future<void> persistBrowserBookmarks(List<String> bookmarks) async {
  if (kIsWeb) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('browser_bookmarked_dirs', bookmarks);
  } catch (_) {}
}

final _browserPrefsProvider = FutureProvider<_BrowserPrefs>((ref) async {
  if (kIsWeb) return _BrowserPrefs.empty();
  try {
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString('browser_selected_samples_dir');
    final bookmarks = prefs.getStringList('browser_bookmarked_dirs') ?? <String>[];
    return _BrowserPrefs(selectedSamplesDir: selected, bookmarkedDirs: bookmarks);
  } catch (_) {
    return _BrowserPrefs.empty();
  }
});

class _BrowserPrefs {
  final String? selectedSamplesDir;
  final List<String> bookmarkedDirs;
  const _BrowserPrefs({this.selectedSamplesDir, this.bookmarkedDirs = const []});

  const _BrowserPrefs.empty()
      : selectedSamplesDir = null,
        bookmarkedDirs = const [];

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (selectedSamplesDir != null) {
      prefs.setString('browser_selected_samples_dir', selectedSamplesDir!);
    } else {
      prefs.remove('browser_selected_samples_dir');
    }
    prefs.setStringList('browser_bookmarked_dirs', bookmarkedDirs);
  }
}

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
