import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/ps5_chrome.dart';
import '../adaptive/ps5_menu.dart';
import '../adaptive/ps5_sounds.dart';
import '../controllers/library_actions.dart';
import '../controllers/ps5_input.dart';
import '../models/game_engine.dart';
import '../models/game_entry.dart';
import '../providers/library_provider.dart';
import '../widgets/ps5_cover_art.dart';

enum GameLibrarySort { recentlyPlayed, nameAz, nameZa }

enum GameLibraryTab { collection, installed, art3m1s, fvp, kirikiri }

enum GameLibraryPlatformFilter { all, art3m1s, rfvp, krkr }

enum GameLibrarySourceFilter { all, directory, pfs }

class Ps5GameLibraryPage extends ConsumerStatefulWidget {
  const Ps5GameLibraryPage({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<Ps5GameLibraryPage> createState() => _Ps5GameLibraryPageState();
}

class _Ps5GameLibraryPageState extends ConsumerState<Ps5GameLibraryPage> {
  final GlobalKey _filterButtonKey = GlobalKey();
  GameLibraryTab _tab = GameLibraryTab.collection;
  GameLibrarySort _sort = GameLibrarySort.recentlyPlayed;
  GameLibraryPlatformFilter _platform = GameLibraryPlatformFilter.all;
  GameLibrarySourceFilter _source = GameLibrarySourceFilter.all;
  int _selectedIndex = 0;
  int _tabDirection = 1;

  bool get _filtersActive =>
      _platform != GameLibraryPlatformFilter.all ||
      _source != GameLibrarySourceFilter.all;

  Rect? _filterAnchor() {
    final box = _filterButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _selectTab(GameLibraryTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tabDirection = tab.index >= _tab.index ? 1 : -1;
      _tab = tab;
      _selectedIndex = 0;
    });
  }

  String get _sortLabel => switch (_sort) {
    GameLibrarySort.recentlyPlayed => '最近游玩',
    GameLibrarySort.nameAz => '名称（A - Z）',
    GameLibrarySort.nameZa => '名称（Z - A）',
  };

  String get _platformLabel => switch (_platform) {
    GameLibraryPlatformFilter.all => '全部',
    GameLibraryPlatformFilter.art3m1s => 'Artemis',
    GameLibraryPlatformFilter.rfvp => 'FVP',
    GameLibraryPlatformFilter.krkr => 'Kirikiri',
  };

  String get _sourceLabel => switch (_source) {
    GameLibrarySourceFilter.all => '全部',
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
      GameLibraryTab.kirikiri => games.where(
        (entry) => entry.engine == GameEngineKind.krkr,
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
    int byRecent(GameEntry a, GameEntry b) {
      final aPlayed = a.lastPlayedAt ?? a.addedAt;
      final bPlayed = b.lastPlayedAt ?? b.addedAt;
      final played = bPlayed.compareTo(aPlayed);
      return played != 0 ? played : b.addedAt.compareTo(a.addedAt);
    }

    list.sort(
      (a, b) => switch (_sort) {
        GameLibrarySort.recentlyPlayed => byRecent(a, b),
        GameLibrarySort.nameAz => byName(a, b),
        GameLibrarySort.nameZa => byName(b, a),
      },
    );
    return list;
  }

  Future<void> _openFilterMenu() async {
    final result = await showPs5ListMenu<Object>(
      context,
      anchor: _filterAnchor(),
      sections: [
        Ps5MenuSection(
          items: [
            Ps5MenuItem(
              id: 'sort',
              label: '排序方式',
              trailing: _sortLabel,
              value: _sort,
              choices: const [
                Ps5MenuChoice(
                  value: GameLibrarySort.recentlyPlayed,
                  label: '最近游玩',
                ),
                Ps5MenuChoice(
                  value: GameLibrarySort.nameAz,
                  label: '名称（A - Z）',
                ),
                Ps5MenuChoice(
                  value: GameLibrarySort.nameZa,
                  label: '名称（Z - A）',
                ),
              ],
            ),
          ],
        ),
        Ps5MenuSection(
          title: '筛选',
          items: [
            Ps5MenuItem(
              id: 'platform',
              label: '运行引擎',
              trailing: _platform == GameLibraryPlatformFilter.all
                  ? null
                  : _platformLabel,
              value: _platform,
              choices: const [
                Ps5MenuChoice(
                  value: GameLibraryPlatformFilter.all,
                  label: '全部',
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
              label: '来源',
              trailing: _source == GameLibrarySourceFilter.all
                  ? null
                  : _sourceLabel,
              value: _source,
              choices: const [
                Ps5MenuChoice(value: GameLibrarySourceFilter.all, label: '全部'),
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
      footerLabel: '重置筛选',
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
      header: Row(
        children: [
          SizedBox.square(
            dimension: 52,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Ps5CoverArt(entry: entry),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayNameOrName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Ps5Colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.engine.label,
                  style: const TextStyle(
                    color: Ps5Colors.menuMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
          Ps5UiSounds.back();
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        key: const ValueKey('ps5-game-library-page'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 112),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Row(
              children: [
                for (final tab in GameLibraryTab.values) ...[
                  if (tab != GameLibraryTab.collection)
                    const SizedBox(width: 28),
                  _LibraryTab(
                    label: switch (tab) {
                      GameLibraryTab.collection => '全部游戏',
                      GameLibraryTab.installed => '已安装',
                      GameLibraryTab.art3m1s => 'Artemis',
                      GameLibraryTab.fvp => 'FVP',
                      GameLibraryTab.kirikiri => 'Kirikiri',
                    },
                    selected: _tab == tab,
                    onPressed: () => _selectTab(tab),
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
                  '全部：${games.length}',
                  style: const TextStyle(
                    color: Ps5Colors.menuMuted,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '排序：$_sortLabel',
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 28, right: 8, top: 8),
                  child: _FilterButton(
                    key: _filterButtonKey,
                    onPressed: _openFilterMenu,
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: _Ps5TabSlide(
                      tabIndex: _tab.index,
                      direction: _tabDirection,
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
                          : GridView.builder(
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
                                  key: ValueKey(
                                    'ps5-game-library-tile-${entry.path}',
                                  ),
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

class _Ps5TabSlide extends StatelessWidget {
  const _Ps5TabSlide({
    required this.tabIndex,
    required this.direction,
    required this.child,
  });

  final int tabIndex;
  final int direction;
  final Widget child;

  static const Curve _inCurve = Cubic(0.16, 1, 0.3, 1);
  static const Curve _outCurve = Cubic(0.7, 0, 0.84, 0);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      key: const ValueKey('ps5-library-tab-slide'),
      duration: const Duration(milliseconds: 460),
      switchInCurve: _inCurve,
      switchOutCurve: _outCurve,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        final currentKey = (child.key as ValueKey<int>?)?.value;
        final incoming = currentKey == tabIndex;
        final beginDx = incoming ? direction.toDouble() : -direction.toDouble();
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(beginDx, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
      child: KeyedSubtree(key: ValueKey(tabIndex), child: child),
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
      onFocusChange: (value) {
        if (value) Ps5UiSounds.tick();
        setState(() => _focused = value);
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
            Ps5UiSounds.confirm();
            widget.onPressed();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: () {
          Ps5UiSounds.confirm();
          widget.onPressed();
        },
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
  const _FilterButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<_FilterButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '排序与筛选',
      child: FocusableActionDetector(
        onFocusChange: (value) {
          if (value) Ps5UiSounds.tick();
          setState(() => _focused = value);
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              Ps5UiSounds.confirm();
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: () {
            Ps5UiSounds.confirm();
            widget.onPressed();
          },
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
    super.key,
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
        if (value) {
          Ps5UiSounds.tick();
          widget.onFocus();
        }
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
            Ps5UiSounds.confirm();
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
          onTap: () {
            Ps5UiSounds.confirm();
            widget.onOpen();
          },
          onSecondaryTap: () {
            Ps5UiSounds.confirm();
            widget.onMenu();
          },
          onLongPress: () {
            Ps5UiSounds.confirm();
            widget.onMenu();
          },
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
                              '已安装',
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
