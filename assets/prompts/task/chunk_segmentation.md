将以下小说文本切分为适合 embedding 检索的语义块。

{{#text}}
## 原文
{{text}}
{{/text}}

{{#target_chunk_chars}}
目标块大小：{{target_chunk_chars}} 字符
{{/target_chunk_chars}}

{{#max_chunk_chars}}
最大块大小：{{max_chunk_chars}} 字符
{{/max_chunk_chars}}

{{#overlap_chars}}
重叠字符数：{{overlap_chars}} 字符
{{/overlap_chars}}

## 切分规则
1. 优先在自然段落边界（双换行）处切分
2. 段落过长时在句号、问号、感叹号处切分
3. 保持对话完整性：同一轮对话不跨块
4. 保持场景完整性：同一场景尽量在一个块内
5. 章末钩子/悬念与下文粘连在同一块
6. 每个块应有独立可读性（包含足够的上下文理解所需的信息）

## 输出格式
每个语义块用 "---" 分隔，块前标注序号：

块 1：
[内容...]

---

块 2：
[内容...]