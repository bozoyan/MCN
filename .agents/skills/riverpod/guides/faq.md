# FAQ & Do/Don't

## FAQ

### ref.refresh vs ref.invalidate

`refresh` = `invalidate` + `read`。不关心新值用 `invalidate`，需要结果用 `refresh`。

### 为什么 Ref 和 WidgetRef 没有共享接口？

有意设计，避免写出同时依赖两者的错误代码。业务逻辑放 Notifier，UI 只调用 notifier 方法。

### 为什么用 ConsumerWidget 而不是 StatelessWidget？

BuildContext 不支持 `ref.listen` 和自动释放。ConsumerWidget 提供的 WidgetRef 解决了这些问题。

### hooks_riverpod 为什么不导出 flutter_hooks？

各自独立版本号，一方 break 不影响另一方。

### 如何重置所有 Provider？

没有内置 API（反模式）。让 Provider watch 一个 user provider，登出时那个 provider 变化，依赖者自动重建。

### ref 在 unmount 后使用不安全

任何 `await` 后检查 `if (!context.mounted) return;`（与 BuildContext 相同）。

### `@riverpod` 报 InvalidTypeException

riverpod_generator 无法对返回类型定义在 Drift 生成文件（`.g.dart` part file）中的 provider 生成代码。例如 `AiProvider` 定义在 `app_database.g.dart` 中。

**症状**：`build_runner` 报 `InvalidTypeException: The type is invalid and cannot be converted to code.`

**解决**：将 `@riverpod` 改为手动 `Provider`/`Provider.family`：

```dart
// ❌ 不能这样写
@riverpod
AiProvider? imageGenerationConfig(Ref ref) { ... }

// ✅ 改为手写
final imageGenerationConfigProvider = Provider.autoDispose<AiProvider?>((ref) { ... });
```

如果原 provider 有命名参数（family），改用 `Provider.family` + record 类型，调用侧加一层括号：

```dart
// ❌ 原来
@riverpod
AiProvider? currentAiConfig(Ref ref, {String? providerId, String? model}) { ... }

// ✅ 手写 family
final currentAiConfigProvider = Provider.family
    .autoDispose<AiProvider?, ({String? providerId, String? model})>((ref, args) { ... });

// 调用侧: currentAiConfigProvider((providerId: ..., model: ...))
```

## Do / Don't

| | 说明 |
|---|---|
| ❌ 不要在 Widget 中初始化 Provider | Provider 应自初始化。如需用户触发，在事件中做。 |
| ❌ 不要在 Provider 中存 ephemeral state | 选中项、Tab、表单状态用 hooks 或局部 state。 |
| ❌ 不要在 build 中做副作用 | Provider 是"读"操作。提交等"写"操作用 mutations。 |
| ✅ 优先 statically known Provider | `ref.watch(provider)` 中 provider 是顶层 final。 |
| ❌ 不要动态创建 Provider | 声明为顶层 final 变量。 |
| ✅ 启用 riverpod_lint | `analysis_options.yaml` 中配置。 |
| ❌ 不要在 `@riverpod`/`@Riverpod` 中返回 Drift 生成的类型 | 如 `AiProvider`（定义在 `app_database.g.dart` 等 part file 中），会导致 `InvalidTypeException: The type is invalid and cannot be converted to code.`。改用手动 `Provider` / `Provider.family` 声明。 |
