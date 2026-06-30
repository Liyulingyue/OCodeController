## 1. 状态和数据模型添加

- [x] 1.1 向 `ChatPage` 添加 `@State historyCursor: string = ''`
- [x] 1.2 向 `ChatPage` 添加 `@State isLoadingHistory: boolean = false`

## 2. 滚动到顶部检测

- [x] 2.1 向 `Scroll` 组件添加 `onReachStart` 处理器
- [x] 2.2 添加守卫：仅在 `historyCursor` 非空且 `isLoadingHistory` 为 `false` 时触发

## 3. 加载历史消息方法

- [x] 3.1 向 `ChatPage` 添加 `private async loadPreviousMessages()` 方法，使用 `historyCursor` 和 `order='desc'` 调用 `viewModel.loadHistoryPage`
- [x] 3.2 请求完成后将消息添加到 `this.messages` 头部
- [x] 3.3 将 `historyCursor` 更新为 `cursor.previous || ''`
- [x] 3.4 在 finally 块中设置 `isLoadingHistory = false`

## 4. 滚动行为

- [x] 4.1 加载历史消息后不要调用 `scrollToBottom()`

## 5. 加载指示器 UI

- [x] 5.1 在 `Scroll` 的 `Column` 内部第一个子元素位置添加加载指示器（如 `LoadingProgress`），条件渲染 `isLoadingHistory` 为 `true` 时显示
- [x] 5.2 确保指示器具有固定高度，避免出现/消失时布局跳动

## 6. 初始状态初始化

- [x] 6.1 在 `loadHistory` 中初始 `loadHistoryPage` 完成后，将 `historyCursor` 设置为 `page.cursor.previous || ''`

## 7. "没有更多消息"提示

- [x] 7.1 当 `historyCursor` 为空且 `messages.length > 0` 且 `isLoadingHistory` 为 `false` 时，在顶部显示不显眼的"没有更多消息"文本
