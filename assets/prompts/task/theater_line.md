{{#scene_description}}
## 场景描述
{{scene_description}}
{{/scene_description}}

{{#prior_lines}}
## 之前的对白
{{prior_lines}}
{{/prior_lines}}

{{#participant_name}}
## 当前发言角色：{{participant_name}}
{{/participant_name}}
{{#participant_character_id}}
角色ID：{{participant_character_id}}
{{/participant_character_id}}

{{#round}}
轮次：第 {{round}} 轮
{{/round}}

## 表演要求
- 若当前场景、角色资料或之前对白不足以支撑本轮表演，先调用 Read、Glob、Grep、GraphSearch、WebSearch 或 WebFetch 获取事实；工具完成后再输出表演内容
- 工具结果只作为角色视角内可用的信息来源，不要在最终表演中解释工具调用过程
- 以{{participant_name}}的身份和语气表演这一轮内容
- 每个角色的语气、用词、句式须有辨识度
- 如果场景中有多个角色在场，注意他们的空间关系和互动
- 对白之间可插入必要的动作、表情、走位描写
- 对话推进情节、揭示信息或制造冲突
- 群像反应差异化：同一事件对不同角色影响不同
- 完成必要的工具查询后，直接输出本轮表演内容
