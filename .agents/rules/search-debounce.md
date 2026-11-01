# 搜索 debounce 规则

- 所有搜索场景都必须 debounce 后再触发实际搜索、过滤、Provider invalidate、数据库查询、网络请求或昂贵计算。
- 输入框文本可以即时更新 UI（例如清除按钮、输入态），但参与结果计算的 query 必须使用 debounced 值。
- Flutter UI 搜索优先使用项目已有 `useDebounced`；如果父组件不是 Hook 组件，优先抽一个小型 Hook 搜索输入组件，不要为了搜索防抖重构整棵复杂状态树。
- 非 Widget 层或确实无法使用 hooks 的场景才使用 `Timer`，并必须在生命周期结束时取消。
- 清空搜索应立即取消未触发的 debounce，并同步清空输入态和结果 query。
