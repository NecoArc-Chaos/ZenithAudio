import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/responsive_utils.dart';
import '../../core/utils/theme_colors.dart';
import '../../providers/project_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/floating_window_provider.dart';
import '../toolbar/menu_bar.dart';
import '../toolbar/tool_bar.dart';
import '../layout/floating_window.dart';
import '../mixer/mixer_panel.dart';
import '../browser/browser_panel.dart';
import 'timeline_ruler.dart';
import 'track_panel.dart';
import 'waveform_view.dart';
import 'piano_roll_track.dart';
import 'piano_roll_editor.dart';
import 'audio_clip_editor.dart';
import '../../models/track.dart';

class AudioEditor extends ConsumerStatefulWidget {
  const AudioEditor({super.key});

  @override
  ConsumerState<AudioEditor> createState() => _AudioEditorState();
}

class _AudioEditorState extends ConsumerState<AudioEditor> {
  final ScrollController _rulerScrollCtrl = ScrollController();
  final ScrollController _waveformScrollCtrl = ScrollController();
  bool _syncing = false;
  bool _userInteracted = false;

  bool _recoveryChecked = false;
  final ValueNotifier<double> _playheadNotifier = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _rulerScrollCtrl.addListener(_onRulerScroll);
    _waveformScrollCtrl.addListener(_onWaveformScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_recoveryChecked) {
        _recoveryChecked = true;
        ProjectNotifier.checkForAutoSaveRecovery(context, ref);
      }
    });
    ref.listen<double>(playheadPositionProvider, (_, pos) {
      _playheadNotifier.value = pos;
      _autoScroll(pos);
    });
  }

  @override
  void dispose() {
    _rulerScrollCtrl.removeListener(_onRulerScroll);
    _waveformScrollCtrl.removeListener(_onWaveformScroll);
    _rulerScrollCtrl.dispose();
    _waveformScrollCtrl.dispose();
    super.dispose();
  }

  void _onRulerScroll() {
    if (_syncing) return;
    _syncing = true;
    if (_waveformScrollCtrl.hasClients) {
      _waveformScrollCtrl.jumpTo(_rulerScrollCtrl.offset);
    }
    _syncing = false;
  }

  void _onWaveformScroll() {
    if (_syncing) return;
    _syncing = true;
    if (_rulerScrollCtrl.hasClients) {
      _rulerScrollCtrl.jumpTo(_waveformScrollCtrl.offset);
    }
    setState(() => _userInteracted = true);
    _syncing = false;
  }

  /// Auto-follow: scroll waveform view to keep the playhead visible.
  ///
  /// Called on each playhead position change via the listener below.
  void _autoScroll(double playheadSec) {
    if (!_waveformScrollCtrl.hasClients) return;
    final playing = ref.read(playbackProvider) == PlaybackState.playing;
    if (!playing || _userInteracted) return;

    final pps = ref.read(pixelsPerSecondProvider);
    final offset = _waveformScrollCtrl.offset;
    final viewportWidth = _waveformScrollCtrl.position.viewportDimension;
    final playheadScreenX = playheadSec * pps - offset;

    if (playheadScreenX > viewportWidth * 2 / 3) {
      final target = playheadSec * pps - viewportWidth * 0.2;
      final maxExtent = _waveformScrollCtrl.position.maxScrollExtent;
      _waveformScrollCtrl.animateTo(
        target.clamp(0, maxExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }

    // Reset user-interacted flag once playhead is back in view.
    if (_userInteracted &&
        playheadScreenX >= -10 &&
        playheadScreenX <= viewportWidth + 10) {
      setState(() => _userInteracted = false);
    }
  }

  void _zoom(double factor, double? focusX) {
    final oldPps = ref.read(pixelsPerSecondProvider);
    final newPps = (oldPps * factor).clamp(10.0, 500.0);
    if (newPps == oldPps) return;
    ref.read(pixelsPerSecondProvider.notifier).state = newPps;

    if (_waveformScrollCtrl.hasClients && focusX != null) {
      final offset = _waveformScrollCtrl.offset;
      final ratio = newPps / oldPps;
      final newOffset = (offset + focusX) * ratio - focusX;
      _waveformScrollCtrl.jumpTo(newOffset);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_waveformScrollCtrl.hasClients) return;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final delta = event.scrollDelta.dy;

    if (isCtrl) {
      final factor = delta < 0 ? 1.15 : 1 / 1.15;
      final box = context.findRenderObject() as RenderBox?;
      final localPos = box != null ? box.globalToLocal(event.position) : Offset.zero;
      _zoom(factor, localPos.dx);
    } else {
      _waveformScrollCtrl.jumpTo(
        (_waveformScrollCtrl.offset + delta * 3)
            .clamp(0, _waveformScrollCtrl.position.maxScrollExtent),
      );
    }
  }

  void _scrollToPlayhead() {
    if (!_waveformScrollCtrl.hasClients) return;
    final pps = ref.read(pixelsPerSecondProvider);
    final playhead = ref.read(playheadPositionProvider);
    final target = playhead * pps - 50;
    _waveformScrollCtrl.animateTo(
      target.clamp(0, _waveformScrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    setState(() => _userInteracted = false);
  }

  void _openAudioClipEditor(BuildContext context, String trackId) {
    final settings = ref.read(settingsProvider);
    if (settings.editorMode == 'float') {
      final track = ref.read(projectProvider).tracks.firstWhere((t) => t.id == trackId);
      ref.read(floatingWindowProvider.notifier).open(
        title: 'Audio: ${track.name}',
        builder: (_) => AudioClipEditor(
          trackId: trackId,
          isFloating: true,
        ),
      );
    } else {
      openAudioClipEditor(context, trackId);
    }
  }

  void _openPianoRoll(String trackId) {
    final settings = ref.read(settingsProvider);
    if (settings.editorMode == 'float') {
      final track = ref.read(projectProvider).tracks.firstWhere((t) => t.id == trackId);
      ref.read(floatingWindowProvider.notifier).open(
        title: 'Piano Roll: ${track.name}',
        builder: (_) => PianoRollEditor(
          trackId: trackId,
          isFloating: true,
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PianoRollEditor(trackId: trackId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider);
    final pps = ref.watch(pixelsPerSecondProvider);
    final screenSize = getScreenSize(context);
    final totalWidth = (project.duration > 0 ? project.duration : 60) * pps;

    // Listen for playback state changes to reset user-interacted on play.
    ref.listen<PlaybackState>(playbackProvider, (_, next) {
      if (next == PlaybackState.playing) {
        setState(() => _userInteracted = false);
      }
    });

    return PopScope(
      canPop: !ref.read(projectProvider.notifier).isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await ref.read(projectProvider.notifier).confirmDiscard(context);
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                if (screenSize != ScreenSize.mobile) const AudioMenuBar(),
                const AudioToolBar(),
                Expanded(
                  child: Listener(
                    onPointerSignal: _onPointerSignal,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            if (screenSize != ScreenSize.mobile)
                              const SizedBox(width: AppConstants.trackPanelWidth),
                            Expanded(
                              child: ClipRect(
                                child: SingleChildScrollView(
                                  controller: _rulerScrollCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: TimelineRuler(
                                    duration: project.duration > 0 ? project.duration : 60,
                                    pixelsPerSecond: pps,
                                    currentPosition: 0,
                                    bpm: project.bpm,
                                    timeSignatureNumerator: project.timeSignatureNumerator,
                                    onSeek: (sec) =>
                                        ref.read(playbackProvider.notifier).seekTo(sec),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              const BrowserPanel(),
                              const TrackPanel(),
                              Expanded(
                                child: ClipRect(
                                  child: Stack(
                                    children: [
                                      project.tracks.isEmpty
                                          ? _buildEmptyState(context)
                                          : SingleChildScrollView(
                                              controller: _waveformScrollCtrl,
                                              scrollDirection: Axis.horizontal,
                                              physics: const ClampingScrollPhysics(),
                                              child: SizedBox(
                                                width: totalWidth,
                                                child: ListView.builder(
                                                  itemCount: project.tracks.length,
                                                  itemExtent: AppConstants.trackTileHeight,
                                                  itemBuilder: (context, index) {
                                                    final tr = project.tracks[index];
                                                      if (tr.type.isInstrument) {
                                                        return PianoRollTrack(
                                                          track: tr,
                                                          pixelsPerSecond: pps,
                                                          onEdit: () => _openPianoRoll(tr.id),
                                                        );
                                                      }
                                                    return WaveformView(
                                                      track: tr,
                                                      pixelsPerSecond: pps,
                                                      onTap: () => _openAudioClipEditor(context, tr.id),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                      _PlayheadOverlay(
                                        pixelsPerSecond: pps,
                                        scrollCtrl: _waveformScrollCtrl,
                                        playheadNotifier: _playheadNotifier,
                                        onScrollToPlayhead: _scrollToPlayhead,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const MixerPanel(),
              ],
            ),
            // Floating windows overlay
            ...ref.watch(floatingWindowProvider).map((fw) {
              final notifier = ref.read(floatingWindowProvider.notifier);
              return FloatingWindow(
                key: ValueKey(fw.id),
                windowId: fw.id,
                title: fw.title,
                initialSize: fw.size,
                initialPosition: fw.position,
                isMinimized: fw.isMinimized,
                onMinimize: () => notifier.toggleMinimize(fw.id),
                onClose: () => notifier.close(fw.id),
                onMove: () => notifier.bringToFront(fw.id),
                onPositionChanged: (pos) => notifier.updatePosition(fw.id, pos),
                onSizeChanged: (size) => notifier.updateSize(fw.id, size),
                child: fw.builder(context),
              );
            }),
          ],
        ),     // Stack
      ),       // SafeArea
    ),        // Scaffold
  );          // PopScope + return
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.waves_outlined, size: 64,
              color: context.outline.withAlpha(77)),
          const SizedBox(height: 16),
          Text('editor.emptyTitle'.tr(),
              style: TextStyle(color: context.outline.withAlpha(153), fontSize: 14)),
          const SizedBox(height: 8),
          Text('editor.emptySubtitle'.tr(),
              style: TextStyle(color: context.outline.withAlpha(102), fontSize: 11)),
        ],
      ),
    );
  }
}

class _PlayheadOverlay extends StatelessWidget {
  final double pixelsPerSecond;
  final ScrollController scrollCtrl;
  final ValueNotifier<double> playheadNotifier;
  final VoidCallback onScrollToPlayhead;

  const _PlayheadOverlay({
    required this.pixelsPerSecond,
    required this.scrollCtrl,
    required this.playheadNotifier,
    required this.onScrollToPlayhead,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([playheadNotifier, scrollCtrl]),
      builder: (context, child) {
        final playhead = playheadNotifier.value;
        final offset = scrollCtrl.hasClients ? scrollCtrl.offset : 0;
        final screenX = playhead * pixelsPerSecond - offset;
        final vpw = scrollCtrl.hasClients ? scrollCtrl.position.viewportDimension : 0;
        final showBack = screenX < -10 || screenX > vpw + 10;

        return Stack(
          children: [
            // Playhead line
            Positioned(
              left: screenX,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(width: 2, color: AppColors.playhead),
              ),
            ),
            // Back-to-playhead button
            if (showBack)
              Positioned(
                right: 8,
                top: 8,
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onScrollToPlayhead,
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
