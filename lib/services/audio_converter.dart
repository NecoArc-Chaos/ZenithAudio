import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/utils/logger.dart';

const _wavHeaderSize = 12;

bool isWavFile(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return false;
    final header = file.openSync().readSync(_wavHeaderSize);
    if (header.length < 12) return false;
    return header[0] == 0x52 &&  // R
        header[1] == 0x49 &&     // I
        header[2] == 0x46 &&     // F
        header[3] == 0x46 &&     // F
        header[8] == 0x57 &&     // W
        header[9] == 0x41 &&     // A
        header[10] == 0x56 &&    // V
        header[11] == 0x45;      // E
  } catch (_) {
    return false;
  }
}

Future<String?> convertToWav(String sourcePath, [BuildContext? context]) async {
  if (isWavFile(sourcePath)) return sourcePath;

  try {
    final dir = await getApplicationDocumentsDirectory();
    final name = 'import_${const Uuid().v4().substring(0, 8)}.wav';
    final outputPath = '${dir.path}/$name';

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final result = await Process.run('ffmpeg', [
          '-y',
          '-i', sourcePath,
          '-f', 'wav',
          '-acodec', 'pcm_s16le',
          '-ar', '44100',
          '-ac', '1',
          outputPath,
        ]).timeout(const Duration(seconds: 120));

        if (result.exitCode == 0 && await File(outputPath).exists()) {
          return outputPath;
        }

        AppLogger.e('ffmpeg conversion failed (exit ${result.exitCode}): ${result.stderr}');
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('音频转换失败：ffmpeg 返回错误')),
          );
        }
        return null;
      } catch (e) {
        AppLogger.e('ffmpeg not available or failed', e);
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('音频转换失败：ffmpeg 不可用或执行出错')),
          );
        }
        return null;
      }
    }

    AppLogger.w('Audio conversion not supported on this platform');
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台不支持音频转换')),
      );
    }
    return null;
  } catch (e) {
    AppLogger.e('Failed to convert audio', e);
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音频转换时发生未知错误')),
      );
    }
    return null;
  }
}
