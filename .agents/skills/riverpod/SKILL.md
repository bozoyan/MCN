---
name: riverpod
description: |
  Riverpod — 声明式、可组合、可测试的状态管理库。涵盖 Provider 声明、Ref 交互、autoDispose、family、mutations、offline persistence、retry、testing、select、overrides、scoping 等全部概念与最佳实践。
  Use this skill when the user asks about ANY Riverpod topic — providers, refs, consumers, containers, auto-dispose, family, mutations, offline, retry, observers, overrides, scoping, testing, select, eager initialization, pull-to-refresh, cancel, migration from Provider, FAQ, or best practices.
---

# Riverpod — 索引

## 快速开始

| 场景 | 文档 |
|---|---|
| FAQ & Do/Don't | [guides/faq.md](guides/faq.md) |

---

## 核心概念 (Core Concepts)

| 概念 | 文档 | 说明 |
|---|---|---|
| Providers | [refs/providers.md](refs/providers.md) | Provider 6 种变体、声明方式、Notifier 规则 |
| Consumers | [refs/consumers.md](refs/consumers.md) | Consumer / ConsumerWidget / ConsumerStatefulWidget |
| Containers | [refs/containers.md](refs/containers.md) | ProviderScope / ProviderContainer，状态在哪里 |
| Refs | [refs/refs.md](refs/refs.md) | watch / read / listen / invalidate / refresh / onDispose / onCancel |
| Auto-dispose | [refs/auto_dispose.md](refs/auto_dispose.md) | keepAlive / onDispose / 自动释放 |
| Family | [refs/family.md](refs/family.md) | 按参数缓存、参数化 Provider |
| Mutations (experimental) | [refs/mutations.md](refs/mutations.md) | Mutation / MutationIdle/Pending/Success/Error |
| Offline persistence (experimental) | [refs/offline.md](refs/offline.md) | Storage / persist / JsonPersist / destroyKey |
| Retry | [refs/retry.md](refs/retry.md) | 自动重试、自定义 retry 函数、全局/按 Provider |
| Observers | [refs/observers.md](refs/observers.md) | ProviderObserver / didUpdateProvider / 命名 |
| Overrides | [refs/overrides.md](refs/overrides.md) | overrideWith / overrideWithValue / Family override |
| Scoping | [refs/scoping.md](refs/scoping.md) | 子树中改变 Provider 行为 / dependencies |

---

## 指南 (Guides)

| 指南 | 文档 | 说明 |
|---|---|---|
| Testing | [guides/testing.md](guides/testing.md) | ProviderContainer.test / widget tests / mocking |
| Select (减少重建) | [guides/select.md](guides/select.md) | provider.select / selectAsync |
| Eager initialization | [guides/eager_initialization.md](guides/eager_initialization.md) | 启动时预加载 Provider |
| Pull-to-refresh | [guides/pull_to_refresh.md](guides/pull_to_refresh.md) | RefreshIndicator + ref.refresh |
| Cancel / Debounce | [guides/cancel.md](guides/cancel.md) | onDispose + autoDispose 取消请求 |

---

## 参考信息

- **官方文档**: https://riverpod.dev
- **源码 (pub cache)**: `~/.pub-cache/git/riverpod-*/packages/`
- **本项目依赖**: `flutter_riverpod: ^3.3.1`, `riverpod_annotation: ^4.0.2`
