## 1. Directory Input

- [x] 1.1 在 `SessionDetail.ets` 的目录 `TextInput.onChange` 中移除 `showPathPicker` 条件，改为设置 `showPathPicker = true` 后调用 `schedulePathSearch(v)`
- [x] 1.2 保留 `onFocus` 调用 `schedulePathSearch(this.directory)`，让空输入继续复用现有 `listDirectory('/')` 分支

## 2. Validation

- [x] 2.1 运行 ArkTS 编译或编辑器检查
- [x] 2.2 手动验证新建会话目录输入：非空输入、清空输入、聚焦空输入框、选择搜索结果、无后端手动输入
- [x] 2.3 手动验证软键盘打开时目录建议不被键盘遮挡
