## 1. 实现键盘压缩避让

- [x] 1.1 查阅官方文档，确认 `KeyboardAvoidMode.RESIZE` 是固定顶部控件的合适方案
- [x] 1.2 在 `ChatPage.ets` 中引入 `KeyboardAvoidMode`
- [x] 1.3 在 `aboutToAppear()` 中设置 `KeyboardAvoidMode.RESIZE`
- [x] 1.4 在 `aboutToDisappear()` 中恢复 `KeyboardAvoidMode.OFFSET`
- [x] 1.5 保留现有 `Scroll.layoutWeight(1)` 布局，不添加 `expandSafeArea([SafeAreaType.KEYBOARD])`

## 2. 验证

- [x] 2.1 运行 ArkTS/HarmonyOS 构建检查
- [x] 2.2 真机或模拟器测试：唤起软键盘时标题栏仍在顶部
- [x] 2.3 真机或模拟器测试：输入栏不被软键盘遮挡
