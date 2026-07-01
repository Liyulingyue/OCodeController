## Why

完成 `streaming-message-recovery`(SSE 逐条恢复)后,用户在 ChatPage 内已经能看到 opencode web 推送的"思考/工具/中间文本/最终回复"逐条出现。但当用户切到会话列表(`SessionList`),会话卡片的工作状态并不能反映实时进度:

- `isWorking` 仅依赖 `OpenCodeCore.session.status` 事件回写,用户停留在列表时该事件会推过来,但列表组件本身**没有订阅** `OpenCodeCore.sessionsChanged`,所以 working 状态会"卡在旧值"或不更新。
- `unreadCount` 只在用户停留在 ChatPage 期间、且 `leftCurrentProject` 时被 +1;`session.idle` 之后并没有"未读数自增"机制,导致 working 完成的会话**不会自动进入未读态**。
- working 期间,用户希望在列表中能看到"后端正在生成第 N 条回复"这种"进度感",仅靠 working 蓝点不足以体现。

本变更要落地:列表页实时同步每条会话的 working / 未读 / 已读状态;working 时定时轮询后端消息,反映"后端已生成 N 条"进度;`session.idle` 后自动转未读态,直到用户进入会话才清零。

## What Changes

- **SessionList 订阅 OpenCodeCore 状态变更**:在 `aboutToAppear` 注册 `setSessionsChangedCallback`,收到事件后重算 `sessions` 列表,确保 `isWorking` / `unreadCount` 即时更新。
- **Working 期间轮询后端消息**:当 `isWorking === true` 的会话存在时,启动一个"对该会话的轮询任务",间隔(默认 3s,可配置)请求 `GET /session/{id}/message?limit=1&order=desc`,把返回的消息总数或最新消息 ID 与本地缓存对比,用于驱动"已生成 N 条"进度感;不要求重新拉全量消息(避免与 ChatPage 内 SSE 重复)。
- **`session.idle` 触发未读自增**:在 `OpenCodeCore.dispatchSseEvent` 的 `session.idle` 分支中,如果项目当前 `currentProjectId !== project.id`(即用户不在该会话页),把 `unreadCount += 1` 并写存储、推 `sessionsChanged` 事件;在 ChatPage 时则保持已读(沿用现有 `wasLeft` 逻辑)。
- **轮询任务按需启停**:`SessionList` 维护 `pollingTimers: Map<projectId, number>`,只有 `isWorking` 的会话会被加入;`isWorking` 转 `false` 时移除定时器,避免空转。
- **轮询生命周期与页面共存**:`aboutToAppear` 启动、`aboutToDisappear` 清空全部定时器,并 `setSessionsChangedCallback(null)`。
- **可观测性**:在轮询命中、`session.idle` 未读自增、订阅回调触发处打印 `console.info` 含 `projectId`、`unreadCount`、`pollingTimers.size`,便于现场排查。
- **保持后端协议不变**:opencode web 的 `/event` 与 `/session/{id}/message` 不变;不引入新依赖。
- **与 `streaming-message-recovery` 协同**:该 change 把 `session.idle` 改成"未读自增"逻辑后,ChatPage 侧的 `wasLeft` 兜底逻辑仍然有效(用户离开 ChatPage 但 APP 在前台,且没及时 `session.idle` 的极端情况)。

## Capabilities

### New Capabilities

- `session-list-realtime-status`:会话列表下每条会话的 working / 未读 / 已读三态实时同步能力,覆盖"SessionList 订阅状态变更""working 期间轮询后端消息""session.idle 触发未读自增""轮询任务按需启停""轮询与页面生命周期一致"等行为契约。

### Modified Capabilities

- 无(现有 `keyboard-avoid-header`、`screen-rotation-lock`、`chat-message-pagination`、`chat-streaming-recovery` 都不约束列表页状态字段,故不需要 delta spec)。

## Impact

- **代码**:
  - `entry/src/main/ets/components/SessionList.ets` — `aboutToAppear` 注册 `core.setSessionsChangedCallback(...)`,`aboutToDisappear` 清空 `pollingTimers` + 反注册;新增 `startWorkingPoll(projectId)` / `stopWorkingPoll(projectId)` / `syncWorkingState()` 三个私有方法;`onRefreshNow` 中合并 SSE 状态变更时的轮询重建。
  - `entry/src/main/ets/core/OpenCodeCore.ts` — `session.idle` 分支补"用户不在该会话则 `unreadCount++`"逻辑;`setProjectWorking(false)` 同时清空 `unreadCount` 之外不主动复位;新增 `incrementUnreadCount(projectId)` 公共方法供测试/外部调用;`sessionsChangedCallback` 在 `setProjectWorking`、`incrementUnreadCount` 中触发。
  - `entry/src/main/ets/pages/ChatPage.ets` — `aboutToDisappear` 的 `wasLeft` 分支继续作为兜底,但 `session.idle` 已自增时,该 `+1` 需去重(在 ChatPage 中由"实时 SSE 收口"决定是否减 1,以避免重复)。
- **依赖**:不引入新依赖,继续使用 `@ohos.net.http`。
- **API 契约**:opencode web 的 `GET /session/{id}/message?limit=1&order=desc` 已支持(在 `OpenCodeApiClient.getMessages` 中),本变更复用 `loadHistoryPage` 思路。
- **UI 体验**:用户在列表页能直接看到"AI 工作中(蓝点) / 1 条未读(红点) / 已读"三态过渡;working 期间列表卡片副标题可显示"已生成 N 条",提供进度感。
- **回退**:把 `POLL_INTERVAL_MS` 调到 `0` 即关闭轮询(只保留 `session.status` 事件驱动的 working 切换 + `session.idle` 未读自增),行为退回到"事件驱动型"。
