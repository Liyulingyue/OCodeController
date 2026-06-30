## 为什么

对话页唤起软键盘时，默认 `KeyboardAvoidMode.OFFSET` 会为露出光标把页面整体上抬，标题栏也会跟着离开屏幕顶部。

官方文档给出的固定顶部控件方案是使用 `KeyboardAvoidMode.RESIZE` 压缩页面高度，让中间弹性内容缩小，而不是把整个页面上抬。

## 改动内容

- 在 `ChatPage.ets` 显示时将当前 UIContext 的键盘避让模式设为 `KeyboardAvoidMode.RESIZE`
- 在离开对话页时恢复官方默认的 `KeyboardAvoidMode.OFFSET`
- 保留现有 `Column + Scroll.layoutWeight(1) + 输入栏` 结构，不给输入栏添加 `expandSafeArea([SafeAreaType.KEYBOARD])`

## 能力

### 新增能力

- `keyboard-avoid-header`：在对话页面，软键盘唤起时压缩消息列表区域，标题栏保持在屏幕顶部，输入栏保持可见。

### 变更能力

- （无）

## 影响范围

- **修改的文件**：`entry/src/main/ets/pages/ChatPage.ets`
- **行为变更**：仅对话页显示期间使用压缩模式避让键盘，离开后恢复默认上抬模式
