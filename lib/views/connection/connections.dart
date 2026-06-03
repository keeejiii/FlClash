import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'item.dart';

class ConnectionsView extends ConsumerStatefulWidget {
  const ConnectionsView({super.key});

  @override
  ConsumerState<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends ConsumerState<ConnectionsView>
    with WidgetsBindingObserver, RouteAware {
  final _connectionsStateNotifier = ValueNotifier<TrackerInfosState>(
    const TrackerInfosState(),
  );
  final ScrollController _scrollController = ScrollController();
  ModalRoute<dynamic>? _route;
  bool _isRouteCurrent = false;
  bool _updateQueued = false;

  Timer? timer;

  bool get _isCurrentPage => ref.read(
    isCurrentPageProvider(PageLabel.connections),
  );

  bool get _usesRouteVisibility => SheetProvider.of(context) != null;

  bool get _isVisiblePage =>
      _isCurrentPage || (_usesRouteVisibility && _isRouteCurrent);

  bool get _isUiActive =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool get _isViewActive => _isUiActive && _isVisiblePage;

  void _clearRenderedConnections() {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      trackerInfos: [],
    );
  }

  void _handleVisibilityChanged() {
    if (_isViewActive) {
      _updateConnectionsTask();
      return;
    }
    _cancelUpdateTimer();
    _clearRenderedConnections();
  }

  void _setRouteCurrent(bool value) {
    if (_isRouteCurrent == value) {
      return;
    }
    _isRouteCurrent = value;
    _handleVisibilityChanged();
  }

  void _subscribeRouteObserver() {
    final route = ModalRoute.of(context);
    if (_route == route) {
      return;
    }
    if (_route != null) {
      commonRouteObserver.unsubscribe(this);
    }
    _route = route;
    if (route != null) {
      commonRouteObserver.subscribe(this, route);
      _isRouteCurrent = route.isCurrent;
    } else {
      _isRouteCurrent = false;
    }
  }

  List<Widget> _buildActions() {
    return [
      IconButton(
        onPressed: () async {
          coreController.closeConnections();
          await _updateConnections();
        },
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ];
  }

  void _onSearch(String value) {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      query: value,
    );
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  void _cancelUpdateTimer() {
    timer?.cancel();
    timer = null;
    _updateQueued = false;
  }

  Future<void> _updateConnectionsTask() async {
    if (!_isViewActive) {
      _cancelUpdateTimer();
      return;
    }
    if (_updateQueued) {
      return;
    }
    _updateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_isViewActive) {
        _cancelUpdateTimer();
        return;
      }
      await _updateConnections();
      if (!mounted || !_isViewActive) {
        _cancelUpdateTimer();
        return;
      }
      _updateQueued = false;
      timer?.cancel();
      timer = Timer(const Duration(seconds: 1), () {
        _updateQueued = false;
        _updateConnectionsTask();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleVisibilityChanged();
      }
    });
    ref.listenManual(currentPageLabelProvider, (prev, next) {
      _handleVisibilityChanged();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isVisiblePage) {
      _handleVisibilityChanged();
      return;
    }
    _cancelUpdateTimer();
    if (state != AppLifecycleState.inactive) {
      _clearRenderedConnections();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeRouteObserver();
  }

  @override
  void didPush() {
    _setRouteCurrent(true);
  }

  @override
  void didPopNext() {
    _setRouteCurrent(true);
  }

  @override
  void didPushNext() {
    _setRouteCurrent(false);
  }

  @override
  void didPop() {
    _setRouteCurrent(false);
  }

  Future<void> _updateConnections() async {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      trackerInfos: await coreController.getConnections(),
    );
  }

  Future<void> _handleBlockConnection(String id) async {
    await coreController.closeConnection(id);
    await _updateConnections();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) {
      commonRouteObserver.unsubscribe(this);
    }
    _cancelUpdateTimer();
    _connectionsStateNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: appLocalizations.connections,
      onKeywordsUpdate: _onKeywordsUpdate,
      searchState: AppBarSearchState(onSearch: _onSearch),
      actions: _buildActions(),
      body: ValueListenableBuilder<TrackerInfosState>(
        valueListenable: _connectionsStateNotifier,
        builder: (context, state, _) {
          final connections = state.list;
          if (connections.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullTip(appLocalizations.connections),
              illustration: const ConnectionEmptyIllustration(),
            );
          }
          final items = connections
              .map<Widget>(
                (trackerInfo) => TrackerInfoItem(
                  key: Key(trackerInfo.id),
                  trackerInfo: trackerInfo,
                  onClickKeyword: (value) {
                    context.commonScaffoldState?.addKeyword(value);
                  },
                  trailing: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(minimumSize: Size.zero),
                    icon: const Icon(Icons.block),
                    onPressed: () {
                      _handleBlockConnection(trackerInfo.id);
                    },
                  ),
                  detailTitle: appLocalizations.details(
                    appLocalizations.connection,
                  ),
                ),
              )
              .separated(const Divider(height: 0))
              .toList();
          return SuperListView.builder(
            controller: _scrollController,
            itemBuilder: (context, index) {
              return items[index];
            },
            itemCount: connections.length,
          );
        },
      ),
    );
  }
}
