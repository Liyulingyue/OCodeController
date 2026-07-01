## 1. OpenCodeCore 自增未读与状态事件扩展

- [ ] 1.1 在 `OpenCodeCore` 顶部新增常量 `LIST_POLL_DEFAULT_INTERVAL_MS = 3000`,放在 `SSE_ENABLED` 附近。
- [ ] 1.2 新增公共方法 `incrementUnreadCount(projectId: string): void`,内部 `unreadCount += 1` → `saveProjects()` → `notifySessionsChanged()`,并打印 `console.info` 含 `projectId` 与最新 `unreadCount`。
- [ ] 1.3 `setProjectWorking(projectId, working)` 改造:在写 `isWorking` 后,把"是否需要触发 `notifySessionsChanged`"的判定条件从"`isWorking` 变化"扩展为"`isWorking` 变化或 working 转为 true/false 时强制触发",保证下游 SessionList 总是收到。
- [ ] 1.4 `dispatchSseEvent` 的 `session.idle` 分支改造:
  - 校验 `project.isWorking === true` 才执行"自增未读"路径,避免重复计数。
  - 自增前比较 `currentProjectId !== project.id`,是则 `incrementUnreadCount`。
  - 在该分支内打 `console.info`,含 `projectId`、`currentProjectId`、`unreadCount`。
- [ ] 1.5 确认 `notifySessionsChanged` 在 `setProjectWorking`、`incrementUnreadCount`、`session.idle` 三个入口都被调用,保证 SessionList 一定收到事件。

## 2. SessionList 订阅与基础同步

- [ ] 2.1 在 `SessionList` 新增 `@State lastKnownMessageIds: Map<string, string> = new Map()` 与 `@State generatedCounts: Map<string, number> = new Map()`,以及 `private pollingTimers: Map<string, number> = new Map()`。
- [ ] 2.2 新增常量 `POLL_INTERVAL_MS = 3000` 与 `@StorageLink('listPollEnabled') listPollEnabled: boolean = true`。
- [ ] 2.3 `aboutToAppear` 中:
  - 调用 `this.core.setSessionsChangedCallback((ts: number) => this.onSessionsChanged(ts))`;
  - 调用 `this.syncWorkingState()` 启动/恢复轮询。
- [ ] 2.4 `aboutToDisappear` 中:
  - 遍历 `pollingTimers` `clearInterval` 并 `pollingTimers.clear()`;
  - 调用 `this.core.setSessionsChangedCallback(null)`。
- [ ] 2.5 新增 `onSessionsChanged(ts: number): void` 私有方法:重新 `refreshSessions()` + `syncWorkingState()`,并在调用前打 `console.info` 含 `ts` 与 `sessions.length`。
- [ ] 2.6 `refreshSessions` 在原逻辑基础上,把 `progressHint` 字段也填进去:从 `generatedCounts` 取值,有值时显示"已生成 N 条",无值时显示空串。

## 3. 轮询任务启停

- [ ] 3.1 新增 `startWorkingPoll(projectId: string): void`:校验 `listPollEnabled === true` 且 `pollingTimers` 中无该项目;构造 `task` 闭包,`task` 调 `this.pollOnce(projectId)`;用 `setInterval(task, POLL_INTERVAL_MS)` 注册并把 handle 写入 `pollingTimers`;`task` 首次立即同步执行一次。
- [ ] 3.2 新增 `stopWorkingPoll(projectId: string): void`:从 `pollingTimers` 取 handle,`clearInterval` 并 `delete`;同时把 `lastKnownMessageIds.delete(projectId)` 与 `generatedCounts.delete(projectId)`,为下次 working 重置做准备。
- [ ] 3.3 新增 `syncWorkingState(): void`:遍历 `core.getProjects()`,对 `isWorking === true` 的项目调 `startWorkingPoll`,对 `isWorking === false` 的项目调 `stopWorkingPoll`;打 `console.info` 含 `pollingTimers.size`。
- [ ] 3.4 新增 `pollOnce(projectId: string): Promise<void>`:从 `core.getProjectById(projectId)` 读 url/username/authToken/path/remoteSessionId,若 `remoteSessionId` 缺失则直接 return;请求 `GET /session/{id}/message?limit=1&order=desc`;成功 200 后解析最新 message 的 `info.id`;与 `lastKnownMessageIds[projectId]` 对比,不同则更新并 `generatedCounts[projectId] = (generatedCounts[projectId] ?? 0) + 1`,触发 `refreshSessions()` 刷新;失败仅 `console.warn` 不抛出。
- [ ] 3.5 校验 `setProjectWorking` 与 `incrementUnreadCount` 一定会触发 `notifySessionsChanged`,保证 SessionList 能感知。

## 4. AboutPage 开关

- [ ] 4.1 在 `AboutPage.ets` 新增 `@StorageLink('listPollEnabled') listPollEnabled: boolean = true`,新增"列表会话轮询"开关的 `Toggle` 控件,label 写"列表轮询 working 会话"。
- [ ] 4.2 切换开关时打印 `console.info` 含 `listPollEnabled`,由 SessionList 在下次 `syncWorkingState` 时按新值生效。
- [ ] 4.3 AboutPage 启动时校验 `listPollEnabled` 的默认值为 `true`,避免存量用户缺失配置导致开关关闭。

## 5. ChatPage 协同

- [ ] 5.1 `ChatPage.aboutToDisappear` 中 `wasLeft` 分支改造:增加"是否已收口"判定 —— `core.isProjectWorking(this.sessionId) === false` 且 `core.getPendingMessage() === null` 时,认为 idle 已由 OpenCodeCore 处理,跳过 `unreadCount + 1`;否则维持原 `+1` 兜底逻辑。
- [ ] 5.2 校验 `core.setCurrentProject('')` 在 `aboutToDisappear` 中是否调用,若未调用则补上,避免后续 idle 误判 `currentProjectId === project.id`。

## 6. 可观测性

- [ ] 6.1 在 `startWorkingPoll`、`stopWorkingPoll`、`pollOnce` 命中、`incrementUnreadCount`、`session.idle` 自增判定处打 `console.info`,含 `projectId`、`isWorking`、`unreadCount`、`pollingTimers.size`。
- [ ] 6.2 在 `onSessionsChanged` 入口打 `console.info`,含 `ts` 与 `sessions.length`,便于排查"事件没收到"或"事件收到但 UI 不刷新"。

## 7. 验证

- [ ] 7.1 启动 APP,创建两个会话 A、B,A 留在 ChatPage,B 切到 SessionList,同时让 A、B 触发后端 working(分别用不同后端或同一后端两个 session)。
- [ ] 7.2 观察列表页 B 卡片右上角出现蓝点(working),ChatPage 内 A 卡片右上角无变化(因为在 ChatPage 内)。
- [ ] 7.3 working 完成后:B 卡片蓝点变红点 + 数字"1";A 在 ChatPage 内仍是已读(无未读数)。
- [ ] 7.4 验证多会话并行 working:再开一个 C,确认 C 卡片有独立轮询节奏,关闭 C working 后 C 轮询停止,A、B 不受影响。
- [ ] 7.5 关闭 AboutPage"列表轮询"开关,确认列表页仍能反映 working → 未读(SSE 事件驱动),只是没有"已生成 N 条"进度感。
- [ ] 7.6 跑 `hvigorw assembleHap` 或项目内构建脚本,确保 0 error / 0 warning(尤其留意 `arkts-no-untyped-obj-literals`、`arkts-no-noninferrable-arr-literals`)。
