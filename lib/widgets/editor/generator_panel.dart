import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/audio_clip.dart';
import '../../services/waveform_generator.dart';
import '../../services/wav_encoder.dart';

class GeneratorPanel extends StatefulWidget {
  final void Function(Float64List samples, String type) onGenerate;

  const GeneratorPanel({super.key, required this.onGenerate});

  @override
  State<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends State<GeneratorPanel> {
  String _waveType = 'sine';
  double _frequency = 440;
  double _duration = 2.0;
  double _amplitude = 0.8;
  double _dutyCycle = 0.5;
  int? _noiseSeed;
  bool _isPreviewing = false;
  Player? _previewPlayer;

  static const _waveTypes = [
    ('sine', 'Sine'),
    ('square', 'Square'),
    ('sawtooth', 'Sawtooth'),
    ('triangle', 'Triangle'),
    ('pulse', 'Pulse'),
    ('whiteNoise', 'White Noise'),
    ('pinkNoise', 'Pink Noise'),
    ('brownNoise', 'Brown Noise'),
  ];

  @override
  void dispose() {
    _previewPlayer?.dispose();
    super.dispose();
  }

  Float64List _generate() {
    switch (_waveType) {
      case 'sine':
        return WaveformGenerator.sine(_frequency, _duration, amplitude: _amplitude);
      case 'square':
        return WaveformGenerator.square(_frequency, _duration, amplitude: _amplitude, dutyCycle: _dutyCycle);
      case 'sawtooth':
        return WaveformGenerator.sawtooth(_frequency, _duration, amplitude: _amplitude);
      case 'triangle':
        return WaveformGenerator.triangle(_frequency, _duration, amplitude: _amplitude);
      case 'pulse':
        return WaveformGenerator.pulse(_frequency, _duration, amplitude: _amplitude, dutyCycle: _dutyCycle);
      case 'whiteNoise':
        return WaveformGenerator.whiteNoise(_duration, amplitude: _amplitude, seed: _noiseSeed);
      case 'pinkNoise':
        return WaveformGenerator.pinkNoise(_duration, amplitude: _amplitude);
      case 'brownNoise':
        return WaveformGenerator.brownNoise(_duration, amplitude: _amplitude);
      default:
        return WaveformGenerator.sine(_frequency, _duration, amplitude: _amplitude);
    }
  }

  Future<void> _preview() async {
    if (_isPreviewing) return;
    _isPreviewing = true;

    final samples = _generate();
    final wav = _encodeWav(samples);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/gen_preview.wav';
    await File(path).writeAsBytes(wav);

    await _previewPlayer?.dispose();
    final player = Player();
    _previewPlayer = player;
    player.stream.completed.listen((_) => _isPreviewing = false);

    try {
      await player.open(Media(Uri.file(path).toString()));
      await player.setVolume(80);
      player.play();
    } catch (_) {
      _isPreviewing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNoiseType = _waveType.contains('Noise');
    final isPulseType = _waveType == 'pulse' || _waveType == 'square';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Waveform', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              DropdownButton<String>(
                value: _waveType,
                isDense: true,
                style: TextStyle(fontSize: 12, color: cs.onSurface),
                underline: const SizedBox(),
                items: _waveTypes.map((wt) =>
                    DropdownMenuItem(value: wt.$1, child: Text(wt.$2))).toList(),
                onChanged: (v) => setState(() => _waveType = v!),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!isNoiseType) ...[
            _ParamSlider(
              label: 'Frequency',
              value: _frequency,
              min: 20, max: 20000,
              display: '${_frequency.round()} Hz',
              logarithmic: true,
              onChanged: (v) => setState(() => _frequency = v),
            ),
          ],
          _ParamSlider(
            label: 'Duration',
            value: _duration,
            min: 0.1, max: 30,
            display: '${_duration.toStringAsFixed(1)} s',
            onChanged: (v) => setState(() => _duration = v),
          ),
          _ParamSlider(
            label: 'Amplitude',
            value: _amplitude,
            min: 0, max: 1,
            display: '${(_amplitude * 100).round()}%',
            onChanged: (v) => setState(() => _amplitude = v),
          ),
          if (isPulseType)
            _ParamSlider(
              label: 'Duty Cycle',
              value: _dutyCycle,
              min: 0.01, max: 0.99,
              display: _dutyCycle.toStringAsFixed(2),
              onChanged: (v) => setState(() => _dutyCycle = v),
            ),
          if (_waveType == 'whiteNoise') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Seed:', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'random',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _noiseSeed = int.tryParse(v)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                icon: Icon(Icons.play_arrow, size: 16),
                label: const Text('Preview', style: TextStyle(fontSize: 11)),
                onPressed: _isPreviewing ? null : _preview,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: Icon(Icons.add, size: 16),
                label: const Text('Generate to Track', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  final samples = _generate();
                  widget.onGenerate(samples, _waveType);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Uint8List _encodeWav(Float64List buffer) {
    return WavEncoder.encode(buffer, buffer.length, WaveformGenerator.defaultSampleRate);
  }
}

class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final bool logarithmic;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    this.logarithmic = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sliderVal = logarithmic
        ? ((log(value / min) / log(max / min)) as double)
        : ((value - min) / (max - min));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
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
                  onChanged(real.clamp(min, max));
                },
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(display, style: TextStyle(fontSize: 10, color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}
