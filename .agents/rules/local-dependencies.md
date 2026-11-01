# 本地依赖规则

- 遇到第三方库接入、兼容层、SDK 行为差异或底层报错时，先检查本项目的本地依赖源码，不要默认以 pub.dev 已发布版本或通用文档为准。
- 当前项目的 AI 相关依赖存在本地覆盖，来源以 `pubspec.yaml` 的 `dependency_overrides` 为准；排查 `Genkit`、`genkit_openai`、`genkit_google_genai`、`genkit_anthropic`、`schemantic`、`anthropic_sdk_dart` 行为时，优先阅读对应本地项目源码。
- 当前项目内置规则文件 `.agents/rules/form.md`、`.agents/rules/design-system.md` 与本地模块 `lib/third/form` 也属于"本地依赖上下文"的一部分；涉及表单和设计系统改动时，先看这些本地实现和规则，再决定方案。
- 如果本地 path 依赖源码与缓存依赖、公开文档或既有认知不一致，以当前实际参与构建的本地源码为准，并在说明中明确指出差异来自本地覆盖。
