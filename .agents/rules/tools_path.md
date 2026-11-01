# Read 工具规则

- **所有持久化实体统一返回自身 `id`，与寻址方式无关。** Read 详情、listing 条目、文件夹自身及子条目、Create 返回均携带真实 ID；name-path 资源也不例外。`path` 用于工具寻址，`id` 用于稳定身份和业务引用，不能相互替代。纯目录索引和字段原值不要求附加实体 ID。
- **路径占位符使用资源专名，关联字段保留明确名称。** 例如 `scenes/{scene_id}/elements/{element_id}`，场次对象与元素对象自身都用 `id`；关联字段和查询作用域仍使用 `scene_id`、`character_id`、`work_id` 等名称，不得一并改成 `id`。允许携带既有身份的数组项同样使用 `id`。
- **outlines、canvas 保留 name-path；lore、materials 保留名称目录层级。** 无论路径中是否使用名称，都返回自身 `id`。outline beats、canvas nodes／edges 的身份和子资源定位独立于父资源的名称寻址。
- **skills、items、factions、creatures 使用 ID path。** 名称用于展示与 search 查询，不作为地址或旧地址别名。按 ID 加载后检查类型与有效状态；列表、Create、字段预览和新 working change 使用同一 ID 路径，重命名不改变地址。
- **field-specific 路径必须严格返回该字段的原始值。** 例如 `/outlines/<name>/content` 必须只返回 `OutlineDraft.content` 的原始文本，不得返回包含标题、timeline beats 等其他字段的组合内容（如 `toDocumentContent()`）。
- 每个字段的返回值必须与字段名严格对应——`content` 键的值必须是纯正文内容，`title` 键的值必须是纯标题，依此类推。
- 禁止在单个字段的返回值中打包其他字段的信息。如果 AI 需要多个字段，应通过全文档读取或多次 field-specific 读取获取。
