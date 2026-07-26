import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/theme_colors.dart';
import '../../providers/browser_provider.dart';
import '../../providers/project_provider.dart';
import '../../services/file_service.dart';

class BrowserPanel extends ConsumerWidget {
  const BrowserPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(browserVisibilityProvider);
    if (!visible) return const SizedBox.shrink();

    return Container(
      width: AppConstants.browserPanelWidth,
      decoration: BoxDecoration(
        color: context.surfaceHigh,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          _BrowserHeader(),
          const _BrowserTabs(),
          const Expanded(child: _BrowserContent()),
        ],
      ),
    );
  }
}

class _BrowserHeader extends ConsumerWidget {
  const _BrowserHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final selectedDir = ref.watch(selectedSamplesDirProvider);
    final bookmarks = ref.watch(browserBookmarksProvider);
    return Container(
      height: AppConstants.timelineHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(51),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open_rounded, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            'BROWSER',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (selectedDir != null)
            Tooltip(
              message: selectedDir,
              child: Icon(Icons.check_circle_outline_rounded, size: 12, color: AppColors.neonGreen),
            ),
          GestureDetector(
            onTap: () async {
              final dir = await FilePicker.platform.getDirectoryPath();
              if (dir != null) {
                ref.read(selectedSamplesDirProvider.notifier).state = dir;
                await persistSelectedSamplesDir(dir);
                ref.invalidate(browserSamplesProvider);
              }
            },
            child: Icon(Icons.folder_outlined, size: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () async {
              if (selectedDir == null) return;
              final bookmarks = List<_BrowserBookmark>.from(ref.read(browserBookmarksProvider));
              final exists = bookmarks.any((b) => b.path == selectedDir);
              if (exists) {
                bookmarks.removeWhere((b) => b.path == selectedDir);
              } else {
                bookmarks.add(_BrowserBookmark(
                  path: selectedDir,
                  addedAt: DateTime.now().toIso8601String(),
                ));
              }
              ref.read(browserBookmarksProvider.notifier).state = bookmarks;
              await persistBrowserBookmarks(bookmarks);
            },
            child: Icon(
              selectedDir != null && bookmarks.any((b) => b.path == selectedDir)
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: 12,
              color: selectedDir != null && bookmarks.any((b) => b.path == selectedDir)
                  ? AppColors.neonYellow
                  : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () async {
              if (bookmarks.isEmpty) return;
              final chosen = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  MediaQuery.of(context).size.width - 200,
                  AppConstants.timelineHeight,
                  MediaQuery.of(context).size.width,
                  AppConstants.timelineHeight + (bookmarks.length * 28.0),
                ),
                items: [
                  ...bookmarks.map((b) {
                    final display = b.label.isNotEmpty
                        ? '${b.label} (${b.path.split('/').last})'
                        : b.path.split('/').last;
                    return PopupMenuItem<String>(
                      value: b.path,
                      child: Row(
                        children: [
                          Icon(Icons.folder_rounded, size: 12, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              display,
                              style: TextStyle(fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final list = List<_BrowserBookmark>.from(ref.read(browserBookmarksProvider));
                              list.removeWhere((item) => item.path == b.path);
                              ref.read(browserBookmarksProvider.notifier).state = list;
                              await persistBrowserBookmarks(list);
                              if (context.mounted) Navigator.of(context).pop();
                            },
                            child: Icon(Icons.close_rounded, size: 10, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
              if (chosen != null) {
                ref.read(selectedSamplesDirProvider.notifier).state = chosen;
                await persistSelectedSamplesDir(chosen);
                ref.invalidate(browserSamplesProvider);
              }
            },
            child: Icon(Icons.bookmark_outline_rounded, size: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () async {
              final path = await exportBrowserBookmarks();
              if (path != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Exported to $path'), duration: const Duration(seconds: 2)),
                );
              }
            },
            child: Icon(Icons.upload_file_rounded, size: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => importBrowserBookmarks(context, ref),
            child: Icon(Icons.download_rounded, size: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => ref.read(browserVisibilityProvider.notifier).state = false,
            child: Icon(Icons.close_rounded, size: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BrowserTabs extends ConsumerWidget {
  const _BrowserTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(browserTabProvider);
    final cs = Theme.of(context).colorScheme;

    final tabs = [
      (BrowserTab.samples, 'Samples'),
      (BrowserTab.presets, 'Presets'),
      (BrowserTab.projects, 'Projects'),
    ];

    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(38),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: tabs.map((tab) {
          final isActive = tab.$1 == currentTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => ref.read(browserTabProvider.notifier).state = tab.$1,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? AppColors.accent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                ),
                child: Text(
                  tab.$2,
                  style: TextStyle(
                    color: isActive ? cs.onSurface : cs.onSurfaceVariant,
                    fontSize: 8,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BrowserContent extends ConsumerStatefulWidget {
  const _BrowserContent();

  @override
  ConsumerState<_BrowserContent> createState() => _BrowserContentState();
}

class _BrowserContentState extends ConsumerState<_BrowserContent> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(() {});
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(browserTabProvider);
    final query = _searchCtrl.text.trim().toLowerCase();

    return Container(
      color: Colors.black.withAlpha(26),
      child: Column(
        children: [
          _BrowserSearchBar(controller: _searchCtrl),
          Expanded(child: _BrowserTree(tab: tab, query: query)),
        ],
      ),
    );
  }
}

class _BrowserSearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _BrowserSearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: TextField(
        controller: controller,
        style: TextStyle(color: cs.onSurface, fontSize: 10),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search...',
          hintStyle: TextStyle(color: cs.onSurfaceVariant.withAlpha(128), fontSize: 10),
          prefixIcon: Icon(Icons.search_rounded, size: 12, color: cs.onSurfaceVariant),
          filled: true,
          fillColor: Colors.black.withAlpha(51),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _BrowserTree extends ConsumerWidget {
  final BrowserTab tab;
  final String query;
  const _BrowserTree({required this.tab, required this.query});

  Future<void> _onItemTap(BuildContext context, WidgetRef ref, _PlaceholderItem item) async {
    if (tab == BrowserTab.projects && item.tag is String) {
      final path = item.tag as String;
      final notifier = ref.read(projectProvider.notifier);
      await notifier.openProject(context);
      AppLogger.i('Open project: ${item.label}');
    } else if (tab == BrowserTab.samples && item.label == 'browser.importAudio'.tr()) {
      final fileService = FileService();
      final result = await fileService.pickAudioFile();
      if (result != null && context.mounted) {
        final trackIndex = ref.read(projectProvider).tracks.length + 1;
        final name = 'track.defaultName'.tr(namedArgs: {'n': '$trackIndex'});
        ref.read(projectProvider.notifier).addTrack(
              name: name,
              audioFilePath: result.audioSource,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('browser.imported'.tr(namedArgs: {'name': result.name})), duration: const Duration(seconds: 2)),
          );
        }
      }
    } else if (tab == BrowserTab.samples && item.tag is String) {
      final path = item.tag as String;
      final trackIndex = ref.read(projectProvider).tracks.length + 1;
      final name = 'track.defaultName'.tr(namedArgs: {'n': '$trackIndex'});
      ref.read(projectProvider.notifier).addTrack(
            name: name,
            audioFilePath: path,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('browser.imported'.tr(namedArgs: {'name': item.label})), duration: const Duration(seconds: 2)),
        );
      }
    } else if (tab == BrowserTab.presets) {
      final preset = InstrumentPreset.allPresets.firstWhere(
        (p) => p.name == item.label,
        orElse: () => InstrumentPreset.presets.first,
      );
      final trackIndex = ref.read(projectProvider).tracks.length + 1;
      final name = 'Track $trackIndex';
      ref.read(projectProvider.notifier).addInstrumentTrack(
            name: name,
            instrumentName: preset.id,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('browser.addedInstrument'.tr(namedArgs: {'name': preset.name})), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    List<_PlaceholderItem> allItems;
    if (tab == BrowserTab.projects) {
      final recent = ref.watch(recentProjectsProvider);
      allItems = recent.when(
        data: (files) => files.map((f) => _PlaceholderItem.file(f.path, f.name)).toList(),
        loading: () => [_PlaceholderItem('Loading...', Icons.hourglass_empty_rounded)],
        error: (_, __) => [_PlaceholderItem('Error loading projects', Icons.error_outline_rounded)],
      );
    } else if (tab == BrowserTab.presets) {
      final presets = ref.watch(browserPresetsProvider);
      allItems = presets
          .map((p) => _PlaceholderItem(p.$1, p.$2))
          .toList();
    } else {
      final samples = ref.watch(browserSamplesProvider);
      allItems = samples.when(
        data: (files) => [
          _PlaceholderItem('browser.importAudio'.tr(), Icons.audio_file_rounded),
          ...files.map((f) => _PlaceholderItem.file(f.path, f.path.split('/').last)),
        ],
        loading: () => [_PlaceholderItem('Loading...', Icons.hourglass_empty_rounded)],
        error: (_, __) => [_PlaceholderItem('Error loading samples', Icons.error_outline_rounded)],
      );
    }

    final filtered = query.isEmpty
        ? allItems
        : allItems.where((item) => item.label.toLowerCase().contains(query)).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'browser.noResults'.tr(),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(128), fontSize: 10),
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        return _BrowserListItem(
          icon: item.icon,
          label: item.label,
          onTap: () => _onItemTap(context, ref, item),
        );
      },
    );
  }
}

class _PlaceholderItem {
  final String label;
  final IconData icon;
  final Object? tag;
  const _PlaceholderItem(this.label, this.icon, {this.tag});

  const _PlaceholderItem.file(String path, this.label)
      : icon = Icons.folder_rounded,
        tag = path;
}

class _BrowserListItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BrowserListItem({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  State<_BrowserListItem> createState() => _BrowserListItemState();
}

class _BrowserListItemState extends State<_BrowserListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: _isHovered ? cs.primary.withAlpha(15) : Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Container(
              height: 24,
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor.withAlpha(38),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 12,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(color: cs.onSurface, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
