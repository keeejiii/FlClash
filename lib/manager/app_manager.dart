import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/window_manager.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class AppStateManager extends ConsumerStatefulWidget {
  final Widget child;

  const AppStateManager({super.key, required this.child});

  @override
  ConsumerState<AppStateManager> createState() => _AppStateManagerState();
}

class _AppStateManagerState extends ConsumerState<AppStateManager>
    with WidgetsBindingObserver {
  bool _needsAndroidForegroundRecovery = false;

  bool get _isUiActive =>
      foregroundUiController.isForegroundUiActive;

  void _clearAndroidBackgroundUiState(ProviderContainer container) {
    debouncer.cancel(FunctionTag.updateGroups);
    container.read(requestsProvider.notifier).clear();
    container.read(delayDataSourceProvider.notifier).value = {};
    container.read(groupsProvider.notifier).value = [];
    container.read(providersProvider.notifier).value = [];
    container.read(packagesProvider.notifier).value = [];
    container.read(localIpProvider.notifier).value = null;
    container.read(networkDetectionProvider.notifier).clear();
  }

  void _handleForegroundUiStateChanged() {
    if (!mounted ||
        !system.isAndroid ||
        foregroundUiController.isForegroundUiActive ||
        foregroundUiController.lifecycleState != AppLifecycleState.inactive) {
      return;
    }
    _needsAndroidForegroundRecovery = true;
    final container = globalState.container;
    container.read(setupActionProvider.notifier).pauseForegroundUpdates();
    _clearAndroidBackgroundUiState(container);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foregroundUiController.addListener(_handleForegroundUiStateChanged);
    ref.listenManual(checkIpProvider, (prev, next) {
      if (prev != next && next.a && next.c && _isUiActive) {
        ref.read(networkDetectionProvider.notifier).startCheck();
      }
    });
    ref.listenManual(configProvider, (prev, next) {
      if (prev != next) {
        globalState.container
            .read(storeActionProvider.notifier)
            .savePreferencesDebounce();
      }
    });
    ref.listenManual(needUpdateGroupsProvider, (prev, next) {
      if (prev != next) {
        globalState.container
            .read(proxiesActionProvider.notifier)
            .updateGroupsDebounce();
      }
    });
    ref.listenManual(suspendProvider, (prev, next) {
      final isStart = ref.read(isStartProvider);
      if (prev != next && isStart) {
        debouncer.call(FunctionTag.suspend, () async {
          if (next == true) {
            await coreController.stopListener();
          } else {
            await coreController.startListener();
          }
          ref.read(checkIpNumProvider.notifier).add();
        });
      }
    });
    if (system.isMacOS) {
      ref.listenManual(autoSetSystemDnsStateProvider, (prev, next) async {
        if (prev == next) {
          return;
        }
        if (next.a == true && next.b == true) {
          macOS?.updateDns(false);
        } else {
          macOS?.updateDns(true);
        }
      });
    }
  }

  @override
  void dispose() {
    foregroundUiController.removeListener(_handleForegroundUiStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    commonPrint.log('$state');
    final container = globalState.container;
    final setupAction = container.read(setupActionProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      final shouldRecoverAndroidUi = _needsAndroidForegroundRecovery;
      _needsAndroidForegroundRecovery = false;
      setupAction.resumeForegroundUpdates();
      permissions.check();
      render?.resume();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        container.read(systemActionProvider.notifier).updateLocalIp();
        container.read(checkIpNumProvider.notifier).add();
        container.read(setupActionProvider.notifier).tryCheckIp();
        if (system.isAndroid && shouldRecoverAndroidUi) {
          try {
            await container.read(coreActionProvider.notifier).tryStartCore();
          } catch (e) {
            commonPrint.log('resume core check error: $e');
          }
          try {
            await container.read(providersProvider.notifier).syncProviders();
          } catch (e) {
            commonPrint.log('resume providers sync error: $e');
          }
          container
              .read(proxiesActionProvider.notifier)
              .updateGroupsDebounce(Duration.zero);
        }
      });
      return;
    }

    switch (state) {
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        setupAction.pauseForegroundUpdates();
        if (system.isAndroid) {
          _needsAndroidForegroundRecovery = true;
          _clearAndroidBackgroundUiState(container);
        }
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  void didChangePlatformBrightness() {
    globalState.container.read(themeActionProvider.notifier).updateBrightness();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: (_) {
        render?.resume();
      },
      child: widget.child,
    );
  }
}

class AppEnvManager extends StatelessWidget {
  final Widget child;

  const AppEnvManager({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      if (globalState.isPre) {
        return Banner(
          message: 'DEBUG',
          location: BannerLocation.topEnd,
          child: child,
        );
      }
    }
    if (globalState.isPre) {
      return Banner(
        message: 'PRE',
        location: BannerLocation.topEnd,
        child: child,
      );
    }
    return child;
  }
}

class AppSidebarContainer extends ConsumerWidget {
  final Widget child;

  const AppSidebarContainer({super.key, required this.child});

  // Widget _buildLoading() {
  //   return Consumer(
  //     builder: (_, ref, _) {
  //       final loading = ref.watch(loadingProvider);
  //       final isMobileView = ref.watch(isMobileViewProvider);
  //       return loading && !isMobileView
  //           ? RotatedBox(
  //               quarterTurns: 1,
  //               child: const LinearProgressIndicator(),
  //             )
  //           : Container();
  //     },
  //   );
  // }

  Widget _buildBackground({
    required BuildContext context,
    required Widget child,
  }) {
    return Material(color: context.colorScheme.surfaceContainer, child: child);
    // if (!system.isMacOS) {
    //   return Material(
    //     color: context.colorScheme.surfaceContainer,
    //     child: child,
    //   );
    // }
    // return child;
    // return TransparentMacOSSidebar(
    //   child: Material(color: Colors.transparent, child: child),
    // );
  }

  void _updateSideBarWidth(WidgetRef ref, double contentWidth) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sideWidthProvider.notifier).value =
          ref.read(viewSizeProvider.select((state) => state.width)) -
          contentWidth;
    });
  }

  void _handleToPage(PageLabel pageLabel) {
    globalState.container
        .read(currentPageLabelProvider.notifier)
        .toPage(pageLabel);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationState = ref.watch(navigationStateProvider);
    final navigationItems = navigationState.navigationItems;
    final isMobileView = navigationState.viewMode == ViewMode.mobile;
    if (isMobileView) {
      return child;
    }
    final currentIndex = navigationState.currentIndex;
    final showLabel = ref.watch(appSettingProvider).showLabel;
    return Row(
      children: [
        _buildBackground(
          context: context,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (system.isMacOS) const SizedBox(height: 22),
                const SizedBox(height: 10),
                if (!system.isMacOS) ...[
                  const ClipRect(child: AppIcon()),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: ScrollConfiguration(
                    behavior: HiddenBarScrollBehavior(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: NavigationRail(
                            scrollable: true,
                            minExtendedWidth: 200,
                            backgroundColor: Colors.transparent,
                            selectedLabelTextStyle: context
                                .textTheme
                                .labelLarge!
                                .copyWith(color: context.colorScheme.onSurface),
                            unselectedLabelTextStyle: context
                                .textTheme
                                .labelLarge!
                                .copyWith(color: context.colorScheme.onSurface),
                            destinations: navigationItems
                                .map(
                                  (e) => NavigationRailDestination(
                                    icon: e.icon,
                                    label: Text(Intl.message(e.label.name)),
                                  ),
                                )
                                .toList(),
                            onDestinationSelected: (index) {
                              _handleToPage(navigationItems[index].label);
                            },
                            extended: false,
                            selectedIndex: currentIndex,
                            labelType: showLabel
                                ? NavigationRailLabelType.all
                                : NavigationRailLabelType.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                IconButton(
                  onPressed: () {
                    ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) =>
                              state.copyWith(showLabel: !state.showLabel),
                        );
                  },
                  icon: Icon(
                    Icons.menu,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: ClipRect(
            child: LayoutBuilder(
              builder: (_, constraints) {
                _updateSideBarWidth(ref, constraints.maxWidth);
                return child;
              },
            ),
          ),
        ),
      ],
    );
  }
}
