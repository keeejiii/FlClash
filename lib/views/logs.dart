import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class LogsView extends ConsumerStatefulWidget {
  const LogsView({super.key});

  @override
  ConsumerState<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends ConsumerState<LogsView>
    with WidgetsBindingObserver, RouteAware {
  final _logsStateNotifier = ValueNotifier<LogsState>(const LogsState());
  late ScrollController _scrollController;
  ModalRoute<dynamic>? _route;
  bool _isRouteCurrent = false;

  List<Log> _logs = [];

  bool get _isCurrentPage => ref.read(isCurrentPageProvider(PageLabel.logs));

  bool get _usesRouteVisibility => SheetProvider.of(context) != null;

  bool get _isVisiblePage => _isCurrentPage || (_usesRouteVisibility && _isRouteCurrent);

  bool get _isUiActive =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool get _isViewActive => _isUiActive && _isVisiblePage;

  void _syncLogsFromStore() {
    _logs = ref.read(logsProvider).list;
    _logsStateNotifier.value = _logsStateNotifier.value.copyWith(logs: _logs);
  }

  void _clearRenderedLogs() {
    _logs = [];
    _logsStateNotifier.value = _logsStateNotifier.value.copyWith(logs: []);
  }

  void _handleVisibilityChanged() {
    if (_isViewActive) {
      _syncLogsFromStore();
      return;
    }
    _clearRenderedLogs();
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
    ref.listenManual(logsProvider.select((state) => VM(state.list)), (
      prev,
      next,
    ) {
      if (prev != next) {
        final isEquality = logListEquality.equals(prev?.a, next.a);
        if (!isEquality) {
          if (!_isViewActive) {
            return;
          }
          _logs = next.a;
          updateLogsThrottler();
        }
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
    if (state != AppLifecycleState.inactive) {
      _clearRenderedLogs();
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

  List<Widget> _buildActions() {
    return [
      IconButton(
        onPressed: () {
          _handleExport();
        },
        icon: const Icon(Icons.save_as_outlined),
      ),
    ];
  }

  void _onSearch(String value) {
    _logsStateNotifier.value = _logsStateNotifier.value.copyWith(query: value);
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) {
      commonRouteObserver.unsubscribe(this);
    }
    _logsStateNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    final appLocalizations = context.appLocalizations;
    final res = await globalState.safeRun<bool>(() async {
      return globalState.container
          .read(logsProvider.notifier)
          .exportLogs();
    }, title: appLocalizations.exportLogs);
    if (res != true) return;
    globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.exportSuccess),
    );
  }

  void updateLogsThrottler() {
    throttler.call(FunctionTag.logs, () {
      if (!mounted) {
        return;
      }
      final isEquality = logListEquality.equals(
        _logs,
        _logsStateNotifier.value.logs,
      );
      if (isEquality) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
            logs: _logs,
          );
        }
      });
    }, duration: commonDuration);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      actions: _buildActions(),
      onKeywordsUpdate: _onKeywordsUpdate,
      searchState: AppBarSearchState(onSearch: _onSearch),
      title: appLocalizations.logs,
      floatingActionButton: ValueListenableBuilder(
        valueListenable: _logsStateNotifier,
        builder: (_, state, _) {
          final autoScrollToEnd = state.autoScrollToEnd;
          return FadeRotationScaleBox(
            child: FloatingActionButton(
              key: ValueKey(autoScrollToEnd),
              onPressed: () {
                _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
                  autoScrollToEnd: !_logsStateNotifier.value.autoScrollToEnd,
                );
              },
              child: autoScrollToEnd
                  ? const Icon(Icons.block)
                  : const Icon(Icons.vertical_align_top),
            ),
          );
        },
      ),
      body: ValueListenableBuilder<LogsState>(
        valueListenable: _logsStateNotifier,
        builder: (context, state, _) {
          final logs = state.list;
          if (logs.isEmpty) {
            return NullStatus(
              illustration: const LogEmptyIllustration(),
              label: appLocalizations.nullTip(appLocalizations.logs),
            );
          }
          final items = logs
              .map<Widget>(
                (log) => LogItem(
                  key: Key(log.dateTime),
                  log: log,
                  onClick: (value) {
                    context.commonScaffoldState?.addKeyword(value);
                  },
                ),
              )
              .separated(const Divider(height: 0))
              .toList();
          return Align(
            alignment: Alignment.topCenter,
            child: ScrollToEndBox(
              onCancelToEnd: () {
                _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
                  autoScrollToEnd: false,
                );
              },
              controller: _scrollController,
              enable: state.autoScrollToEnd,
              dataSource: logs,
              child: CommonScrollBar(
                controller: _scrollController,
                child: SuperListView.builder(
                  physics: const NextClampingScrollPhysics(),
                  reverse: true,
                  shrinkWrap: true,
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

class LogItem extends StatelessWidget {
  final Log log;
  final Function(String)? onClick;

  const LogItem({super.key, required this.log, this.onClick});

  @override
  Widget build(BuildContext context) {
    return ListItem(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () {},
      title: SelectableText(
        log.payload,
        style: context.textTheme.bodyLarge?.copyWith(
          color: log.logLevel.color(context),
        ),
      ),
      subtitle: Column(
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CommonChip(
                onPressed: () {
                  if (onClick == null) return;
                  onClick!(log.logLevel.name);
                },
                label: log.logLevel.name,
              ),
              Text(
                log.dateTime,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.opacity80,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
