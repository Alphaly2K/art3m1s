import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/ps5_chrome.dart';
import '../adaptive/ps5_menu.dart';
import '../controllers/library_actions.dart';
import '../controllers/ps5_input.dart';
import '../models/game_engine.dart';
import '../models/game_entry.dart';
import '../providers/library_provider.dart';
import '../widgets/ps5_cover_art.dart';

enum GameLibrarySort { mostRecent, purchasedNew, purchasedOld, nameAz, nameZa }

enum GameLibraryTab { collection, installed, art3m1s, fvp }

enum GameLibraryPlatformFilter { all, art3m1s, rfvp, krkr }

enum GameLibrarySourceFilter { all, directory, pfs }

class Ps5GameLibraryPage extends ConsumerStatefulWidget {
  const Ps5GameLibraryPage({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<Ps5GameLibraryPage> createState() => _Ps5GameLibraryPageState();
}

class _Ps5GameLibraryPageState extends ConsumerState<Ps5GameLibraryPage> {
  GameLibraryTab _tab = GameLibraryTab.collection;
  GameLibrarySort _sort = GameLibrarySort.mostRecent;
  GameLibraryPlatformFilter _platform = GameLibraryPlatformFilter.all;
  GameLibrarySourceFilter _source = GameLibrarySourceFilter.all;
  int _selectedIndex = 0;

  bool get _filtersActive =>
      _platform != GameLibraryPlatformFilter.all ||
      _source != GameLibrarySourceFilter.all;

  String get _sortLabel => switch (_sort) {
    GameLibrarySort.mostRecent => 'Most Recent',
    GameLibrarySort.purchasedNew => 'Purchased Date (New - Old)',
    GameLibrarySort.purchasedOld => 'Purchased Date (Old - New)',
    GameLibrarySort.nameAz => 'Name (A - Z)',
    GameLibrarySort.nameZa => 'Name (Z - A)',
  };

  String get _platformLabel => switch (_platform) {
    GameLibraryPlatformFilter.all => 'All',
    GameLibraryPlatformFilter.art3m1s => 'Artemis',
    GameLibraryPlatformFilter.rfvp => 'FVP',
    GameLibraryPlatformFilter.krkr => 'Kirikiri',
  };

  String get _sourceLabel => switch (_source) {
    GameLibrarySourceFilter.all => 'All',
    GameLibrarySourceFilter.directory => '工程目录',
    GameLibrarySourceFilter.pfs => 'PFS',
  };

  List<GameEntry> _visibleGames(List<GameEntry> library) {
    Iterable<GameEntry> games = library;
    games = switch (_tab) {
      GameLibraryTab.collection || GameLibraryTab.installed => games,
      GameLibraryTab.art3m1s => games.where(
        (entry) => entry.engine == GameEngineKind.art3m1s,
      ),
      GameLibraryTab.fvp => games.where(
        (entry) => entry.engine == GameEngineKind.rfvp,
      ),
    };
    games = switch (_platform) {
      GameLibraryPlatformFilter.all => games,
      GameLibraryPlatformFilter.art3m1s => games.where(
        (entry) => entry.engine == GameEngineKind.art3m1s,
      ),
      GameLibraryPlatformFilter.rfvp => games.where(
        (entry) => entry.engine == GameEngineKind.rfvp,
      ),
      GameLibraryPlatformFilter.krkr => games.where(
        (entry) => entry.engine == GameEngineKind.krkr,
      ),
    };
    games = switch (_source) {
      GameLibrarySourceFilter.all => games,
      GameLibrarySourceFilter.directory => games.where(
        (entry) => entry.source == GameSource.directory,
      ),
      GameLibrarySourceFilter.pfs => games.where(
        (entry) => entry.source == GameSource.pfsArchive,
      ),
    };
    final list = games.toList();
    int byName(GameEntry a, GameEntry b) => a.displayNameOrName
        .toLowerCase()
        .compareTo(b.displayNameOrName.toLowerCase());
    int byAdded(GameEntry a, GameEntry b) => a.addedAt.compareTo(b.addedAt);
    int byRecent(GameEntry a, GameEntry b) {
      final aPlayed = a.lastPlayedAt ?? a.addedAt;
      final bPlayed = b.lastPlayedAt ?? b.addedAt;
      final played = bPlayed.compareTo(aPlayed);
      return played != 0 ? played : b.addedAt.compareTo(a.addedAt);
    }

    list.sort(
      (a, b) => switch (_sort) {
        GameLibrarySort.mostRecent => byRecent(a, b),
        GameLibrarySort.purchasedNew => byAdded(b, a),
        GameLibrarySort.purchasedOld => byAdded(a, b),
        GameLibrarySort.nameAz => byName(a, b),
        GameLibrarySort.nameZa => byName(b, a),
      },
    );
    return list;
  }

  Future<void> _openFilterMenu() async {
    final result = await showPs5ListMenu<Object>(
      context,
      sections: [
        Ps5MenuSection(
          items: [
            Ps5MenuItem(
              id: 'sort',
              label: 'Sort by',
              trailing: _sortLabel,
              value: _sort,
              choices: const [
                Ps5MenuChoice(
                  value: GameLibrarySort.mostRecent,
                  label: 'Most Recent',
                ),
                Ps5MenuChoice(
                  value: GameLibrarySort.purchasedNew,
                  label: 'Purchased Date (New - Old)',
                ),
                Ps5MenuChoice(
                  value: GameLibrarySort.purchasedOld,
                  label: 'Purchased Date (Old - New)',
                ),
                Ps5MenuChoice(
                  value: GameLibrarySort.nameAz,
                  label: 'Name (A - Z)',
                ),
                Ps5MenuChoice(
                  value: GameLibrarySort.nameZa,
                  label: 'Name (Z - A)',
                ),
              ],
            ),
          ],
        ),
        Ps5MenuSection(
          title: 'Filters',
          items: [
            Ps5MenuItem(
              id: 'platform',
              label: 'Platform',
              trailing: _platform == GameLibraryPlatformFilter.all
                  ? null
                  : _platformLabel,
              value: _platform,
              choices: const [
                Ps5MenuChoice(
                  value: GameLibraryPlatformFilter.all,
                  label: 'All',
                ),
                Ps5MenuChoice(
                  value: GameLibraryPlatformFilter.art3m1s,
                  label: 'Artemis',
                ),
                Ps5MenuChoice(
                  value: GameLibraryPlatformFilter.rfvp,
                  label: 'FVP',
                ),
                Ps5MenuChoice(
                  value: GameLibraryPlatformFilter.krkr,
                  label: 'Kirikiri',
                ),
              ],
            ),
            Ps5MenuItem(
              id: 'source',
              label: 'Source',
              trailing: _source == GameLibrarySourceFilter.all
                  ? null
                  : _sourceLabel,
              value: _source,
              choices: const [
                Ps5MenuChoice(value: GameLibrarySourceFilter.all, label: 'All'),
                Ps5MenuChoice(
                  value: GameLibrarySourceFilter.directory,
                  label: '工程目录',
                ),
                Ps5MenuChoice(value: GameLibrarySourceFilter.pfs, label: 'PFS'),
              ],
            ),
          ],
        ),
      ],
      footerLabel: 'Reset Filters',
      footerEnabled: _filtersActive,
    );
    if (!mounted || result == null) return;
    setState(() {
      switch (result.itemId) {
        case 'sort':
          _sort = result.value as GameLibrarySort? ?? _sort;
        case 'platform':
          _platform = result.value as GameLibraryPlatformFilter? ?? _platform;
        case 'source':
          _source = result.value as GameLibrarySourceFilter? ?? _source;
        case 'reset':
          _platform = GameLibraryPlatformFilter.all;
          _source = GameLibrarySourceFilter.all;
      }
    });
  }

  Future<void> _openGameMenu(GameEntry entry, LibraryActions actions) async {
    final result = await showPs5ListMenu<int>(
      context,
      sections: [
        Ps5MenuSection(
          items: [
            const Ps5MenuItem(id: 'play', label: '开始游戏', value: 0),
            const Ps5MenuItem(id: 'edit', label: '编辑项目', value: 1),
            const Ps5MenuItem(
              id: 'delete',
              label: '从库中移除',
              value: 2,
              destructive: true,
            ),
          ],
        ),
      ],
    );
    if (!mounted || result == null) return;
    switch (result.itemId) {
      case 'play':
        actions.launch(entry);
      case 'edit':
        actions.editGame(entry);
      case 'delete':
        actions.confirmDelete(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final games = _visibleGames(library);
    if (_selectedIndex >= games.length) {
      _selectedIndex = games.isEmpty ? 0 : games.length - 1;
    }
    final actions = LibraryActions(context, ref);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (ps5InputAction(event.logicalKey) == Ps5InputAction.back) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        key: const ValueKey('ps5-game-library-page'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 8, 48, 0),
            child: Row(
              children: [
                _HeaderIconButton(onPressed: widget.onClose),
                const SizedBox(width: 16),
                const Text(
                  'Game Library',
                  style: TextStyle(
                    color: Ps5Colors.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Row(
              children: [
                for (final tab in GameLibraryTab.values) ...[
                  if (tab != GameLibraryTab.collection)
                    const SizedBox(width: 28),
                  _LibraryTab(
                    label: switch (tab) {
                      GameLibraryTab.collection => 'Your Collection',
                      GameLibraryTab.installed => 'Installed',
                      GameLibraryTab.art3m1s => 'Artemis',
                      GameLibraryTab.fvp => 'FVP',
                    },
                    selected: _tab == tab,
                    onPressed: () => setState(() {
                      _tab = tab;
                      _selectedIndex = 0;
                    }),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Row(
              children: [
                Text(
                  'All: ${games.length}',
                  style: const TextStyle(
                    color: Ps5Colors.menuMuted,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  'Sort by: $_sortLabel',
                  style: const TextStyle(
                    color: Ps5Colors.menuMuted,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: games.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '没有匹配的游戏',
                          style: TextStyle(
                            color: Ps5Colors.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Ps5Button(
                          primary: true,
                          icon: Icons.folder_open_rounded,
                          onPressed: actions.pickDirectory,
                          child: const Text('选择游戏文件夹'),
                        ),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 28,
                          right: 8,
                          top: 8,
                        ),
                        child: _FilterButton(onPressed: _openFilterMenu),
                      ),
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 8, 48, 36),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 286,
                                mainAxisSpacing: 20,
                                crossAxisSpacing: 18,
                                childAspectRatio: 1,
                              ),
                          itemCount: games.length,
                          itemBuilder: (context, index) {
                            final entry = games[index];
                            return _LibraryGridTile(
                              entry: entry,
                              selected: index == _selectedIndex,
                              autofocus: index == _selectedIndex,
                              onFocus: () {
                                if (_selectedIndex != index) {
                                  setState(() => _selectedIndex = index);
                                }
                              },
                              onOpen: () => actions.launch(entry),
                              onMenu: () => _openGameMenu(entry, actions),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onFocusChange: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _focused ? const Color(0xFFE8EEF6) : const Color(0xFF1B1F27),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Ps5GameLibraryGlyph(
              size: 28,
              color: _focused ? Ps5Colors.background : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryTab extends StatefulWidget {
  const _LibraryTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;
    return FocusableActionDetector(
      onFocusChange: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? Ps5Colors.text : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: active ? Ps5Colors.text : const Color(0x66FFFFFF),
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatefulWidget {
  const _FilterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<_FilterButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sort & Filters',
      child: FocusableActionDetector(
        onFocusChange: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            key: const ValueKey('ps5-library-filter-button'),
            duration: const Duration(milliseconds: 160),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _focused
                  ? const Color(0xFFE8EEF6)
                  : const Color(0xFF23262E),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.sort_rounded,
              color: _focused ? Ps5Colors.background : Ps5Colors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryGridTile extends StatefulWidget {
  const _LibraryGridTile({
    required this.entry,
    required this.selected,
    required this.autofocus,
    required this.onFocus,
    required this.onOpen,
    required this.onMenu,
  });

  final GameEntry entry;
  final bool selected;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  State<_LibraryGridTile> createState() => _LibraryGridTileState();
}

class _LibraryGridTileState extends State<_LibraryGridTile> {
  Timer? _hoverTimer;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (value) {
        if (value) widget.onFocus();
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onOpen();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) {
          _hoverTimer?.cancel();
          _hoverTimer = Timer(const Duration(milliseconds: 180), () {
            if (mounted) widget.onFocus();
          });
        },
        onExit: (_) {
          _hoverTimer?.cancel();
          _hoverTimer = null;
        },
        child: GestureDetector(
          onTap: widget.onOpen,
          onSecondaryTap: widget.onMenu,
          onLongPress: widget.onMenu,
          child: AnimatedScale(
            scale: active ? 1.055 : 1,
            alignment: Alignment.center,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: Ps5FocusFrame(
              selected: active,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Ps5CoverArt(entry: widget.entry),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xC9000000)],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 30, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.entry.displayNameOrName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Ps5Colors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Installed',
                              style: TextStyle(
                                color: Ps5Colors.menuMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
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
