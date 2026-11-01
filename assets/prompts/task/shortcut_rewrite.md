{{#novel_name}}# {{novel_name}}{{/novel_name}}
{{#chapter_title}}# {{chapter_title}}{{/chapter_title}}

{{#outline}}
## 大纲参考
{{outline}}
{{/outline}}

{{#content}}
## 原文
{{content}}
{{/content}}

## 润色要求
### 语言层面
- 消除冗余修饰和重复用词
- 用精准动词替代笼统表达
- 调整句式长短制造呼吸感
- 变化句子开头方式

### 去AI味层面
若可调用 AgentSkill，从 **AgentSkills** 按 when_to_use 匹配去AI味或润色类技能并加载完整规则；否则遵循以下基础约束：删废话、变节奏、避免模板化列举与 AI 腔连接词。
## 约束
- 不改变情节走向、人物行为和既定事实
- 不添加原文没有的信息
- 不删除关键情节点
- 保持原始叙事视角

## 输出
直接输出润色后的正文，不附说明。