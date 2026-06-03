import 'dart:async';

import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/material.dart';

typedef TickWidgetBuilder = Widget Function(BuildContext context, int tick);

class TickBuilder extends StatefulWidget {
  final Duration duration;
  final TickWidgetBuilder builder;

  const TickBuilder({super.key, required this.duration, required this.builder})
    : assert(duration > Duration.zero);

  @override
  State<TickBuilder> createState() => _TickBuilderState();
}

class _TickBuilderState extends State<TickBuilder> with WidgetsBindingObserver {
  Timer? _timer;
  int _tick = 0;

  bool get _isUiActive {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    return lifecycleState == null ||
        lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant TickBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {
          _tick++;
        });
      }
      _startTimer();
      return;
    }
    _cancelTimer();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _startTimer() {
    _cancelTimer();
    if (!_isUiActive) return;
    _timer = Timer.periodic(widget.duration, (_) {
      if (!mounted) return;
      if (!_isUiActive) {
        _cancelTimer();
        return;
      }
      setState(() {
        _tick++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _tick);
  }
}

class ScrollOverBuilder extends StatefulWidget {
  final Widget Function(bool isOver) builder;

  const ScrollOverBuilder({super.key, required this.builder});

  @override
  State<ScrollOverBuilder> createState() => _ScrollOverBuilderState();
}

class _ScrollOverBuilderState extends State<ScrollOverBuilder> {
  final isOverNotifier = ValueNotifier<bool>(false);

  @override
  void dispose() {
    isOverNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (scrollNotification) {
        isOverNotifier.value = scrollNotification.metrics.maxScrollExtent > 0;
        return true;
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: isOverNotifier,
        builder: (_, isOver, _) {
          return widget.builder(isOver);
        },
      ),
    );
  }
}

class FloatingActionButtonExtendedBuilder extends StatelessWidget {
  final Widget Function(bool isExtend) builder;

  const FloatingActionButtonExtendedBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final isExtended =
        CommonScaffoldFabExtendedProvider.of(context)?.isExtended ?? true;
    return builder(isExtended);
  }
}

typedef StateWidgetBuilder<T> = Widget Function(T state);

typedef StateAndChildWidgetBuilder<T> = Widget Function(T state, Widget? child);
