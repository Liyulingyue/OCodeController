## 1. 类型与状态结构

- [ ] 1.1 在 `ChatPage` 顶部新增 `interface StreamState { content: string; isLoading: boolean; role: 'user' | 'assistant'; lastUpdateAt: number; }`,按 ArkTS 规则使用显式类型,避免 `any` / 隐式对象字面量。
- [ ] 1.2 在 `ChatPage` 新增 `@State streamingById: Map<string, StreamState> = new Map()`,并新增 `@State pendingPlaceholderIds: Set<string> = new Set()` 记录本轮前端插入的占位。
- [ ] 1.3 新增 `@State sseDeliveredAny: boolean = false`,记录"本轮是否收到过任意 assistant message 的 SSE 推送",用于 HTTP 兜底判定。
- [ ] 1.4 抽 `StreamMessageCallback` 已有签名,确认 `OpenCodeCore.dispatchSseEvent` 的 `message.updated` 路径会附带 `info` 字段,信息足够还原 `StreamState`。

## 2. SSE 消费重构

- [ ] 2.1 重写 `handleSseEvent`:`message.updated` 入口按 `info.id` 注册或刷新 `streamingById`,role=user 时把对应前端占位 id 替换为真实 id。
- [ ] 2.2 抽 `appendDeltaToMessage(messageID: string, delta: string)`,`text.delta` 与 `message.part.delta(part.type='text')` 都调它,内部做"不存在则忽略+日志"与"幂等去重"(`lastDeltaMessageID`)。
- [ ] 2.3 `message.updated` 入口处理 `info.finish`:非空时把对应 message 的 `isLoading=false`;为 user 时只更新 id,不设 isLoading。
- [ ] 2.4 `session.idle` 入口:遍历 `streamingById` 把所有 `isLoading=true` 置 `false`,并把 `pendingPlaceholderIds` 中"未在 SSE 真实 id 中出现"的占位从 `messages` 中删除。

## 3. 渲染层适配

- [ ] 3.1 改造 `buildMessageItem`/`parseMessageSegments`:对 `isLoading=true` 的 message 渲染"思考中"占位 UI(沿用现有 `isLoading` 分支),不再依赖单一 `streamingMessageId`。
- [ ] 3.2 `ForEach` 的 key 仍用 `msg.id`,但新增 `id` 替换场景下要确保 key 不会因 `id` 变化触发整树重建(用 `(msg: DisplayMessage) => msg.msgId || msg.id` 兜底)。
- [ ] 3.3 新增"会话级加载指示":仅在 `sseDeliveredAny` 为 `true` 时,顶部展示"AI 正在思考…",与现有"思考中…"按钮文案区分。
- [ ] 3.4 `appendDeltaToMessage` 内的 `scrollToBottom` 仅在 `messages.length` 变化时调用;纯 delta 不滚动。

## 4. sendMessage 与 HTTP 收口

- [ ] 4.1 改造 `sendMessage`:把 `userMsgId` 加入 `pendingPlaceholderIds`,并在 SSE `message.updated(role=user)` 到达时移除占位、刷新 `id`。
- [ ] 4.2 改造 `sendMessage` 内 `core.sendMessagePersistent` 回调:HTTP 200 到达时,先检查 `sseDeliveredAny`:
  - 为 `false` → 把 `response` 作为单条 assistant 卡片插入,`isLoading=false`。
  - 为 `true` → 检查 `response.info.id`:
    - 在 `streamingById` 中 → 跳过。
    - 不在但 `info.time.created > lastCachedMsgTime` → 追加到末尾。
  - 任何路径下,把 `pendingPlaceholderIds` 中的"无 SSE 真实 id"占位从 `messages` 中过滤掉。
- [ ] 4.3 错误路径(error)保持现有行为:删除占位,显示错误卡片;不再依赖 `streamingMessageId`。

## 5. finalizeStreamingMessage 修复

- [ ] 5.1 把 `m.id !== this.streamingMessageId` 过滤替换为 `pendingPlaceholderIds.has(m.id)`。
- [ ] 5.2 在 `message.updated` 命中 `pendingPlaceholderIds` 中的 id 时,从 `pendingPlaceholderIds` 移除该 id(避免误删真实卡片)。
- [ ] 5.3 在 `aboutToDisappear` 显式 `this.streamingById = new Map()`、`this.pendingPlaceholderIds = new Set()`、`this.sseDeliveredAny = false`,避免跨会话残留。

## 6. SSE 默认启用与开关

- [ ] 6.1 `OpenCodeCore.SSE_ENABLED` 改为 `true`。
- [ ] 6.2 在 `EntryAbility.onCreate` 从 `StorageLink('sseEnabled')` 同步到 `OpenCodeCore.SSE_ENABLED`(默认 `true`)。
- [ ] 6.3 `AboutPage.ets` 新增"实时流式"开关:`@StorageLink('sseEnabled') sseEnabled: boolean = true`,切换时立即同步到 `OpenCodeCore.SSE_ENABLED`,并触发 `OpenCodeCore.startSse(currentProjectId)` 或 `OpenCodeCore.stopSse()`。
- [ ] 6.4 校验 `ChatPage.aboutToAppear` 在 `SSE_ENABLED=false` 时不调用 `startSse`,但仍可保留"思考中"占位 UI(由 HTTP 路径收口)。

## 7. 可观测性

- [ ] 7.1 在 `message.updated`、`text.delta`、`session.idle` 三个入口打 `console.info` 含 `messageID` / `role` / `contentLength`。
- [ ] 7.2 在 `finalizeStreamingMessage` 入口打日志,记录"本轮占位清理结果"(删除数量、剩余卡片数量),便于现场定位"消息没出来"。

## 8. 验证

- [ ] 8.1 发送一条"请调用一个工具并回复"的指令,确认中间出现多张 assistant 卡片(思考/工具/草稿/最终),每张实时刷新,顺序与 opencode web 推送一致。
- [ ] 8.2 发送一条"直接回答"的简单指令,确认单条卡片正常显示,且不会出现"重复插入"。
- [ ] 8.3 杀掉应用,断网重连,冷启动进入会话再发送,确认 SSE 失败时降级到 HTTP 一次性回调,UI 仍能展示最终回复。
- [ ] 8.4 在 AboutPage 关闭"实时流式",重新发送消息,确认回到旧版 HTTP 一次性行为。
- [ ] 8.5 跑 `hvigorw assembleHap` 或项目内构建脚本,确保 0 error / 0 warning(尤其留意 `arkts-no-untyped-obj-literals`、`arkts-no-noninferrable-arr-literals`)。
