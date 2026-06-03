import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'item.dart';

class RequestsView extends ConsumerStatefulWidget {
  const RequestsView({super.key});

  @override
  ConsumerState<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends ConsumerState<RequestsView>
    with WidgetsBindingObserver, RouteAware {
  final _requestsStateNotifier = ValueNotifier<TrackerInfosState>(
    const TrackerInfosState(),
  );
  List<TrackerInfo> _requests = [];
  late final ScrollController _scrollController;
  ModalRoute<dynamic>? _route;
  bool _isRouteCurrent = false;

  bool get _isCurrentPage => ref.read(
    isCurrentPageProvider(PageLabel.requests),
  );

  bool get _usesRouteVisibility => SheetProvider.of(context) != null;

  bool get _isVisiblePage =>
      _isCurrentPage || (_usesRouteVisibility && _isRouteCurrent);

  bool get _isUiActive =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool get _isViewActive => _isUiActive && _isVisiblePage;

  void _syncRequestsFromStore() {
    _requests = ref.read(requestsProvider).list;
    _requestsStateNotifier.value = _requestsStateNotifier.value.copyWith(
      trackerInfos: _requests,
    );
  }

  void _clearRenderedRequests() {
    _requests = [];
    _requestsStateNotifier.value = _requestsStateNotifier.value.copyWith(
      trackerInfos: [],
    );
  }

  void _handleVisibilityChanged() {
    if (_isViewActive) {
      _syncRequestsFromStore();
      return;
    }
    _clearRenderedRequests();
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

  void _onSearch(String value) {
    _requestsStateNotifier.value = _requestsStateNotifier.value.copyWith(
      query: value,
    );
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _requestsStateNotifier.value = _requestsStateNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController(initialScrollOffset: double.maxFinite);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleVisibilityChanged();
      }
    });
    ref.listenManual(requestsProvider.select((state) => VM(state.list)), (
      prev,
      next,
    ) {
      if (!_isViewActive) {
        return;
      }
      _requests = next.a;
      updateRequestsThrottler();
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
    if (state != AppLifecycleState.inactive) {
      _clearRenderedRequests();
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) {
      commonRouteObserver.unsubscribe(this);
    }
    _requestsStateNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void updateRequestsThrottler() {
    throttler.call(FunctionTag.requests, () {
      if (!mounted) {
        return;
      }
      final isEquality = trackerInfoListEquality.equals(
        _requests,
        _requestsStateNotifier.value.trackerInfos,
      );
      if (isEquality) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _requestsStateNotifier.value = _requestsStateNotifier.value.copyWith(
            trackerInfos: _requests,
          );
        }
      });
    }, duration: commonDuration);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: appLocalizations.requests,
      searchState: AppBarSearchState(onSearch: _onSearch),
      onKeywordsUpdate: _onKeywordsUpdate,
      floatingActionButton: ValueListenableBuilder(
        valueListenable: _requestsStateNotifier,
        builder: (_, state, _) {
          final autoScrollToEnd = state.autoScrollToEnd;
          return FadeRotationScaleBox(
            child: FloatingActionButton(
              key: ValueKey(autoScrollToEnd),
              onPressed: () {
                _requestsStateNotifier.value = _requestsStateNotifier.value
                    .copyWith(
                      autoScrollToEnd:
                          !_requestsStateNotifier.value.autoScrollToEnd,
                    );
              },
              child: autoScrollToEnd
                  ? const Icon(Icons.block)
                  : const Icon(Icons.vertical_align_top),
            ),
          );
        },
      ),
      body: ValueListenableBuilder<TrackerInfosState>(
        valueListenable: _requestsStateNotifier,
        builder: (context, state, _) {
          final requests = state.list;
          if (requests.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullTip(appLocalizations.requests),
            );
          }
          final items = requests
              .map<Widget>(
                (trackerInfo) => TrackerInfoItem(
                  key: Key(trackerInfo.id),
                  trackerInfo: trackerInfo,
                  onClickKeyword: (value) {
                    context.commonScaffoldState?.addKeyword(value);
                  },
                  detailTitle: appLocalizations.details(
                    appLocalizations.request,
                  ),
                ),
              )
              .separated(const Divider(height: 0))
              .toList();
          return Align(
            alignment: Alignment.topCenter,
            child: CommonScrollBar(
              trackVisibility: false,
              controller: _scrollController,
              child: ScrollToEndBox(
                controller: _scrollController,
                dataSource: requests,
                enable: state.autoScrollToEnd,
                onCancelToEnd: () {
                  _requestsStateNotifier.value = _requestsStateNotifier.value
                      .copyWith(autoScrollToEnd: false);
                },
                child: SuperListView.builder(
                  reverse: true,
                  shrinkWrap: true,
                  physics: const NextClampingScrollPhysics(),
                  controller: _scrollController,
                  itemBuilder: (_, index) {
                    return items[index];
                  },
                  itemCount: items.length,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
