## ADDED Requirements

### Requirement: 多 messageID 并行持有与增量更新
前端 MUST 支持同时持有多个 assistant message 的流式状态,按 messageID 独立追加 `text.delta` / `message.part.delta`,新 message 到达时 MUST 在 `messages` 列表中创建占位卡片。

#### Scenario: 思考/工具/回复三段式到达
- **WHEN** 用户发送一条消息后,opencode web 通过 SSE 依次推送 `message.updated(role=assistant,id=m1)`、`text.delta(messageID=m1,delta="…")`、`message.updated(role=assistant,id=m2)`、`text.delta(messageID=m2,delta="…")`、`message.updated(role=assistant,id=m3)`、`text.delta(messageID=m3,delta="…")`
- **THEN** `messages` 列表依次新增 m1、m2、m3 三个占位卡片,每张卡片按各自 `text.delta` 实时刷新 `content`
- **AND** 三张卡片互不覆盖,后到的 `text.delta` 不会清空先到卡片的文本

#### Scenario: 同一 messageID 连续多个 delta
- **WHEN** 同一 `messageID` 在毫秒级连续收到 10 个 `text.delta` 事件
- **THEN** 该 message 卡片的 `content` 累加 10 个 delta,期间不应触发整张卡片重建
- **AND** `scrollToBottom` 仅在 `messages.length` 变化或当前在底部时调用

#### Scenario: 收到 message.part.delta(无顶层 text.delta 的旧协议)
- **WHEN** opencode web 推送 `message.part.delta` 而非 `text.delta`,且 `part.type === 'text'`
- **THEN** 按相同规则把 `part.text` 追加到该 messageID 的 `content`

### Requirement: assistant message 完成判定
前端 MUST 在收到 `message.updated(info.finish !== '')` 或 `session.idle` 时,把对应 message 的 `isLoading` 置为 `false`。

#### Scenario: 单 message 完成后被关闭
- **WHEN** 收到 `message.updated` 且 `info.id` 命中某张正在 loading 的卡片、`info.finish` 不为空
- **THEN** 该卡片的 `isLoading` 置 `false`
- **AND** `isLoading`(按钮的全局 loading)只在 `session.idle` 到达时统一置 `false`

#### Scenario: session.idle 兜底关闭
- **WHEN** 收到 `session.idle` 且仍有卡片处于 `isLoading === true`
- **THEN** 把所有 `isLoading === true` 的卡片统一置 `false`
- **AND** 触发"最终收口":把"思考中"占位的发送按钮恢复为"发送"

### Requirement: user 消息的真实 id 替换
前端 MUST 在收到 SSE 推送的 `message.updated(role=user)` 时,用后端返回的真实 id 替换前端占位 id(`user-${ts}`)。

#### Scenario: 发送后 200ms 内收到后端回执
- **WHEN** `sendMessage` 已经把 `userMsgId = "user-1717000000000"` 插入 `messages`,随后 SSE 推送 `message.updated(role=user,info.id="msg_real_001")`
- **THEN** 找到 `id === "user-1717000000000"` 的卡片,将其 `id` 与 `msgId` 字段更新为 `"msg_real_001"`
- **AND** 不新增重复卡片,不改 `role` 与 `content`

#### Scenario: 没有收到 user 回执(协议变体)
- **WHEN** 后端未推送 `message.updated(role=user)`
- **THEN** 保留前端占位 id,不影响后续分页/缓存(后续分页由真实后端 id 主导)

### Requirement: HTTP 与 SSE 双链路收口
`sendMessagePersistent` 的 HTTP 响应 MUST 仅在 SSE 尚未交付任何 assistant message 时,才把响应体作为兜底插入;否则 MUST 只追加"比 `lastCachedMsgTime` 新"的消息,并在 `session.idle` 到达时清除"思考中"占位。

#### Scenario: SSE 先交付,HTTP 响应到达
- **WHEN** SSE 已经把 m1、m2、m3 全部交付(每条都收到 `message.updated` + 至少一个 `text.delta` + `finish`),随后 `sendMessagePersistent` 的 HTTP 200 响应到达
- **THEN** 不再插入 HTTP 响应中的 message 实体
- **AND** 仅当响应中的 `info.time.created > lastCachedMsgTime` 时,按现有逻辑追加并刷新 `lastMsgCursor`

#### Scenario: SSE 未交付,HTTP 兜底
- **WHEN** 在 `session.idle` 到达前 SSE 一直没有 `text.delta`,且 `sendMessagePersistent` 的 HTTP 200 响应到达
- **THEN** 把响应中的 message 插入 `messages` 末尾,`isLoading=false`
- **AND** 把"思考中"占位卡片移除

#### Scenario: SSE 出现但仅交付部分,HTTP 补齐
- **WHEN** SSE 交付了 m1,m2 仍在流式中,HTTP 响应同时到达
- **THEN** 不重复插入 m1
- **AND** 若 HTTP 响应 `info.id === m2.id`,则不重复插入;否则按 `lastCachedMsgTime` 判定追加

### Requirement: 修复"非当前流式 ID 占位被误删"
`finalizeStreamingMessage` MUST 仅清除"前端自己插入的占位 id,且没有对应 SSE 推送"的占位,不得删除"非 `streamingMessageId` 但合法的 message 卡片"。

#### Scenario: 多条 message 收尾
- **WHEN** `session.idle` 到达,`messages` 包含 m1、m2、m3 三张已交付的卡片,且仍有一张 `loading-${ts}` 占位
- **THEN** 仅删除 `loading-${ts}` 占位卡片
- **AND** m1、m2、m3 全部保留

#### Scenario: 单条流式收尾
- **WHEN** 历史上只发过一条 message,且 SSE 仅交付了 m1,`streamingMessageId === m1.id`
- **THEN** m1 的 `isLoading` 置 `false`,无其他卡片被删除

### Requirement: SSE 默认启用与可关闭
`OpenCodeCore.SSE_ENABLED` MUST 默认 `true`,并 MUST 通过 `StorageLink('sseEnabled')` 与 AboutPage 开关保持同步。

#### Scenario: 首次安装启动
- **WHEN** 用户首次启动 APP 且未配置过 `sseEnabled`
- **THEN** `SSE_ENABLED` 取默认值 `true`,`ChatPage` 进入时按 SSE 链路工作

#### Scenario: 用户在 AboutPage 关闭"实时流式"
- **WHEN** 用户在 AboutPage 把"实时流式"开关置为 `false`
- **THEN** `SSE_ENABLED` 立即同步为 `false`
- **AND** 后续 `sendMessage` 不再启动 `startSse`,回退到 HTTP 一次性回调路径
- **AND** 已有的 SSE 连接被 `stopSse()` 关闭

#### Scenario: 后端不支持 `/event` 时降级
- **WHEN** `startSse` 因网络或 4xx 失败
- **THEN** 不阻塞用户:HTTP 路径继续工作,SSE 失败仅打日志
- **AND** 仍展示"思考中"占位,确保用户能看到进度

### Requirement: 流式状态可观测
前端 MUST 在 `message.updated` / `text.delta` / `session.idle` / `finalizeStreamingMessage` 关键路径输出可定位的日志(包含 `messageID`、`role`、`contentLength`)。

#### Scenario: 排查"消息没出来"
- **WHEN** 现场反馈某条消息始终不显示
- **THEN** 日志中能找到:`send start → message.updated(id=m1) → text.delta(id=m1,len=N) × k → message.updated(id=m1, finish="stop") → session.idle` 的完整序列
- **AND** 若中间断链,日志中能直接定位到缺失的事件类型或 messageID
