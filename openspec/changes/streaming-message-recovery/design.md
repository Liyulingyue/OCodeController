## Context

`OCodeController` 鸿蒙端已经接入了 opencode web 的 SSE 事件流(`OpenCodeCore.startSse` + `handleSseChunk` + `dispatchSseEvent`),事件类型完整覆盖 `server.connected` / `session.status` / `session.idle` / `message.updated` / `message.part.updated` / `message.part.delta` / `text.delta` / `permission.*`。但消费侧 `ChatPage.handleSseEvent` 仅维护一个 `streamingMessageId`,遇到以下场景就失效:

- **新 message 切换**:`message.updated` 携带新的 `info.id` 时,代码 `if (msgId && this.streamingMessageId !== msgId)` 会更新 `streamingMessageId` 并清空 `streamingContent`,导致上一条 message 的内容被丢弃。
- **同时多段并行**:opencode 在一次用户回合内可能先推"思考"再推"工具调用"再推"草稿回复"再推"最终回复",而前端只有一个 ID 槽位,只能"串行"渲染。
- **HTTP 一次性收尾**:`sendMessagePersistent` 回调在 `session.idle` 之前到达,`response` 会被无脑插入 `messages`,但 `formatMessage(response)` 拼出的内容可能与 SSE 已经在堆的中间卡片重复/覆盖。
- **占位误删**:`finalizeStreamingMessage` 的 `m.id !== this.streamingMessageId` 过滤条件会把"非当前流式 ID 但合理存在"的占位卡片删除。
- **SSE 默认关闭**:`OpenCodeCore.SSE_ENABLED = false`,即使用户停留在会话页也只能等 HTTP 一次性回调。

本变更要打通"opencode web 推送 → 多个 messageID → 多张卡片"的真实链路,实现"思考中"占位、每条 message 独立占位与完成、HTTP 兜底/补齐、user id 替换、可关闭开关、可观测日志。

## Goals / Non-Goals

**Goals:**
- 发送消息后立刻看到"思考中"占位,后端每完成一段就插入新卡片并实时刷新文本。
- 多个 assistant message 并行存在,互不覆盖。
- HTTP 响应到达时按"是否已交付"决定兜底或补齐,不重复插入。
- `session.idle` 兜底关闭所有 loading,清掉前端"思考中"占位。
- SSE 失败/被关闭时优雅降级到 HTTP 一次性回调路径。
- AboutPage 提供"实时流式"开关,默认开启。

**Non-Goals:**
- 不实现消息编辑/重发/分支(超出本变更范围)。
- 不实现 message 级别的事件回放(只保证"实时+收尾"两条主路径)。
- 不重构 `OpenCodeApiClient` 后端调用;沿用现有 `sendMessagePersistent`。
- 不实现后端协议适配(以 opencode web 当前事件类型为准)。

## Decisions

### 1. 用 `Map<messageID, StreamState>` 替代单 ID 持有
**决定**:`ChatPage` 新增 `@State streamingById: Map<string, StreamState>`,每个 `StreamState` 包含 `content: string`、`isLoading: boolean`、`role: 'assistant' | 'user'`、`partTypes: Set<string>`(用于去重 `text` / `tool` / `reasoning` 等 part)。
**理由**:opencode web 的事件天然按 messageID 切分,Map 是最贴近协议的本地状态结构;`@State Map` 在 ArkUI 中需通过 `this.streamingById = new Map(this.streamingById).set(...)` 整体赋值触发响应式更新。
**备选**:
- 用并行 `@State` 数组 `streamingMessageIds: string[]` + `streamingContents: Record<string,string>`:可工作但要维护两套同步,易出 bug。
- 把 SSE 事件下沉到 `OpenCodeCore` 内聚成 `MessageStreamController`:改动面大,本变更优先解决 ChatPage 侧的渲染问题。

### 2. 占位卡片由 SSE 事件驱动创建
**决定**:`message.updated` 携带 `info.id` 时:
- 若 `info.id` 已在 `streamingById` 中 → 仅刷新 `role` / `partTypes` / `time`,按 `info.finish` 决定是否 `isLoading=false`。
- 若 `info.id` 不在 → 在 `messages` 末尾插入新占位卡片,并在 `streamingById` 注册。
**理由**:opencode 后端对 user message、assistant 思考段、tool 段、最终回复都是 `message.updated` 触发的,统一入口可减少分支。
**备选**:
- 在 `sendMessage` 时由前端预占位 "思考中" 卡片:已有,继续保留作为兜底,被 SSE 接管后会被替换或忽略。

### 3. text.delta / message.part.delta 走同一追加函数
**决定**:抽 `appendDeltaToMessage(messageID: string, delta: string)`,`text.delta` 与 `message.part.delta(part.type='text')` 都调它,逻辑:
- 校验 `messageID` 在 `streamingById` 中,否则忽略(异常事件,记日志)。
- `content += delta` 后整体赋值 `@State messages` 与 `streamingById`。
**理由**:两个事件类型语义等价,合并可减少重复代码,且与 ArkUI 的响应式更新规则一致(必须整体赋值)。
**备选**:
- 各自独立处理:导致逻辑分叉,后续要补 `message.part.updated` 时容易遗漏。

### 4. user message id 替换走"先占位后替换"
**决定**:`sendMessage` 中先插入 `id: userMsgId = "user-${ts}"` 占位,等 `message.updated(role=user,info.id=realId)` 到达时,找到 `id === userMsgId` 的卡片,`id` 与 `msgId` 同步改为 `realId`,不重建卡片。
**理由**:opencode 后端对 user message 的真实 id 在 SSE 里回传是稳定协议;前端占位 + 替换避免了在等待真实 id 期间显示"空 id"或不显示。
**备选**:
- 不占位、等 `message.updated` 来了再插入:会引入可感知的延迟,与"立即看到自己消息"的产品期望冲突。

### 5. HTTP 响应兜底/补齐的判定
**决定**:`sendMessagePersistent` 回调里检查"是否已有任意 `streamingById` 的 assistant 卡片":
- 若无 → 视为 SSE 不可用,直接把 `response` 作为单条 assistant 卡片插入,`isLoading=false`。
- 若有 → 检查 `response.info.id`:
  - 在 `streamingById` 中 → 跳过(`SSE 路径已交付`)。
  - 不在但 `info.time.created > lastCachedMsgTime` → 追加到末尾(走"刷不到的中段"兜底)。
- 任意情况下,清掉"思考中"占位(`loading-${ts}`)。
**理由**:opencode HTTP 响应通常只回最后一条 message,但不排除极端情况下 SSE 漏推某条,用 `time.created` 判定可补齐"漏推"。

### 6. `finalizeStreamingMessage` 仅清占位、不动其他卡片
**决定**:把现有 `m.id !== this.streamingMessageId` 的过滤改为:`m.id.startsWith('loading-')` 或 `m.id.startsWith('user-')` 且 SSE 后续推送中**未出现**对应真实 id 的卡片才删除。
**理由**:占位 id 命名空间与真实 id(后端 UUID)不会冲突,可安全用前缀判断。
**备选**:
- 引入 `pendingPlaceholderIds: Set<string>` 显式记录本轮插入的占位,收口时按 set 删除:更显式,但增加一个状态字段。

### 7. SSE 默认开启 + AboutPage 开关
**决定**:`OpenCodeCore.SSE_ENABLED = true`(默认),AboutPage 新增 `Toggle({ isOn: $$sseEnabled })` 绑定 `@StorageLink('sseEnabled')`;`EntryAbility.onCreate` 启动时从 `StorageLink` 同步到 `OpenCodeCore.SSE_ENABLED`。
**理由**:默认开启 = 让用户立即看到新链路;开关 = 提供回退路径;`StorageLink` 跨页同步最稳定。
**备选**:
- 仅在 ChatPage 启动时 `setSseEnabled(this.sseEnabled)`:开关只影响单页,行为不一致。

### 8. 性能:`scrollToBottom` 限频
**决定**:`appendDeltaToMessage` 内仅在 `messages.length` 变化时 `scrollToBottom`;纯 delta 追加不滚动,避免每次 SSE 事件都强制滚动造成卡顿。
**理由**:opencode web 在快速模型下可达每秒上百次 `text.delta`,全量滚动会与打字体验冲突。
**备选**:
- 用 `requestAnimationFrame` 节流:ArkTS 没有 RAF 原语,`setTimeout(_, 16)` 近似实现,但与 `onScroll` 事件冲突,会卡顿。

## Risks / Trade-offs

- [R1: `@State Map` 整体赋值触发整个组件重建] → 仅在变更时整体赋值,且赋值前用 `new Map(prev)` 构造新引用,避免被 ArkUI 内部浅比较优化掉。
- [R2: 同一 messageID 在 SSE 断线重连后收到重复事件] → `streamingById` 用 `id` 命中 + `appendDeltaToMessage` 幂等(纯 `+=` 不可幂等),需要在 `dispatchSseEvent` 中对 `messageID` 做去重(仅当与上次 `text.delta.messageID` 相同且未经历 `session.idle` 时忽略);记录一个 `lastDeltaMessageID` 简单去重即可。
- [R3: `session.idle` 提前到达,后续 SSE 消息被丢弃] → 收尾后清空 `streamingById` 与 `pendingPlaceholderIds`,但保留 `messages` 中已交付的卡片。
- [R4: 关闭 SSE 后,AboutPage 开关与 `OpenCodeCore.SSE_ENABLED` 同步延迟] → `EntryAbility.onCreate` 启动时强制同步一次,运行期由 ChatPage.aboutToAppear 同步一次。
- [R5: 旧"非 SSE 路径"(HTTP 一次性)的兼容] → 不删除,`SSE_ENABLED=false` 时走 `sendMessagePersistent` 一次性回调,渲染端按"已有 HTTP 响应 + 无 SSE 卡片"路径处理。
- [R6: 跨页残留 `streamingById`] → `aboutToDisappear` 显式清空,避免下一次进入会话误渲染。

## Migration Plan

1. 提交 `OpenCodeCore.SSE_ENABLED` 改为 `true` 与同步逻辑(可控灰度:先在 `EntryAbility` 写一个临时关闭入口,观察 1 个版本再放开)。
2. 提交 `ChatPage` 重构(`Map<messageID,StreamState>` + `appendDeltaToMessage`),与 `sendMessagePersistent` 回调的兜底/补齐逻辑。
3. 提交 AboutPage 的"实时流式"开关。
4. 验证流程:发送一条带工具调用的消息,确认中间 3~5 条卡片依次出现并实时刷新;发送一条简单消息,确认 HTTP 兜底路径仍可用;关闭开关,确认降级到原行为。
5. 回滚:AboutPage 关闭"实时流式"即可;不需要数据迁移。

## Open Questions

- `message.part.updated`(`part.type` 不一定是 text,可能是 tool / reasoning / step-start / step-finish)是否需要在本变更中可视化?目前 `ChatViewModel.formatMessage` 已经能渲染这些 part,但 SSE 没有逐 part 的 delta,只能整段刷新。**建议本变更先按 messageID 持有,不细化 part**;后续若要做"工具调用实时进度"再补 `message.part.updated`。
- `permission.updated` 触发的"工具审批"提示,本变更不重构,但要确认 `pendingPermission` 不会因 `Map` 改造被打断。已确认:`PendingPermission` 在 ChatPage 顶层 state,与 `messages` 独立。
- `text.delta` 与 `message.part.delta` 哪个更优先?目前实现里 `text.delta` 先到,但不同版本 opencode web 可能只推其中一个。本变更在 `appendDeltaToMessage` 内统一处理,无需分优先级。
