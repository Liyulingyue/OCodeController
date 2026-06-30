## ADDED Requirements

### Requirement: 对话页使用压缩模式避让键盘

系统 MUST 在对话页显示期间使用 `KeyboardAvoidMode.RESIZE`，使软键盘弹出时压缩页面可用高度，而不是整体上抬页面。

#### Scenario: 进入对话页
- **当** 用户进入 `ChatPage`
- **则** 当前 UIContext 的键盘避让模式设置为 `KeyboardAvoidMode.RESIZE`

#### Scenario: 离开对话页
- **当** 用户离开 `ChatPage`
- **则** 当前 UIContext 的键盘避让模式恢复为 `KeyboardAvoidMode.OFFSET`

### Requirement: 标题栏在键盘弹出时保持固定

系统 MUST 在软键盘弹出时保持标题栏固定在屏幕顶部，不随页面整体上抬。

#### Scenario: 键盘弹出
- **当** 用户点击输入框唤起软键盘时
- **则** 标题栏保持在页面顶部可见
- **并且** 消息列表区域被压缩以适配剩余高度

### Requirement: 输入框在键盘弹出时保持可见

系统 MUST 在软键盘弹出时保持输入框区域可见。

#### Scenario: 键盘弹出后输入框可见
- **当** 软键盘弹出时
- **则** 底部输入栏位于压缩后页面的底部
- **并且** 用户可以正常输入文字
