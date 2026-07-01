## Context

`OCodeController` 鸿蒙端的会话列表(`SessionList`)已经能展示 working 蓝点 / 未读数 / 草稿 / 后端备注 / 目录等关键信息,但状态字段同步存在两个缺口:

1. **working 状态不实时**:`SessionList` 仅在 `aboutToAppear` 与 `onRefreshNow` 时同步 `isWorking` / `unreadCount`,**没有订阅** `OpenCodeCore.sessionsChanged` 事件,所以用户在列表页停留时,SSE 推送的 `session.status(busy/retry)` 与 `session.idle` 不会驱动列表重渲染。后端在跑的任务,列表上看不到"工作中"状态。
2. **working 完成后没有未读感**:目前 `unreadCount` 只在 `ChatPage.aboutToDisappear` 设置 `wasLeft=true` 时被 +1,且依赖 `sendMessagePersistent` 的回调。如果用户在 ChatPage 期间 `session.idle` 自然结束,`wasLeft` 不会被设置,`unreadCount` 永远是 0,导致 working 完成的会话看起来"已读"。

`OpenCodeCore` 已经有较完整的会话状态管理:
- `setProjectWorking(projectId, working)`:写 `isWorking` + `saveProjects()` + `notifySessionsChanged()`。
- `session.idle` 事件处理:仅写 `isWorking = false` + `saveProjects()` + `notifySessionsChanged()`,**没有自增未读**。
- `notifySessionsChanged()` → `sessionsChangedCallback(timestamp)`:目前只被 `addProject` / `removeProject` / `removeSession` 触发,本变更要扩展到 `setProjectWorking` 与 `incrementUnreadCount`。
- `AppStorage.setOrCreate('refreshSessionsNow', ...)`:作为兜底通知,ChatPage 离开时仍会触发一次,本变更作为"硬保证"层保留。

`streaming-message-recovery` 之后,SSE 通道稳定可用,可以承担"列表页 working 实时"+"未读自增"两条主线。

## Goals / Non-Goals

**Goals:**
- 列表页实时显示 working / 未读 / 已读三态。
- working 期间按需轮询后端,展示"已生成 N 条"进度感。
- `session.idle` 后自动进入未读,直到用户进入会话清零。
- 与 `streaming-message-recovery` + ChatPage `wasLeft` 协同,避免重复计数。
- 可关闭、可降级:AboutPage 提供"列表轮询"开关,关闭时仅保留 `session.status/idle` 事件驱动。

**Non-Goals:**
- 不实现"消息已读/已送达"的远端持久化(本变更仅前端状态)。
- 不实现按项目分组的会话列表 UI(本期只做"实时状态",不做"分组/排序策略")。
- 不实现 N 个 working 会话的并发限流(典型用户在 1~3 个会话并行,3s 间隔在合理范围内)。
- 不重写 `OpenCodeApiClient`,沿用 `loadHistoryPage` 思路做轻量轮询。

## Decisions

### 1. 复用 `setSessionsChangedCallback`,不新增事件总线
**决定**:在 `SessionList.aboutToAppear` 调用 `core.setSessionsChangedCallback((ts: number) => this.onSessionsChanged(ts))`,`aboutToDisappear` 传 `null` 解除。
**理由**:`OpenCodeCore` 已有 `notifySessionsChanged` 与 `setSessionsChangedCallback` 完整签名,新增事件总线会引入冗余抽象。
**备选**:
- 用 `@StorageLink` 监听 `isWorking` / `unreadCount` 变化:需要 OpenCodeCore 把每个项目字段都写到 AppStorage,粒度过粗且 AppStorage 同步延迟,弃用。
- 新增 `EventBus` 工具类:与现有 callback 机制重复,被否决。

### 2. 轮询 = `setInterval`,不引入 RxJS/Worker
**决定**:`SessionList` 用 ArkTS 原生 `setInterval(handler, 3000)` 维护 `pollingTimers: Map<string, number>`,key 为 `projectId`。
**理由**:轮询周期稳定(3s),每会话独立 task,无需异步并发控制,ArkTS 原生定时器够用。
**备选**:
- 用 `setTimeout` 递归:可被 UI 调度打断,稳定性差,弃用。
- 在 `OpenCodeCore` 内做全局轮询:与 `SessionList` 生命周期耦合,被否决。

### 3. 轮询内容 = "最新一条 message 的 id + time"
**决定**:每次轮询请求 `GET /session/{id}/message?limit=1&order=desc`,解析返回的 `info.id` 与 `time.created`,与 `SessionList` 维护的 `lastKnownMessageIds: Map<string, string>` 对比。
**理由**:opencode 后端对 `limit=1&order=desc` 已经支持(`OpenCodeApiClient.getMessages` 与 `loadHistoryPage` 都用此模式),请求体积最小(几十字节),3s 一次不会对后端产生压力。
**备选**:
- 拉全量消息(`/message` 不带 limit):与 ChatPage 内 SSE / 缓存策略冲突,且列表页不需要历史,被否决。
- 拉 `?limit=20`:包含"已生成 N 条"统计需要遍历,得不偿失,弃用。

### 4. "已生成 N 条"用本地计数 + 卡片副标题
**决定**:每次轮询命中新的 `info.id` 时,把对应 `lastKnownMessageIds[projectId]` 更新为新 id,`generatedCount[projectId] += 1`,在 `SessionDisplayItem` 新增 `progressHint: string = ''` 字段,渲染到副标题旁。
**理由**:用户最关心"还差几条/已经出几条",给个简单数字即可,不需要展示具体内容。
**备选**:
- 用 `info.parts.length` 累加:可能与"消息条数"概念不一致(单条 message 可含多 part),弃用。
- 直接显示最新一条 message 摘要:文案渲染复杂,且消息可能很长,弃用。

### 5. `session.idle` 自增未读,但只在"用户不在该会话"时
**决定**:在 `OpenCodeCore.dispatchSseEvent` 的 `session.idle` 分支中:
- 若 `project.isWorking === true`(本次 idle 是从 working 退出):把 `isWorking = false`,然后:
  - 若 `currentProjectId !== project.id` → `unreadCount += 1`
  - 否则(用户在 ChatPage)→ 保持 `unreadCount`
- 若 `project.isWorking === false`(重复 idle,例如 SSE 重连):不再 +1,避免重复计数。
**理由**:用"是否处于 working 状态"作为去重标志,简单可靠。
**备选**:
- 用"上次 idle 时间戳"去重:需要新加 state 字段,得不偿失,弃用。
- 依赖 ChatPage 上报"已读":增加耦合,被否决。

### 6. 与 ChatPage `wasLeft` 协同:`wasLeft` 仅在 HTTP 路径生效
**决定**:`OpenCodeCore.session.idle` 自增未读后,ChatPage `aboutToDisappear` 的 `wasLeft` 兜底逻辑改为"仅当 OpenCodeCore 通知 `pendingRequest === null` 且 `isWorking === false` 时,说明 idle 已到达"才执行 +1;否则跳过。
**理由**:`streaming-message-recovery` 之后,ChatPage 内 SSE 接管了主要的"完成"信号,`wasLeft` 只剩"用户在 idle 到达前就离开"的边缘场景,加一个"已收口"判定避免重复 +1。
**备选**:
- 完全删除 `wasLeft` 分支:ChatPage 主动离开时若 SSE 尚未 idle,可能漏掉未读 +1,不删。

### 7. 开关与降级:AboutPage "列表轮询"开关
**决定**:AboutPage 新增 `Toggle({ isOn: $$listPollEnabled })` 绑定 `@StorageLink('listPollEnabled')`,默认 `true`;`SessionList.aboutToAppear` 读 `listPollEnabled`,为 `false` 时不启动轮询,只保留 SSE 状态变更驱动。
**理由**:提供显式回退路径,避免在某些网络/后端版本下持续轮询造成流量。
**备选**:
- 在 `OpenCodeCore` 加全局开关:粒度太粗,本变更只影响列表页,被否决。

## Risks / Trade-offs

- [R1: 多个 working 会话时,后端压力] → 3s 间隔 + `limit=1`,单会话轮询 QPS 约 0.33,典型用户在 1~3 个会话并行,后端 QPS < 1,可接受。
- [R2: `setInterval` 在 ArkTS 后台被冻结] → 用户切到后台时 SessionList 进入 `aboutToDisappear`,定时器被清,符合预期;恢复前台时 `syncWorkingState()` 重新启动,可能漏掉"后台期间新增的回复" → 用"立即执行一次"补齐差量。
- [R3: SSE 断线重连期间 `session.status/idle` 漏推] → ChatPage 内 SSE 与 `OpenCodeCore` 已有重连机制(见 `OpenCodeCore.startSse` 的 `dataEnd` 处理);列表页依赖该事件,本变更不修复 SSE 断线问题。
- [R4: 轮询结果与 SSE 推送的"新 message"竞争] → 轮询是"按 time 排序的最新一条",SSE 是"按推送顺序的事件",二者最终一致即可;UI 渲染时以"最新 known id"为准,不展示中间态。
- [R5: `currentProjectId` 在 `ChatPage` 内被切换但未离开页面(例如打开新会话)→ `setCurrentProject` 会更新 `currentProjectId`,idle 自增判定会按新值走,符合"用户在哪个会话就算哪个会话已读"的直觉。

## Migration Plan

1. 提交 `OpenCodeCore.dispatchSseEvent` 中 `session.idle` 自增未读逻辑 + `incrementUnreadCount` 公共方法。
2. 提交 `SessionList` 订阅 + 轮询逻辑,AboutPage 开关同步上线。
3. 提交 `ChatPage.aboutToDisappear` 的"已收口判定"补丁,避免重复 +1。
4. 验证:同时打开 2 个 working 会话,一个在 ChatPage 一个在 SessionList,确认:
   - ChatPage 中那个的卡片不出现红点;
   - SessionList 中那个的卡片显示 working 蓝点 → 完成后变红点 + 数字。
5. 回滚:AboutPage 关闭"列表轮询"开关即可,不影响 `session.status/idle` 事件驱动。

## Open Questions

- 轮询期间"已生成 N 条"的 N 是否要限制最大显示(避免"已生成 50 条"过长)?建议:UI 层做 `Math.min(N, 99) + '+'` 处理,本变更不细化,留作后续体验打磨。
- `currentProjectId` 在用户从 ChatPage 切到 SessionList 时会被 `setCurrentProject` 重新置为列表选中的项目 id,这会改变后续 idle 自增判定。**建议在 ChatPage.aboutToDisappear 中显式 `core.setCurrentProject('')`**,确保后续 idle 一定自增。本变更不修复,留作后续。
- `unreadCount` 是否需要按 message 条数累加(每次新 message +1)?目前是按"working 完成一次 +1",粒度更粗但语义清晰。若用户希望"每条新 message 都 +1",需要 ChatPage 内 SSE 收口时主动调用 `incrementUnreadCount`,本变更**不采纳**。
