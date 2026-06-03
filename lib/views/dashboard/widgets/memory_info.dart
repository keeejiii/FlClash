import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _memoryStateNotifier = ValueNotifier<num>(0);

class MemoryInfo extends ConsumerStatefulWidget {
  const MemoryInfo({super.key});

  @override
  ConsumerState<MemoryInfo> createState() => _MemoryInfoState();
}

class _MemoryInfoState extends ConsumerState<MemoryInfo> {
  Timer? _timer;

  bool get _isViewActive => ref.read(
    isForegroundPageActiveProvider(PageLabel.dashboard),
  );

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      isForegroundPageActiveProvider(PageLabel.dashboard),
      (prev, next) {
        if (next) {
          _updateMemory();
        } else {
          _cancelUpdateTimer();
        }
      },
    );
    if (_isViewActive) {
      _updateMemory();
    }
  }

  @override
  void dispose() {
    _cancelUpdateTimer();
    super.dispose();
  }

  void _cancelUpdateTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _updateMemory() async {
    _cancelUpdateTimer();
    if (!_isViewActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_isViewActive) return;
      final rss = ProcessInfo.currentRss;
      final memory = coreController.isCompleted
          ? await coreController.getMemory() + rss
          : rss;
      if (!mounted || !_isViewActive) return;
      _memoryStateNotifier.value = memory;
      _timer = Timer(const Duration(seconds: 2), () async {
        _updateMemory();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return SizedBox(
      height: getWidgetHeight(1),
      child: RepaintBoundary(
        child: CommonCard(
          info: Info(
            iconData: Icons.memory,
            label: appLocalizations.memoryInfo,
          ),
          onPressed: () {
            coreController.requestGc();
          },
          child: Container(
            padding: baseInfoEdgeInsets.copyWith(top: 0),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: globalState.measure.bodyMediumHeight + 2,
                  child: ValueListenableBuilder(
                    valueListenable: _memoryStateNotifier,
                    builder: (_, memory, _) {
                      final traffic = memory.traffic;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            traffic.value,
                            style: context.textTheme.bodyMedium?.toLight
                                .adjustSize(1),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            traffic.unit,
                            style: context.textTheme.bodyMedium?.toLight
                                .adjustSize(1),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
