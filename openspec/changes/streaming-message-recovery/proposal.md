## Why

opencode web 服务对单条用户消息会产生多段回复(思考 → 工具调用 → 中间文本 → 最终回复,共 N 条 message)。当前 `ChatPage` 在用户停留在会话页时,`sendMessagePersistent` 必须等 HTTP 响应(`POST /session/{id}/message`)完成才会回调一次,导致两个相互关联的体验 BUG:

1. **只显示一条**:opencode 后端在 POST 响应里只回**最后一条** message(其他中间 message 已在过程中被写入后端 store,但只在 SSE 事件中下发),HTTP 回调拿不到完整序列,所以 UI 只看到 1 条最终回复。
2. **没有逐条展示**:SSE 通道已经在 `text.delta` / `message.part.delta` / `message.updated` 事件中按 messageID 推送了每一段的增量,但 `ChatPage.handleSseEvent` 只用**单一** `streamingMessageId` 跟踪"最后那条",遇到中间的 `messageID` 切换就丢失,产生"白屏等到底"的现象。

本变更要打通"opencode web 分段回复 → APP 逐条恢复"的链路:发送消息后立即看到"思考中"占位,SSE 推送每条新 message 就插入/更新对应 ID 的卡片,完全结束时收口。

## What Changes

- **多 messageID 并行持有**:把 `ChatPage` 当前的"单 streamingMessageId + 单 streamingContent"重构为"按 messageID 的 Map",每条 message 独立维护"是否占位、文本、是否 loading、是否完成"。
- **新增 message 占位与提交流程**:
  - 收到 `message.updated`(role=assistant,新 id)→ 在 `messages` 末尾插入占位卡片(`isLoading=true`)。
  - 收到 `text.delta` / `message.part.delta`(携带 messageID)→ 找到该 id 的占位,按 delta 增量更新 `content`。
  - 收到 `message.updated` 中 `info.finish` 非空(或收到 `session.idle`)→ 关闭对应 message 的 loading。
- **新增 `user` 消息的回执刷新**:发送完 user message 后,SSE 首个 `message.updated(role=user)` 携带真实后端 id 时,用该 id 替换前端 `user-${ts}` 占位 id,确保后续分页/缓存按真实 id 命中。
- **重写 `sendMessage` 完成分支**:HTTP 响应到达后,只**在 SSE 尚未交付**任意 assistant message 的前提下,才把响应体作为兜底插入;否则只把响应中**比 `lastCachedMsgTime` 新的部分**追加到末尾(沿用现有增量刷新)。
- **修正 `finalizeStreamingMessage` 的误删逻辑**:当前实现用 `m.id !== this.streamingMessageId` 作为过滤条件会误删"非当前流式 ID 但合理的占位",改为"只清掉自己插入的占位 id(`loading-${ts}`、且无对应 SSE 推送的)"。
- **默认启用 SSE**:`OpenCodeCore.SSE_ENABLED` 由 `false` 改为 `true`,并在 AboutPage 提供"实时流式"开关,允许用户在 SSE 不可用时回退。
- **可观测性**:在 `finalizeStreamingMessage` / `message.updated` / `text.delta` 关键路径增加 `console.info`,记录 `messageID`、`contentLength`、`role`,便于现场排查。
- **保持后端协议不变**:opencode web 的 `GET /event` 与 `POST /session/{id}/message` 不变;本变更只调整前端消费 SSE 的状态机。

## Capabilities

### New Capabilities

- `chat-streaming-recovery`:opencode web 分段回复消息的"逐条恢复"能力,覆盖"多 messageID 持有与更新""user 消息 id 替换""HTTP/SSE 双链路收口""占位误删修复""SSE 默认启用"等行为契约。

### Modified Capabilities

- 无(现有 `keyboard-avoid-header`、`screen-rotation-lock` 不涉及消息流契约,无 `chat-message-pagination` 之外的现有 spec 需要 delta)。

## Impact

- **代码**:
  - `entry/src/main/ets/pages/ChatPage.ets` — 重构 `handleSseEvent`、`updateStreamingMessage`、`finalizeStreamingMessage`、`sendMessage` 内部回调,新增 `streamingById: Map<string, StreamState>` 或等价的 `@State` 组合。
  - `entry/src/main/ets/core/OpenCodeCore.ts` — `SSE_ENABLED` 改为默认 `true`;`dispatchSseEvent` 中 `message.updated` 已带 `info` 字段,确认 `streamMessageCallback` 透传 `info` 与 messageID。
  - `entry/src/main/ets/components/AboutPage.ets` — 新增"实时流式"开关(`StorageLink('sseEnabled')`),AboutPage 启动时把开关值同步到 `OpenCodeCore.SSE_ENABLED`。
  - 涉及 ArkTS 严格类型:Map / 嵌套对象字面量需按 `AGENTS.md` 提供显式接口,避免 `arkts-no-untyped-obj-literals` / `arkts-no-noninferrable-arr-literals` 编译错误。
- **依赖**:不引入新依赖,继续使用 `@ohos.net.http.requestInStream`。
- **API 契约**:opencode web 的 `/event` 事件流(`message.updated` / `message.part.updated` / `message.part.delta` / `text.delta` / `session.idle`)字段已在 `OpenCodeCore.SseEvent` 类型中声明,本变更只补充消费逻辑。
- **UI 体验**:用户在发送消息后立即看到"思考中"占位,后端每完成一段就有一条新消息卡片插入并实时刷新文本,工具调用、思考过程、中间草稿、最终回复都能按生成顺序呈现。
- **回退**:AboutPage 关闭"实时流式"后,`SSE_ENABLED=false`,`sendMessage` 走原 HTTP 一次性回调路径,行为回到变更前(可作为应急回退)。
