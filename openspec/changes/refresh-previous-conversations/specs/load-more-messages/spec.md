## ADDED Requirements

### Requirement: 滚动到顶部加载历史消息

系统 MUST 允许用户通过滚动到消息列表顶部来加载更早的消息。

#### Scenario: 用户滚动到顶部且存在更早消息
- **当** 用户滚动到消息列表顶部且 `historyCursor` 非空且 `isLoadingHistory` 为 `false` 时
- **则** 系统使用 `loadHistoryPage`（`cursor` 设置为 `historyCursor`）获取上一页消息
- **并且** 在请求期间设置 `isLoadingHistory = true`
- **并且** 将加载的消息添加到现有 `messages` 数组的头部
- **并且** 不自动滚动到底部

#### Scenario: 用户滚动到顶部但无更多历史
- **当** 用户滚动到顶部但 `historyCursor` 为空时
- **则** 系统不发起请求
- **并且** 显示一个不显眼的"没有更多消息"提示

#### Scenario: 正在加载中
- **当** 用户滚动到顶部但 `isLoadingHistory` 为 `true` 时
- **则** 系统不发起新的请求

#### Scenario: 请求完成且还有更多历史
- **当** 请求完成且 `cursor.previous` 非空时
- **则** 系统将 `historyCursor` 更新为新的 `cursor.previous` 值
- **并且** 设置 `isLoadingHistory = false`

#### Scenario: 请求完成且无更多历史
- **当** 请求完成且 `cursor.previous` 为空或 undefined 时
- **则** 系统设置 `historyCursor = ''`
- **并且** 设置 `isLoadingHistory = false`

#### Scenario: 请求遇到错误
- **当** 由于网络错误或非 200 响应导致请求失败时
- **则** 系统设置 `isLoadingHistory = false`
- **并且** 记录错误日志而不崩溃

### Requirement: 加载指示器

系统 MUST 在获取历史消息时在消息列表顶部显示加载指示器。

#### Scenario: 加载过程中加载指示器可见
- **当** `isLoadingHistory` 为 `true` 时
- **则** 在滚动区域中第一条消息上方显示加载指示器
- **当** 请求完成或失败时
- **则** 隐藏加载指示器

### Requirement: 页面加载时的初始状态

系统 MUST 根据页面初始加载结果初始化历史消息加载状态。

#### Scenario: 初始加载返回 cursor.previous
- **当** 初始 `loadHistoryPage` 调用返回 `cursor.previous` 值时
- **则** 将 `historyCursor` 设置为该值

#### Scenario: 初始加载无 cursor.previous
- **当** 初始 `loadHistoryPage` 调用没有返回 `cursor.previous` 值（空或 undefined）时
- **则** 将 `historyCursor` 设置为空字符串
