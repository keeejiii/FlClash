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
5. **尽量把改动收束在少量文件，方便后续同步 upstream**

---

## 二、阶段总览

本轮改动分成四个阶段：

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
- 以及后续清理：
  - `android/app/src/main/kotlin/com/follow/clash/Service.kt`
  - `android/app/src/main/kotlin/com/follow/clash/plugins/ServicePlugin.kt`
  - `android/service/src/main/java/com/follow/clash/service/models/NotificationParams.kt`
  - `android/service/src/main/java/com/follow/clash/service/models/Traffic.kt`
  - `lib/plugins/service.dart`

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
这部分没有做“隐藏一个显示项”那么简单，而是**把整条 speed 通知链路完整回收**：

- 删除 Flutter -> MethodChannel -> Kotlin 的 speed 通知推送接口
- `NotificationParams` 去掉 `contentText`
- `NotificationModule` 回退成静态前台通知，只保留：
  - 标题
  - 停止按钮

效果：
- 通知栏不再显示 `↑ xx/s ↓ xx/s`
- 不再有专门为 speed 刷新的链路

#### C. 补 Doze 监听
在 `SuspendModule.kt` 中增加：

- `PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED`

效果：
- 进入 / 退出 Doze 时，挂起状态判断更完整
- 不只依赖亮灭屏广播

### 1.4 收益

- 后台 traffic 统计活跃度下降
- 通知栏从“动态 speed 面板”退回静态前台 service 通知
- 减少因通知 speed 刷新导致的额外 wakeup / UI 更新
- Doze 下的挂起逻辑更完整

### 1.5 风险与取舍

- 放弃了通知栏实时速度可视化
- 但这是主动取舍，换取更干净的后台行为
- 没有停前台 service，没有伤害代理保活主链路

### 1.6 对应提交

- `e5a04b8` `perf(android): reduce background traffic polling and notification churn`
- `6b8acd2` `perf(android): remove speed notification update path`

---

## 阶段 2（3A）：后台真正停 foreground timer

### 2.1 目标

阶段 1 完成后，后台虽然已经不再每秒更新 traffic，但 periodic timer 仍然存在：

- 每秒触发一次 Dart 层 timer
- 只是进入后很快 return

这仍然不是最省。

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

调整：

- `_handleStart()` 不再直接裸建 timer，统一走 `_startUpdateTimer()`
- `handleStop()` 统一走 `pauseForegroundUpdates()`

#### B. 在 `AppStateManager` 里接 lifecycle
在 `didChangeAppLifecycleState()` 中：

- `resumed`：
  - `resumeForegroundUpdates()`
  - 然后继续原本的权限检查、恢复、checkIp、Android 下的 core 状态检查
- `inactive / hidden / paused / detached`：
  - `pauseForegroundUpdates()`

### 2.4 收益

- 后台不再保留每秒 periodic timer
- 比“后台跑 timer 再 return”更干净
- 前台恢复后可以立即补一次状态，避免 UI 卡住一拍

### 2.5 风险与取舍

- 后台时 `runTime` 数值不会每秒递增刷新，但 `runTimeProvider` 不会被置空
- 也就是说：
  - UI 上“正在运行”的状态仍然存在
  - 只是后台不再做无意义数值更新

### 2.6 对应提交

- `94f7470` `perf(android): pause foreground timers while app is backgrounded`

---

## 阶段 3（3B-1）：网络变化后轻量清理旧连接

### 3.1 目标

FlClash 在网络切换时，可能出现：

- 旧连接拖尾
- Wi‑Fi / 流量切换后恢复慢
- 后台切网后一段时间才恢复正常

BettBox 在这类场景中更积极，但其实现已经扩展成一整套 native 状态机，直接搬会显著扩大 fork 分叉。

目标：

- 不引入 smartStop / smartResume
- 不引入 Android native 复杂状态机
- 只在 Dart 层做一个轻量网络变化响应

### 3.2 涉及文件

- `lib/application.dart`

### 3.3 实际做法

直接复用现有 `ConnectivityManager(onConnectivityChanged: ...)`：

#### A. 增加主网络类型判断
新增：

- `_lastPrimaryConnectivity`
- `_getPrimaryConnectivity(List<ConnectivityResult>)`

主网络类型优先级：
- wifi
- mobile
- ethernet
- bluetooth
- other
- vpn
- none

目的：
- 避免 `vpn` 结果污染真实底层网络判断

#### B. 增加 debounce
新增：

- `_networkChangeDebounceTimer`

逻辑：
- 网络主类型发生变化后
- debounce 800ms
- 再执行动作

#### C. 轻量动作：`closeConnections()`
触发条件：
- Android 平台
- 主网络类型真的变化
- 当前已启动
- 当前不在 suspend 状态

动作：
- `await coreController.closeConnections()`

### 3.4 收益

- Wi‑Fi ↔ 流量切换时，旧连接更快清掉
- 减少切网后的连接拖尾和恢复慢
- 不改变 VPN / service 生命周期

### 3.5 风险与取舍

- 某些长连接场景下，切网时会更积极地清旧连接
- 这是主动取舍，用更快恢复换更少拖尾
- 没有动 core 主状态，也没有做 aggressive restart

### 3.6 对应提交

- `a860e91` `perf(android): close stale connections after network changes`

---

## 阶段 4（3C-lite）：后台丢弃高频 UI 事件

### 4.1 为什么不是直接做“后台停 listener”

在 FlClash 当前架构里：

- `startListener()` / `stopListener()`
- 最终和 Android service 生命周期绑定

也就是说，如果直接把 listener 当作“后台 UI 消费开关”：

- 后台 `stopListener()`
- 很可能不是只停 UI 事件消费
- 而是把 service / 代理运行链路一起动到

这太危险，不适合作为省电优化直接落地。

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

同时，页面级的明显 UI 刷新残口也进一步收紧为“当前页可见才运行”：

- `ConnectionsView` 的 1 秒 `getConnections()` 轮询，不在当前页或后台时直接停止，回到当前页再恢复
- `RequestsView` 的显示刷新层，不在当前页或后台时不再继续推动 `_requestsStateNotifier`
- `LogsView` 的显示刷新层，不在当前页或后台时不再继续推动 `_logsStateNotifier`，但日志采集与保留本身不受影响，回到当前页后再同步显示
- `networkDetection` 的触发条件收紧为“仪表盘当前可见”，离开仪表盘就清空 UI 状态，回到仪表盘再重新检测

这里的设计原则不是“把前台体验砍残”，而是：

> **当前页 UI 完整，不可见页静默；后台 UI 静默；运行层与日志保留。**

### 4.5 收益

- 后台不再消费高频 UI 事件
- 连对应的事件反序列化成本也能省一点
- crash 事件保留，不影响后台异常感知
- log 保留，不影响后台调试和错误暴露
- `loaded` 在后台直接跳过，避免为不可见页面维持 provider / group 同步抖动
- 连接页轮询、请求页和日志页显示层、network detection 都进一步纳入“不可见即静默”
- 规则更统一：当前页完整、不可见页静默、后台静默

### 4.6 风险与取舍

- 后台时 request / delay 等前台专属 UI 数据不会继续增长
- 不在当前页时，日志 / 请求 / 连接这些页面的显示层状态不会持续维护
- 这是预期行为：后台不再为不可见 UI 持续加工高频数据
- 日志保留全部等级（debug / info / warning / error），用于后台调试与排障
- 当前页恢复时会重新从 provider / core 同步最新可见数据，以换取不可见期的更低 churn

### 4.7 对应提交

- `bcb1ff0` `perf(android): skip ui-heavy core events while app is backgrounded`

### 4.8 当前工作树继续补充（未提交）

- `LogsView`：只有当前页可见时才同步 `_logsStateNotifier`
- `RequestsView`：只有当前页可见时才同步 `_requestsStateNotifier`
- `ConnectionsView`：只有当前页可见时才维持 1 秒轮询
- `AppStateManager`：`networkDetection` 只有仪表盘当前可见时才触发；离开仪表盘即清空 UI 状态

---

## 四、最终效果总结

到当前版本为止，这个 fork 已经形成了一套 **Android 后台减活跃方案**：

1. **后台不再每秒刷新 traffic，而是保留低频补采样**
2. **后台真正停 foreground timer**
3. **切网后主动清理旧连接**
4. **后台不再消费高频 UI 事件**
5. **连接页 / 请求页 / 日志页只在当前页可见时更新显示层**
6. **network detection 只在仪表盘当前可见时触发**
7. **通知栏回退静态前台 service 形态**
8. **日志在前后台都完整保留**
9. **Doze 监听补齐**

这套方案的特点不是“激进智能保活”或“智能暂停代理”，而是：

> **当前页 UI 完整、不可见页静默、后台 UI 静默，同时尽量不伤害 VPN / service 主链路。**

---

## 五、对后台留存与前台行为的判断

这轮修改的目标不是“用更复杂的保活手段提升留存”，而是“降低后台噪音，避免系统把它判成高活跃后台”，同时保持：

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
2. **继续优先收紧“只服务 UI 的后台行为”**
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

---

## 九、简短结论

这个 fork 当前的 Android 省电方向不是“更聪明地控制代理启停”，而是：

> **尽可能少做后台无意义工作，同时尽量不改变代理主运行链。**

这使它更适合在后续继续同步 upstream 的前提下长期维护。
