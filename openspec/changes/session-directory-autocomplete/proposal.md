## Why

新建会话时，工作目录输入框已经有目录下拉组件，但输入过程中不会主动打开并刷新建议。用户只能先聚焦输入框再依赖已有下拉，路径容易手输错误。

## What Changes

- 用户输入工作目录时，自动展开目录建议并复用现有 400ms 防抖搜索
- 输入为空或聚焦空输入框时，复用现有空查询分支列出根目录，并保留最近使用路径
- 用户选择建议项后，填充路径、收起下拉，并继续写入最近使用记录

## Impact

- 修改文件：`entry/src/main/ets/pages/SessionDetail.ets`
- 复用组件：`PathAutocomplete.ets`
- 复用逻辑：`SessionDetailViewModel.schedulePathSearch()`、`listDirectory()`、`searchPaths()`
- 复用接口：`/file`、`/find/file`
