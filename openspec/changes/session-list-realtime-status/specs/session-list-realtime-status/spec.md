## ADDED Requirements

### Requirement: SessionList 订阅 OpenCodeCore 状态变更
`SessionList` MUST 注册 `OpenCodeCore.sessionsChangedCallback`,在 `isWorking` 或 `unreadCount` 变化时实时重算 `sessions` 数组并刷新 UI。

#### Scenario: 远端 working 状态变化
- **WHEN** 后端通过 SSE 推送 `session.status(type=busy)`,且 `SessionList` 当前可见
- **THEN** `OpenCodeCore` 写入 `project.isWorking=true` 并触发 `sessionsChanged` 事件
- **AND** `SessionList` 在收到回调后于 100ms 内重算 `sessions`,对应卡片右上角的蓝点立即出现

#### Scenario: 远端 working 状态回归 idle
- **WHEN** 后端推送 `session.idle` 且当前 `currentProjectId !== project.id`(用户在列表页)
- **THEN** `project.isWorking=false`、`project.unreadCount` 自增 1,`sessionsChanged` 触发
- **AND** `SessionList` 卡片右上角蓝点消失,红点 + 数字角标出现

#### Scenario: 用户停留在 ChatPage 时的 session.idle
- **WHEN** 后端推送 `session.idle` 且 `currentProjectId === project.id`(用户在 ChatPage)
- **THEN** `project.isWorking=false`,`unreadCount` 保持 0(已读)
- **AND** 后续 `ChatPage.aboutToDisappear` 不再因 `wasLeft` 重复 +1

### Requirement: Working 期间轮询后端消息进度
`SessionList` MUST 对每个 `isWorking === true` 的会话启动一个轮询任务,周期性请求后端最新消息元信息,用于驱动"已生成 N 条"进度展示。

#### Scenario: working 状态上升为轮询起点
- **WHEN** `SessionList` 收到 `sessionsChanged` 且 `project.isWorking` 由 `false` 变为 `true`
- **THEN** 在 `pollingTimers` 中以 `projectId` 为 key 注册一个 `setInterval(task, POLL_INTERVAL_MS=3000)` 任务
- **AND** 任务首次立即执行一次,后续每 3 秒一次

#### Scenario: 轮询命中,展示进度
- **WHEN** 轮询任务成功请求 `GET /session/{id}/message?limit=1&order=desc`
- **THEN** 从响应中解析最新一条 message 的 `info.id` 与 `time.created`
- **AND** 与本地记录的 `lastKnownMessageId` 对比:若不同则更新 `lastKnownMessageId`,并在卡片副标题显示"已生成 N 条"(N = 已累计的不同 id 数量,本地维护)
- **AND** 轮询失败仅记日志,不打断列表渲染

#### Scenario: working 状态下降为轮询终点
- **WHEN** `SessionList` 收到 `sessionsChanged` 且 `project.isWorking` 由 `true` 变为 `false`
- **THEN** 在 `pollingTimers` 中以 `projectId` 为 key 移除并 `clearInterval` 对应任务
- **AND** 该会话的 `lastKnownMessageId` 在下次进入 working 时重置

#### Scenario: 多 working 会话并行
- **WHEN** 同时有两个 `isWorking === true` 的会话(后端两个项目同时在跑)
- **THEN** `pollingTimers` 中存在两个独立的定时器,互不干扰
- **AND** 任一会话 working 变化都不会影响另一会话的轮询节奏

### Requirement: 轮询生命周期与页面一致
`SessionList` MUST 在 `aboutToAppear` 启动轮询基础能力,在 `aboutToDisappear` 清理全部定时器与状态回调。

#### Scenario: 进入 SessionList
- **WHEN** 用户从其他页面切到 SessionList
- **THEN** `aboutToAppear` 注册 `core.setSessionsChangedCallback(this.onSessionsChanged)`
- **AND** `syncWorkingState()` 遍历 `core.getProjects()`,对所有 `isWorking === true` 的会话启动轮询

#### Scenario: 离开 SessionList
- **WHEN** 用户从 SessionList 切到 ChatPage / 后端页 / AboutPage
- **THEN** `aboutToDisappear` 遍历 `pollingTimers` `clearInterval` 全部任务并 `pollingTimers.clear()`
- **AND** 调用 `core.setSessionsChangedCallback(null)` 解除回调
- **AND** 重新回到列表页时,`syncWorkingState()` 会重新启动 working 会话的轮询

### Requirement: session.idle 触发未读自增
`OpenCodeCore` MUST 在 `session.idle` 事件处理中,根据当前 `currentProjectId` 与 `project.id` 的关系决定是否把 `unreadCount += 1`。

#### Scenario: 用户不在该会话页
- **WHEN** `session.idle` 到达,且 `currentProjectId !== project.id`(例如用户在 SessionList / BackendList / AboutPage)
- **THEN** `project.unreadCount += 1`,写存储 `saveProjects()`,触发 `notifySessionsChanged()`
- **AND** `StreamMessageCallback` 仍照常下发 `{ isComplete: true }`

#### Scenario: 用户在该会话页
- **WHEN** `session.idle` 到达,且 `currentProjectId === project.id`
- **THEN** `project.unreadCount` 保持 0,仅清 `isWorking`
- **AND** ChatPage 在 `session.idle` 收口时不依赖 `unreadCount` 判断

#### Scenario: 同一 session.idle 重复到达
- **WHEN** SSE 重连后,`session.idle` 再次推送给同一个 project
- **THEN** 仅当 `isWorking` 仍为 `true` 时执行自增,避免重复 +1
- **AND** 重复自增的判定用"`isWorking === true` → 关闭后 +1,且 `idleCount` 计数器加 1"的去重策略

### Requirement: 未读自增的兜底与 ChatPage 协同
`OpenCodeCore` MUST 与 `ChatPage` 已有 `wasLeft` 自增逻辑协同,避免重复计数。

#### Scenario: ChatPage 在前台时收到 session.idle
- **WHEN** 用户停留在 ChatPage,后端 `session.idle` 到达
- **THEN** OpenCodeCore 不自增未读(用户在 ChatPage)
- **AND** ChatPage 后续 `aboutToDisappear` 触发 `wasLeft = true`,但因 idle 已把 `isWorking=false` 关闭,`wasLeft` 分支不会重复 +1(调整后该分支只对 HTTP 兜底路径生效)

#### Scenario: 用户提前离开 ChatPage 且 idle 未到
- **WHEN** 用户在 ChatPage 还在 working 时按返回键,后端尚未 `session.idle`
- **THEN** `ChatPage.aboutToDisappear` 设置 `wasLeft = true`
- **AND** 后续 `session.idle` 到达时由 OpenCodeCore 自增未读 +1,ChatPage 兜底路径不再 +1

### Requirement: 状态字段可观测
`SessionList` 与 `OpenCodeCore` MUST 在关键路径输出可定位的日志(包含 `projectId`、`isWorking`、`unreadCount`、`pollingTimers.size`)。

#### Scenario: 排查"working 状态不更新"
- **WHEN** 现场反馈某会话一直显示已读,实际后端还在跑
- **THEN** 日志中能定位到:`session.status(busy) → setProjectWorking(true) → notifySessionsChanged → SessionList.onSessionsChanged → syncWorkingState → startWorkingPoll`
- **AND** 缺失其中任一环节都能被定位

#### Scenario: 排查"未读数不增加"
- **WHEN** 现场反馈 working 完成后未读没出现
- **THEN** 日志中能找到:`session.idle → currentProjectId !== project.id → unreadCount+1 → notifySessionsChanged → SessionList.onSessionsChanged`
- **AND** 若 `currentProjectId === project.id` 误判,日志中记录 `currentProjectId` 与 `project.id` 便于对照
