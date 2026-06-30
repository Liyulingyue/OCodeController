## Context

`SessionDetail.ets` 的目录输入框当前只在 `showPathPicker` 已经为 `true` 时才会响应 `onChange` 搜索：

```typescript
.onChange(v => {
  this.directory = v;
  if (this.showPathPicker) {
    this.schedulePathSearch(v);
  }
})
```

这让输入行为依赖“下拉是否已经打开”，而不是依赖“用户是否正在输入目录”。

## Decision

在 `TextInput.onChange` 中直接打开下拉并调用 `schedulePathSearch(v)`。`schedulePathSearch()` 已经处理空输入和 `/`：它会立即调用 `listDirectory('/')`，不需要在页面层再加一份空值分支。

保留 `onFocus` 的现有职责：打开下拉并按当前 `directory` 调用 `schedulePathSearch()`。这样空输入、已有内容、输入中更新都走同一条搜索入口。

## Non-Goals

- 不改 `PathAutocomplete` 的布局和排序
- 不改 `SessionDetailViewModel` 的搜索算法
- 不新增目录选择弹窗、键盘快捷键或多选交互

## Validation

- `openspec validate session-directory-autocomplete --strict`
- ArkTS 编译或编辑器检查
- 手动验证：非空输入、清空输入、聚焦空输入框、选择搜索结果、无后端时继续手动输入
