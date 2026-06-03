import 'dart:async';

import 'package:fl_clash/common/system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class ForegroundUiController extends ValueNotifier<bool>
    with WidgetsBindingObserver {
  static const inactiveBackgroundDelay = Duration(seconds: 1);

  static ForegroundUiController? _instance;

  Timer? _inactiveTimer;
  AppLifecycleState? _lifecycleState;

  factory ForegroundUiController() {
    return _instance ??= ForegroundUiController._();
  }

  ForegroundUiController._()
      : _lifecycleState = WidgetsBinding.instance.lifecycleState,
        super(_getInitialForegroundState(WidgetsBinding.instance.lifecycleState)) {
    WidgetsBinding.instance.addObserver(this);
    if (_lifecycleState == AppLifecycleState.inactive) {
      _scheduleInactiveBackgroundTransition();
    }
  }

  static ForegroundUiController get instance =>
      _instance ??= ForegroundUiController._();

  AppLifecycleState? get lifecycleState => _lifecycleState;

  bool get isForegroundUiActive => value;

  static bool _getInitialForegroundState(AppLifecycleState? state) {
    if (!system.isAndroid) {
      return true;
    }
    return switch (state) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => false,
      AppLifecycleState.inactive ||
      AppLifecycleState.resumed ||
      null => true,
    };
  }

  void _cancelInactiveTimer() {
    _inactiveTimer?.cancel();
    _inactiveTimer = null;
  }

  void _scheduleInactiveBackgroundTransition() {
    _cancelInactiveTimer();
    if (!system.isAndroid ||
        _lifecycleState != AppLifecycleState.inactive ||
        !value) {
      return;
    }
    _inactiveTimer = Timer(inactiveBackgroundDelay, () {
      if (_lifecycleState == AppLifecycleState.inactive) {
        value = false;
      }
    });
  }

  void _setForegroundUiActive(bool nextValue) {
    if (value != nextValue) {
      value = nextValue;
      if (!nextValue) {
        _cleanupBackgroundResources();
      }
    }
  }

  void _cleanupBackgroundResources() {
    imageCache.clearLiveImages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (!system.isAndroid) {
      _setForegroundUiActive(true);
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        _cancelInactiveTimer();
        _setForegroundUiActive(true);
        break;
      case AppLifecycleState.inactive:
        _scheduleInactiveBackgroundTransition();
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _cancelInactiveTimer();
        _setForegroundUiActive(false);
        break;
    }
  }
}

ForegroundUiController get foregroundUiController =>
    ForegroundUiController.instance;

