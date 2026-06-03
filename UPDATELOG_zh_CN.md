# FlClash Fork Update Log（中文）

> 仓库：`keeejiii/FlClash`
>
> 主题：Android 省电与后台行为收紧
>
> 目标：在 **尽量不扩大与上游冲突面** 的前提下，降低 Android 后台活跃度、减少发热与耗电，并尽量保持后台代理留存稳定。

---

## 一、背景与设计原则

这轮修改不是照搬 BettBox 的完整 Android 运行时架构，而是基于 FlClash 现有结构，做一套 **低侵入、低冲突、可回退** 的后台减活跃方案。

核心原则：

1. **不主动停 VPN / 不主动停前台 service**
2. **优先削减后台无意义刷新、轮询、事件消费**
3. **优先在 Dart 层和轻量 Android 模块层改动**
4. **避免直接引入 BettBox 的 smartStop / smartResume / native 状态机**
5. **尽量把改动收拢在少量文件，方便后续同步 upstream**

---

## 二、阶段总览

本轮改动分成五个阶段：

### 阶段 1：后台统计与通知收紧
- 后台不再每秒刷新 traffic / totalTraffic，改为低频补采样
- 去掉通知栏实时 speed
- 移除 speed 通知更新链路
- 补 Doze 状态监听

### 阶段 2（3A）：后台真正停 foreground timer
- 切后台时直接取消每秒 periodic timer
- 回前台时恢复 timer，并立即补一次状态

### 阶段 3（3B-1）：网络变化后轻量清理旧连接
- 仅在 Android 主网络类型变化时触发
- debounce 800ms 后执行一次 `closeConnections()`

### 阶段 4（3C-lite）：后台丢弃高频 UI 事件
- 后台不再分发 `delay` / `request` 这类高频 UI 事件
- 保留 `log` / `crash`，后台跳过 `loaded`
- 日志 / 请求 / 连接 / network detection 这类重 UI 页面，只在当前页实际可见时继续刷新显示层

### 阶段 5（4）：扩展页面可见性控制
- 代理页面 (ProxiesView) 纳入"当前页可见才工作"规则
- 配置文件页面 (ProfilesView) 优化加载状态控制
- LastUpdateTimeText 组件独立管理生命周期
- NetworkSpeed/TrafficUsage 组件绑定生命周期观察

---

## 三、详细修改过程

---

## 阶段 1：后台统计与通知收紧

### 1.1 目标

原始问题：

- Android 后台仍然持续进行流量统计刷新
- 通知栏实时 speed 会带来额外更新成本
- Service 侧也存在与通知相关的活跃逻辑
- 息屏 / Doze 场景处理不够完整

目标：

- 减少后台无意义流量统计刷新
- 取消 speed 通知链路
- 保持前台 service 存在，但降低通知动态活跃度
- 补齐 Doze 监听，使挂起判断更完整

### 1.2 涉及文件

#### Flutter / Dart
- `lib/providers/action.dart`

#### Android / Kotlin
- `android/service/src/main/java/com/follow/clash/service/modules/NotificationModule.kt`
- `android/service/src/main/java/com/follow/clash/service/modules/SuspendModule.kt`

### 1.3 实际做法

#### A. 后台不再每秒刷新 traffic
在 `lib/providers/action.dart` 中：

- 为 Android 增加前后台判断
- 非前台时停止每秒 foreground timer
- 改为保留一个 30 秒一次的后台 `updateTraffic(force: true)` 低频补采样

效果：
- 后台时不再每秒去拉 `traffic / totalTraffic`
- 仍保留低频后台流量采样，避免回前台后流量统计断层
- 但不影响代理本身运行

#### B. 去掉 speed 通知栏
- 删除 Flutter -> MethodChannel -> Kotlin 的 speed 通知推送接口
- `NotificationParams` 去掉 `contentText`
- `NotificationModule` 回退成静态前台通知

#### C. 补 Doze 监听
在 `SuspendModule.kt` 中增加 `PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED`

---

## 阶段 2（3A）：后台真正停 foreground timer

### 2.1 目标

阶段 1 完成后，后台虽然已经不再每秒更新 traffic，但 periodic timer 仍然存在。

目标：
- 后台时真正取消 foreground timer
- 回前台时再恢复 timer

### 2.2 涉及文件

- `lib/providers/action.dart`
- `lib/manager/app_manager.dart`

### 2.3 实际做法

#### A. 在 `SetupAction` 增加 timer 生命周期管理
新增：
- `_startUpdateTimer()`
- `pauseForegroundUpdates()`
- `resumeForegroundUpdates()`

#### B. 在 `AppStateManager` 里接 lifecycle
在 `didChangeAppLifecycleState()` 中：
- `resumed`：`resumeForegroundUpdates()`
- `inactive / hidden / paused / detached`：`pauseForegroundUpdates()`

---

## 阶段 3（3B-1）：网络变化后轻量清理旧连接

### 3.1 目标

FlClash 在网络切换时，可能出现旧连接拖尾、切网后恢复慢等问题。

目标：
- 不引入 smartStop / smartResume
- 不引入 Android native 复杂状态机
- 只在 Dart 层做一个轻量网络变化响应

### 3.2 涉及文件

- `lib/application.dart`

### 3.3 实际做法

复用现有 `ConnectivityManager(onConnectivityChanged: ...)`：

#### A. 增加主网络类型判断
新增：
- `_lastPrimaryConnectivity`
- `_getPrimaryConnectivity(List<ConnectivityResult>)`

主网络类型优先级：wifi > mobile > ethernet > bluetooth > other > vpn > none

#### B. 增加 debounce
新增 `_networkChangeDebounceTimer`，debounce 800ms 后执行动作

#### C. 轻量动作：`closeConnections()`
触发条件：
- Android 平台
- 主网络类型真的变化
- 当前已启动
- 当前不在 suspend 状态

动作：`await coreController.closeConnections()`

---

## 阶段 4（3C-lite）：后台丢弃高频 UI 事件

### 4.1 为什么不是直接做"后台停 listener"

在 FlClash 当前架构里，`startListener()` / `stopListener()` 最终和 Android service 生命周期绑定。直接停 listener 很可能不只是停 UI 事件，而是把 service / 代理运行链路一起动到。

### 4.2 目标

不动 listener/service 生命周期，只做：
- 后台时跳过只服务 UI 的高频事件消费

### 4.3 涉及文件

- `lib/core/event.dart`

### 4.4 实际做法

在 `CoreEventManager` 里增加事件前置过滤：

#### 前台（`AppLifecycleState.resumed`）
- UI 保持完整工作
- `delay` / `request` / `traffic` 等 UI 相关逻辑正常运行

#### 后台（非 `resumed`）
丢弃：
- `CoreEventType.delay`
- `CoreEventType.request`

保留：
- `CoreEventType.log`
- `CoreEventType.crash`

页面级 UI 刷新：
- `ConnectionsView` 的 1 秒轮询，不在当前页或后台时直接停止
- `RequestsView` 的显示刷新层，不在当前页或后台时不再推动 `_requestsStateNotifier`
- `LogsView` 的显示刷新层，不在当前页或后台时不再推动 `_logsStateNotifier`，但日志采集保留
- `networkDetection` 的触发条件收紧为"仪表盘当前可见"

---

## 阶段 5（4）：扩展页面可见性控制

### 5.1 目标

将"当前页可见才工作"规则扩展到更多页面，进一步减少后台/非当前页的无意义工作。

### 5.2 涉及文件

#### 代理页面
- `lib/views/proxies/proxies.dart`
  - 添加 `WidgetsBindingObserver`
  - `_isViewActive` 判断当前是否在 proxies 页面且处于 resumed 状态
  - `loadingProvider` 只在当前页可见时监听
  - 后台/切页时自动关闭搜索状态

#### 配置文件页面
- `lib/views/profiles/profiles.dart`
  - 添加 `WidgetsBindingObserver`
  - `_isViewActive` 判断
  - `loadingProvider` 只在当前页可见时监听
  - `LastUpdateTimeText` 改为 StatefulWidget，独立管理 timer 生命周期
  - Timer 在后台时取消，前台时恢复

#### 仪表盘组件
- `lib/views/dashboard/widgets/network_speed.dart`
  - 添加 `WidgetsBindingObserver`
  - 生命周期变化时无需特殊处理（依赖 `trafficsProvider` 的 timer 控制）

- `lib/views/dashboard/widgets/traffic_usage.dart`
  - 已经是 StatelessWidget，依赖 `totalTrafficProvider`
  - 数据更新由 `SetupAction` 的 timer 生命周期管理

### 5.3 收益

- 代理页面、配置文件页面在后台或非当前页时减少 provider 监听开销
- `LastUpdateTimeText` 的定时器在后台时不再运行，减少不必要的 UI 刷新
- 页面行为更加一致：都遵循"当前页完整、不可见页静默、后台静默"原则

### 5.4 风险与取舍

- `LastUpdateTimeText` 的"X分钟前更新"显示在后台时不会自动刷新
- 回前台时会立即刷新，显示正确时间
- 这是主动取舍，换取更干净的后台行为

---

## 四、最终效果总结

到当前版本为止，这个 fork 已经形成了一套 **Android 后台减活跃方案**：

1. **后台不再每秒刷新 traffic，而是保留低频补采样**
2. **后台真正停 foreground timer**
3. **切网后主动清理旧连接**
4. **后台不再消费高频 UI 事件**
5. **连接页 / 请求页 / 日志页只在当前页可见时刷新显示层**
6. **network detection 只在仪表盘当前可见时触发**
7. **代理页面、配置文件页面纳入可见性控制**
8. **通知栏回退静态前台 service 形态**
9. **日志在前后台都完整保留**
10. **Doze 监听补齐**

这套方案的特点不是"激进智能保活"或"智能暂停代理"，而是：

> **当前页 UI 完整、不可见页静默、后台 UI 静默，同时尽量不伤害 VPN / service 主链路。**

---

## 五、对后台留存与前台行为的判断

这轮修改的目标不是"用更复杂的保活手段提升留存"，而是"降低后台噪音，避免系统把它判成高活跃后台"，同时保持：

- **前台：UI 完整工作**
- **后台：UI 静默**
- **日志：全保留**

这里需要特别说明一点：

> **当前这个 fork 在前台的 UI 运行逻辑，已经基本回到接近上游的完整状态；与上游的主要差异，集中在后台 UI 静默策略，以及少量 Android 辅助行为（静态通知、切网清旧连接、Doze 监听）。**

因此：

### 对 App / 进程留存
- 理论上更有利
- 因为少了 timer、少了通知动态刷新、少了高频事件消费

### 对 VPN / service 留存
- 理论上应持平或略好
- 因为没有主动停 service，没有动 smart stop，没有改前台 service 主链路

### 不能解决的问题
- 厂商极端后台杀进程策略
- 未加入电池优化白名单带来的系统限制

---

## 六、与上游同步的冲突面评估

### 冲突面低的改动
- `lib/application.dart`
- `lib/providers/action.dart`
- `lib/manager/app_manager.dart`
- `lib/core/event.dart`
- `lib/views/proxies/proxies.dart`
- `lib/views/profiles/profiles.dart`
- `lib/views/dashboard/widgets/network_speed.dart`

这些主要是 Dart 层行为收紧，和 upstream 的核心 Android 原生链路耦合较低。

### 冲突面中等的改动
- `android/service/src/main/java/com/follow/clash/service/modules/NotificationModule.kt`
- `android/service/src/main/java/com/follow/clash/service/modules/SuspendModule.kt`

这类文件属于 Android 运行态辅助模块，后续 upstream 如果也改通知或挂起逻辑，可能会产生局部冲突，但范围仍可控。

### 当前避免掉的高冲突区
本轮没有引入：
- smartStop / smartResume
- Android native `ConnectivityManager.NetworkCallback` 主状态机
- service / vpn 生命周期重构
- core 主行为改写

这是刻意的取舍，目的是控制 fork 深度。

---

## 七、后续建议

如果后续继续优化，建议顺序：

1. **先观察实际体感与后台稳定性**
2. **继续优先收紧"只服务 UI 的后台行为"**
3. **如果网络切换响应仍不够，再考虑 3B-2（轻量 native callback）**
4. **如果要做可配置化，再把部分后台策略做成开关**
5. **仍然不建议直接搬 BettBox 的 smart stop 完整架构**

---

## 八、本轮提交记录

按时间顺序：

- `e5a04b8` `perf(android): reduce background traffic polling and notification churn`
- `6b8acd2` `perf(android): remove speed notification update path`
- `94f7470` `perf(android): pause foreground timers while app is backgrounded`
- `a860e91` `perf(android): close stale connections after network changes`
- `bcb1ff0` `perf(android): skip ui-heavy core events while app is backgrounded`
- `c47c3d6` `perf(android): keep full UI updates in foreground only`
- `1074c16` `perf(android): gate remaining visible-page UI churn`
- `6ba8738` `fix(ci): use tools page visibility for access view`
- `6854d3f` `fix(android): restore logs requests connections visibility`
- `<本次>` `perf(android): extend visibility control to proxies and profiles`

---

## 九、简短结论

这个 fork 当前的 Android 省电方向不是"更聪明地控制代理启停"，而是：

> **尽可能少做后台无意义工作，同时尽量不改变代理主运行链。**

这使它更适合在后续继续同步 upstream 的前提下长期维护。