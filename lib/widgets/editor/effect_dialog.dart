import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/wav_encoder.dart';

/// Result from an effect dialog: [samples] is null if cancelled.
class EffectResult {
  final Float64List? samples;

  const EffectResult(this.samples);
}

/// Show a floating effect dialog.
///
/// [title] — effect name shown in the title bar.
/// [clipSamples] — the current clip samples (for preview rendering).
/// [sampleRate] — sample rate of the clip.
/// [initialParams] — map of parameter names to initial numeric values.
/// [process] — function that takes samples + params and returns processed samples.
/// [builder] — widget builder that receives context + current params map + onChanged callback.
///
/// Returns [EffectResult] — .samples is null if cancelled, otherwise the processed samples.
Future<EffectResult> showEffectDialog({
  required BuildContext context,
  required String title,
  required Float64List clipSamples,
  required int sampleRate,
  required Map<String, double> initialParams,
  required Float64List Function(Float64List samples, int sampleRate, Map<String, double> params) process,
  required Widget Function(BuildContext, Map<String, double>, void Function(String, double) onParamChanged) builder,
}) {
  return showDialog<EffectResult>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (ctx) => _EffectDialog(
      title: title,
      clipSamples: clipSamples,
      sampleRate: sampleRate,
      initialParams: initialParams,
      process: process,
      builder: builder,
    ),
  ).then((r) => r ?? const EffectResult(null));
}

class _EffectDialog extends StatefulWidget {
  final String title;
  final Float64List clipSamples;
  final int sampleRate;
  final Map<String, double> initialParams;
  final Float64List Function(Float64List, int, Map<String, double>) process;
  final Widget Function(BuildContext, Map<String, double>, void Function(String, double)) builder;

  const _EffectDialog({
    required this.title,
    required this.clipSamples,
    required this.sampleRate,
    required this.initialParams,
    required this.process,
    required this.builder,
  });

  @override
  State<_EffectDialog> createState() => _EffectDialogState();
}

class _EffectDialogState extends State<_EffectDialog> {
  late Map<String, double> _params;
  Player? _previewPlayer;
  bool _previewing = false;

  static const _previewDurationSec = 2.0;

  @override
  void initState() {
    super.initState();
    _params = Map.from(widget.initialParams);
  }

  @override
  void dispose() {
    _previewPlayer?.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    if (_previewing) return;
    _previewing = true;

    // Process a 2-second segment roughly centered
    final sampleCount = (_previewDurationSec * widget.sampleRate).round();
    final halfClip = widget.clipSamples.length ~/ 2;
    final halfPreview = sampleCount ~/ 2;
    final startSample = (halfClip - halfPreview).clamp(0, widget.clipSamples.length - sampleCount);
    final segment = widget.clipSamples.sublist(startSample, startSample + sampleCount);

    final processed = widget.process(segment, widget.sampleRate, _params);

    // Encode as WAV and play
    final wav = _encodeWavPreview(processed, widget.sampleRate);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/effect_preview.wav';
    await File(path).writeAsBytes(wav);

    await _previewPlayer?.dispose();
    final player = Player();
    _previewPlayer = player;
    player.stream.completed.listen((_) {
      if (mounted) setState(() => _previewing = false);
    });
    player.stream.error.listen((_) {
      if (mounted) setState(() => _previewing = false);
    });

    try {
      await player.open(Media(Uri.file(path).toString()));
      await player.setVolume(80);
      player.play();
    } catch (_) {
      if (mounted) setState(() => _previewing = false);
    }
  }

  void _apply() {
    final result = widget.process(widget.clipSamples, widget.sampleRate, _params);
    Navigator.of(context).pop(EffectResult(result));
  }

  void _cancel() {
    Navigator.of(context).pop(const EffectResult(null));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    return Dialog(
      insetPadding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.symmetric(
        horizontal: max(MediaQuery.of(context).size.width * 0.15, 280),
        vertical: 48,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(color: cs.surface),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: cs.outlineVariant.withAlpha(77))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                    ),
                    _MiniBtn(icon: Icons.close, size: 16, onTap: _cancel),
                  ],
                ),
              ),
              // Parameters area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: widget.builder(context, _params, (name, value) {
                    setState(() => _params[name] = value);
                  }),
                ),
              ),
              // Button bar
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: cs.outlineVariant.withAlpha(77))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      icon: Icon(_previewing ? Icons.stop : Icons.play_arrow, size: 14),
                      label: Text(_previewing ? 'Stop' : 'Preview', style: const TextStyle(fontSize: 11)),
                      onPressed: _previewing ? null : _preview,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _cancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Cancel', style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _apply,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Apply', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Uint8List _encodeWavPreview(Float64List buffer, int sampleRate) {
    return WavEncoder.encode(buffer, buffer.length, sampleRate);
  }
}

class _EffectSlider extends StatelessWidget {
  final String label;
  final String paramKey;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) display;
  final void Function(String, double) onChanged;
  final bool logarithmic;

  const _EffectSlider({
    required this.label,
    required this.paramKey,
    required this.value,
    required this.min,
    required this.max,
    this.divisions = 100,
    required this.display,
    required this.onChanged,
    this.logarithmic = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sliderVal = logarithmic
        ? ((log(value / min) / log(max / min))).clamp(0.0, 1.0)
        : ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: sliderVal.clamp(0.0, 1.0),
                onChanged: (v) {
                  final real = logarithmic
                      ? min * pow(max / min, v)
                      : min + (max - min) * v;
                  onChanged(paramKey, real.clamp(min, max));
                },
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(display(value), style: TextStyle(fontSize: 10, color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}

/// Helper: build a slider param row.
Widget effectSlider({
  required String label,
  required String paramKey,
  required Map<String, double> params,
  required void Function(String, double) onChanged,
  double min = 0,
  double max = 1,
  int divisions = 100,
  String Function(double)? display,
  bool logarithmic = false,
  double defaultValue = 0,
}) {
  final value = params[paramKey] ?? defaultValue;
  return _EffectSlider(
    label: label,
    paramKey: paramKey,
    value: value,
    min: min,
    max: max,
    divisions: divisions,
    display: display ?? ((v) => v.toStringAsFixed(1)),
    onChanged: onChanged,
    logarithmic: logarithmic,
  );
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _MiniBtn({required this.icon, this.size = 18, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: size),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        splashRadius: 14,
      ),
    );
  }
}
