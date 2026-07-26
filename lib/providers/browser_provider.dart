import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/instrument.dart';
import '../services/file_service.dart';
import '../core/utils/logger.dart';

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

final browserBookmarksProvider = StateProvider<List<_BrowserBookmark>>((ref) {
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
Future<void> persistBrowserBookmarks(List<_BrowserBookmark> bookmarks) async {
  if (kIsWeb) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = bookmarks.map((b) => jsonEncode(b.toJson())).toList();
    prefs.setStringList('browser_bookmarked_dirs', jsonList);
  } catch (_) {}
}

final _browserPrefsProvider = FutureProvider<_BrowserPrefs>((ref) async {
  if (kIsWeb) return _BrowserPrefs.empty();
  try {
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString('browser_selected_samples_dir');
    final raw = prefs.getStringList('browser_bookmarked_dirs') ?? <String>[];
    final bookmarks = <_BrowserBookmark>[];
    for (final item in raw) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        bookmarks.add(_BrowserBookmark.fromJson(map));
      } catch (_) {
        // Backward compat: treat as plain path
        if (item.isNotEmpty) {
          bookmarks.add(_BrowserBookmark(path: item, addedAt: DateTime.now().toIso8601String(), label: ''));
        }
      }
    }
    return _BrowserPrefs(selectedSamplesDir: selected, bookmarkedDirs: bookmarks);
  } catch (_) {
    return _BrowserPrefs.empty();
  }
});

class _BrowserPrefs {
  final String? selectedSamplesDir;
  final List<_BrowserBookmark> bookmarkedDirs;
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
    final jsonList = bookmarkedDirs.map((b) => jsonEncode(b.toJson())).toList();
    prefs.setStringList('browser_bookmarked_dirs', jsonList);
  }
}

class _BrowserBookmark {
  final String path;
  final String addedAt;
  final String label;
  const _BrowserBookmark({
    required this.path,
    required this.addedAt,
    this.label = '',
  });

  factory _BrowserBookmark.fromJson(Map<String, dynamic> json) {
    return _BrowserBookmark(
      path: json['path'] as String? ?? '',
      addedAt: json['addedAt'] as String? ?? DateTime.now().toIso8601String(),
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'addedAt': addedAt,
    'label': label,
  };

  _BrowserBookmark copyWith({String? path, String? addedAt, String? label}) {
    return _BrowserBookmark(
      path: path ?? this.path,
      addedAt: addedAt ?? this.addedAt,
      label: label ?? this.label,
    );
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

/// Export bookmarked directories to a JSON file.
/// Returns the exported file path, or null on failure / web.
Future<String?> exportBrowserBookmarks() async {
  if (kIsWeb) return null;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('browser_bookmarked_dirs') ?? <String>[];
    final bookmarks = <Map<String, String>>[];
    for (final item in raw) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        bookmarks.add(Map<String, String>.from(map.map((k, v) => MapEntry(k, v.toString()))));
      } catch (_) {
        if (item.isNotEmpty) {
          bookmarks.add({'path': item, 'addedAt': DateTime.now().toIso8601String(), 'label': ''});
        }
      }
    }
    final exportData = {
      'bookmarks': bookmarks,
      'exportedAt': DateTime.now().toIso8601String(),
      'version': 1,
    };
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/ZenithAudio/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${exportDir.path}/bookmarks_$timestamp.json';
    await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(exportData));
    return path;
  } catch (e) {
    AppLogger.e('Failed to export bookmarks', e);
    return null;
  }
}

/// Import bookmarks from a JSON file picked by the user.
/// Merges with existing bookmarks, deduplicates by path.
Future<void> importBrowserBookmarks(BuildContext context, WidgetRef ref) async {
  if (kIsWeb) return;
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Select bookmarks JSON',
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    if (file.path == null) return;

    final content = await File(file.path!).readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    final List<dynamic> incoming = data['bookmarks'] ?? [];

    final prefs = await SharedPreferences.getInstance();
    final existingRaw = prefs.getStringList('browser_bookmarked_dirs') ?? <String>[];
    final existingPaths = <String>{};
    final merged = <String>[];

    for (final item in existingRaw) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        final path = map['path'] as String? ?? item;
        if (path.isNotEmpty && !existingPaths.contains(path)) {
          existingPaths.add(path);
          merged.add(item);
        }
      } catch (_) {
        if (item.isNotEmpty && !existingPaths.contains(item)) {
          existingPaths.add(item);
          merged.add(item);
        }
      }
    }

    int added = 0;
    for (final item in incoming) {
      final path = (item['path'] as String?)?.trim() ?? '';
      if (path.isEmpty || existingPaths.contains(path)) continue;
      final label = (item['label'] as String?)?.trim() ?? '';
      final addedAt = (item['addedAt'] as String?)?.trim() ?? DateTime.now().toIso8601String();
      merged.add(jsonEncode({'path': path, 'addedAt': addedAt, 'label': label}));
      existingPaths.add(path);
      added++;
    }

    await prefs.setStringList('browser_bookmarked_dirs', merged);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $added bookmark(s)'), duration: const Duration(seconds: 2)),
      );
    }
    ref.invalidate(_browserPrefsProvider);
    ref.invalidate(browserBookmarksProvider);
  } catch (e) {
    AppLogger.e('Failed to import bookmarks', e);
  }
}
