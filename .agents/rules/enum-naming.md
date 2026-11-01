# 枚举值命名规则

- **状态/分类枚举**的值使用 `snake_case`，例如 `CouncilParticipantRole.plot_architect`、`AiMessageType.chapter_content`、`MapEditorMode.draw_rect`。
- **表单字段枚举**（实现 `FieldSchema` 接口的枚举，如 `AppSettingsFormField`、`AiProviderFormField`、`NovelFormField`、`SubAgentEditFields`、`AgentRuleEditFields`、`MapInspectorLocationFields`）保持 `camelCase`，因为它们代表表单字段标识符，不是状态或分类。
- 判断标准：如果枚举值表示一种**状态、阶段、角色、类型、模式、分类**，使用 `snake_case`；如果枚举值表示**表单字段名**，保持 `camelCase`。
- 新增枚举值时必须遵循此规则；修改已有枚举值时同步更新所有引用和 `.g.dart` 生成文件。
