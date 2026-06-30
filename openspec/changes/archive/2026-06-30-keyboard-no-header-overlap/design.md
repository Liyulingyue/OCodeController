## 背景

`ChatPage.ets` 的页面结构已经是固定标题栏、中间消息列表、底部输入栏：

```typescript
Column() {
  Row() { ... }                  // 标题栏
  Divider()
  Scroll(...).layoutWeight(1)    // 消息列表
  Column() { Row() { ... } }     // 输入栏
}
.height('100%')
```

问题不需要重搭布局。根因是系统默认 `KeyboardAvoidMode.OFFSET` 会在键盘弹出时上抬 Page 内容，标题栏也被一起推走。

## 文档依据

- `KeyboardAvoidMode.OFFSET` 是默认模式，会把页面上抬以避让键盘。
- `KeyboardAvoidMode.RESIZE` 会压缩 Page 大小，百分比高度和 `layoutWeight(1)` 内容跟随压缩。
- `expandSafeArea([SafeAreaType.KEYBOARD])` 的语义是组件不避让键盘；在 `RESIZE` 模式下，`expandSafeArea([SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])` 不生效。

## 决策

### 1. 对话页使用 RESIZE 模式

在 `ChatPage.aboutToAppear()` 中设置：

```typescript
this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
```

这样软键盘出现时压缩页面高度，标题栏仍在顶部，`Scroll.layoutWeight(1)` 自动缩小，底部输入栏保持在键盘上方。

### 2. 离开对话页恢复默认模式

在 `ChatPage.aboutToDisappear()` 中恢复：

```typescript
this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
```

这把影响限制在对话页，不改变其他页面的默认键盘行为。

### 3. 不使用输入栏 KEYBOARD safe area

不给输入栏 `Row` 添加 `expandSafeArea([SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])`。该 API 表示不避让键盘，和“输入栏上移可见”的目标相反；在本方案的 `RESIZE` 模式下它也不会生效。

## 风险 / 权衡

- 需要真机或模拟器唤起软键盘验证视觉效果；静态构建只能验证 API 和 ArkTS 类型正确。
