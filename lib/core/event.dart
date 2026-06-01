import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

abstract mixin class CoreEventListener {
  void onLog(Log log) {}

  void onDelay(Delay delay) {}

  void onRequest(TrackerInfo connection) {}

  void onLoaded(String providerName) {}

  void onCrash(String message) {}
}

class CoreEventManager {
  final _controller = StreamController<CoreEvent>();

  bool _shouldSkipEventInBackground(CoreEventType type) {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState == null ||
        lifecycleState == AppLifecycleState.resumed) {
      return false;
    }
    return switch (type) {
      CoreEventType.delay || CoreEventType.request || CoreEventType.loaded =>
        true,
      CoreEventType.log || CoreEventType.crash => false,
    };
  }

  CoreEventManager._() {
    _controller.stream.listen((event) {
      if (_shouldSkipEventInBackground(event.type)) {
        return;
      }
      for (final CoreEventListener listener in _listeners) {
        switch (event.type) {
          case CoreEventType.log:
            listener.onLog(Log.fromJson(event.data));
            break;
          case CoreEventType.delay:
            listener.onDelay(Delay.fromJson(event.data));
            break;
          case CoreEventType.request:
            listener.onRequest(TrackerInfo.fromJson(event.data));
            break;
          case CoreEventType.loaded:
            listener.onLoaded(event.data);
            break;
          case CoreEventType.crash:
            listener.onCrash(event.data);
            break;
        }
      }
    });
  }

  static final CoreEventManager instance = CoreEventManager._();

  final ObserverList<CoreEventListener> _listeners =
      ObserverList<CoreEventListener>();

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  void sendEvent(CoreEvent event) {
    _controller.add(event);
  }

  void addListener(CoreEventListener listener) {
    _listeners.add(listener);
  }

  void removeListener(CoreEventListener listener) {
    _listeners.remove(listener);
  }
}

final coreEventManager = CoreEventManager.instance;
