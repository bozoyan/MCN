# Hooks 使用规则

## 基本原则

- Hooks 只管理 **Widget 局部状态**，例如 `TextEditingController`、`FocusNode`、`AnimationController`、弹窗开关、表单临时输入。
- 跨页面共享状态走 Riverpod Provider，不要塞进 hooks。
- 所有 hook 调用必须在 `build` 顶层、稳定顺序调用，禁止放进条件分支、循环、早返回之后的分支路径中。

## Hook 索引

### 基础 Hooks

| Hook | 用途 | 文档 |
|---|---|---|
| `useState` | 创建局部响应式变量 | [useState.md](hooks/useState.md) |
| `useEffect` | 副作用（监听、订阅、定时器），可用 keys 控制重跑 | [useEffect.md](hooks/useEffect.md) |
| `useRef` | 跨 rebuild 保持可变引用，修改不触发重建 | [useRef.md](hooks/useRef.md) |
| `useMemoized` | 缓存复杂对象/函数，只在 keys 变化时重建 | [useMemoized.md](hooks/useMemoized.md) |
| `useCallback` | `useMemoized` 的语法糖，缓存函数 | [useCallback.md](hooks/useCallback.md) |
| `useValueChanged` | 监听值变化并执行回调 | [useValueChanged.md](hooks/useValueChanged.md) |
| `useContext` | 获取当前 `BuildContext` | [useContext.md](hooks/useContext.md) |
| `useSingleTickerProvider` | 创建单次使用的 TickerProvider（内部使用） | [useSingleTickerProvider.md](hooks/useSingleTickerProvider.md) |

### 控制器 Hooks

| Hook | 用途 | 文档 |
|---|---|---|
| `useTextEditingController` | 创建并自动 dispose TextEditingController | [useTextEditingController.md](hooks/useTextEditingController.md) |
| `useFocusNode` | 创建并自动 dispose FocusNode | [useFocusNode.md](hooks/useFocusNode.md) |
| `useScrollController` | 创建并自动 dispose ScrollController | [useScrollController.md](hooks/useScrollController.md) |
| `useFixedExtentScrollController` | 创建并自动 dispose FixedExtentScrollController | [useFixedExtentScrollController.md](hooks/useFixedExtentScrollController.md) |
| `useTabController` | 创建并自动 dispose TabController | [useTabController.md](hooks/useTabController.md) |
| `usePageController` | 创建并自动 dispose PageController | [usePageController.md](hooks/usePageController.md) |
| `useAnimationController` | 创建并管理 AnimationController 生命周期 | [useAnimationController.md](hooks/useAnimationController.md) |
| `useTransformationController` | 创建并管理 TransformationController 生命周期 | [useTransformationController.md](hooks/useTransformationController.md) |
| `useSearchController` | 创建并自动 dispose SearchController | [useSearchController.md](hooks/useSearchController.md) |
| `useWidgetStatesController` | 创建并自动 dispose WidgetStatesController | [useWidgetStatesController.md](hooks/useWidgetStatesController.md) |
| `useExpansionTileController` | ⚠️ 已废弃，请使用 `useExpansibleController` | [useExpansionTileController.md](hooks/useExpansionTileController.md) |
| `useExpansibleController` | 创建并自动 dispose ExpansibleController（替代 useExpansionTileController） | [useExpansibleController.md](hooks/useExpansibleController.md) |
| `useFocusScopeNode` | 创建并自动 dispose FocusScopeNode | [useFocusScopeNode.md](hooks/useFocusScopeNode.md) |
| `useDraggableScrollableController` | 创建并自动 dispose DraggableScrollableController | [useDraggableScrollableController.md](hooks/useDraggableScrollableController.md) |
| `useCarouselController` | 创建并自动 dispose CarouselController | [useCarouselController.md](hooks/useCarouselController.md) |
| `useTreeSliverController` | 创建并自动 dispose TreeSliverController | [useTreeSliverController.md](hooks/useTreeSliverController.md) |
| `useOverlayPortalController` | 创建并自动 dispose OverlayPortalController | [useOverlayPortalController.md](hooks/useOverlayPortalController.md) |
| `useSnapshotController` | 创建并自动 dispose SnapshotController | [useSnapshotController.md](hooks/useSnapshotController.md) |
| `useCupertinoTabController` | 创建并自动 dispose CupertinoTabController | [useCupertinoTabController.md](hooks/useCupertinoTabController.md) |

### 响应式 Hooks

| Hook | 用途 | 文档 |
|---|---|---|
| `useListenable` | 订阅 Listenable 并触发 widget 重建 | [useListenable.md](hooks/useListenable.md) |
| `useListenableSelector` | 类似 useListenable，但只在其结果变化时重建 | [useListenableSelector.md](hooks/useListenableSelector.md) |
| `useValueNotifier` | 创建并自动 dispose ValueNotifier | [useValueNotifier.md](hooks/useValueNotifier.md) |
| `useValueListenable` | 订阅 ValueListenable 并返回其 value，触发重建 | [useValueListenable.md](hooks/useValueListenable.md) |
| `useOnListenableChange` | 监听变化执行回调，**不触发重建**（适合副作用） | [useOnListenableChange.md](hooks/useOnListenableChange.md) |
| `useAnimation` | 订阅 Animation 并返回其值，触发重建 | [useAnimation.md](hooks/useAnimation.md) |

### 异步 Hooks

| Hook | 用途 | 文档 |
|---|---|---|
| `useStream` | 订阅 Stream 并以 AsyncSnapshot 返回状态 | [useStream.md](hooks/useStream.md) |
| `useStreamController` | 创建并自动 dispose StreamController | [useStreamController.md](hooks/useStreamController.md) |
| `useOnStreamChange` | 订阅 Stream 并执行回调，不触发重建 | [useOnStreamChange.md](hooks/useOnStreamChange.md) |
| `useFuture` | 监听 Future 并以 AsyncSnapshot 返回状态 | [useFuture.md](hooks/useFuture.md) |

### 工具 Hooks

| Hook | 用途 | 文档 |
|---|---|---|
| `useDebounced` | 对值做 debounce，返回 debounce 后的值 | [useDebounced.md](hooks/useDebounced.md) |
| `usePrevious` | 返回上一次调用时的值 | [usePrevious.md](hooks/usePrevious.md) |
| `useReducer` | 类似 Redux reducer，管理复杂状态 | [useReducer.md](hooks/useReducer.md) |
| `useIsMounted` | ⚠️ 已废弃，建议用 `context.mounted`（Flutter 3.7+） | [useIsMounted.md](hooks/useIsMounted.md) |
| `useReassemble` | hot reload 时执行回调（仅 debug 模式） | [useReassemble.md](hooks/useReassemble.md) |
| `useAutomaticKeepAlive` | 等效于 AutomaticKeepAlive widget | [useAutomaticKeepAlive.md](hooks/useAutomaticKeepAlive.md) |
| `useAppLifecycleState` | 返回当前 AppLifecycleState，变化时重建 | [useAppLifecycleState.md](hooks/useAppLifecycleState.md) |
| `useOnAppLifecycleStateChange` | 监听应用生命周期变化，不触发重建 | [useOnAppLifecycleStateChange.md](hooks/useOnAppLifecycleStateChange.md) |
| `usePlatformBrightness` | 返回当前平台亮度模式，变化时重建 | [usePlatformBrightness.md](hooks/usePlatformBrightness.md) |
| `useOnPlatformBrightnessChange` | 监听平台亮度变化，不触发重建 | [useOnPlatformBrightnessChange.md](hooks/useOnPlatformBrightnessChange.md) |

## useEffect 规则

- `useEffect` 的依赖列表（keys）必须包含“其变化应触发 effect 重跑”的响应式依赖（props、provider state、hook state 等），不允许漏掉真实触发条件。
- 稳定 ref，或刻意不触发 effect 重跑但需要读取最新值的回调，通过 `useRef` 转发；这属于显式稳定化，不是允许漏依赖。
- 当依赖未变化时 `useEffect` 会跳过重跑，真实触发条件漏写会导致状态不同步。
- `useEffect` 回调返回的函数会在 effect 重跑前或 widget dispose 时执行（cleanup）。
- **例外：不要把「每帧都换新实例的内联闭包/内联对象」放进 keys**。父级（尤其 `HookConsumerWidget`）传下来的内联回调 prop（如 `onRegisterSave: (fn) => ref.value = fn`）每次 build 都是新实例，放进 keys 会让 effect 每帧「cleanup→重跑」。对于「挂载注册、卸载注销」类 effect 这是致命的：flutter_hooks 在 keys 变化时**先跑新 setup、后跑旧 cleanup**，抖动最终停在 cleanup（注销）上，注册值被置空。正确做法是把这类闭包放进 `useRef` 并在 build 顶层刷新，effect 用稳定 keys（通常 `const []`）并通过 ref 转发调用。

```dart
// ✅ 正确：依赖列表包含所有会触发同步的字段
useEffect(() {
  nameController.text = agent.name;
  enabled.value = agent.enabled;
  hasChanges.value = false;
  return null;
}, [agent.id, agent.name, agent.enabled]);

// ❌ 错误：漏掉 agent 的其他字段
useEffect(() {
  nameController.text = agent.name;
  enabled.value = agent.enabled; // enabled 变了但依赖没写
  return null;
}, [agent.id]);
```

## 禁止在 hook init 阶段读取 InheritedWidget

`useEffect`、hook 初始化阶段以及传给 hook 的初始化闭包里，**禁止**读取依赖 inherited widget 的值：

- `context.t(...)`
- `Theme.of(context)`
- `MediaQuery.of(context)`
- `RevericTheme.colorsOf(context)`

这些读取会在 Hook init 阶段触发 `dependOnInheritedWidgetOfExactType` 断言。

**正确做法**：先在 `build` 顶层读取成普通局部变量，再传给 effect/listener：

```dart
Widget build(BuildContext context) {
  final colors = RevericTheme.colorsOf(context);    // ✅ 在 build 顶层读取
  final saveLabel = context.t(LocaleKeys.commonSave); // ✅

  useEffect(() {
    // ❌ 这里不能调用 context.t(...)
    someService.configure(colors.accent); // ✅ 使用已经读取的局部变量
    return null;
  }, [colors]);

  // ...
}
```

## 禁止在 useEffect 中修改外部状态（包括 Riverpod 和父 Widget）

`useEffect` 的回调在 `initHook` 阶段**同步执行**，仍处于 widget `build()` 的生命周期内。此时修改外部状态会导致父 widget 或上游 provider 在 build 过程中收到变更通知，触发 `setState()` 或 `_debugAssertNotificationAllowed` 断言。

**两种典型场景：**

### 1. 禁止修改 Riverpod provider 状态

通过 `ref.read(provider.notifier).method()` 修改 provider 状态会触发 Riverpod 的 `_debugAssertNotificationAllowed` 断言：

```
#0      _UncontrolledProviderScopeState._debugCanModifyProviders
#1      ProviderElement._debugAssertNotificationAllowed
```

```dart
// ❌ 错误：useEffect 内直接修改 provider 状态
useEffect(() {
  ref.read(chatProvider.notifier).addMessage('...');
  return null;
}, [key]);
```

### 2. 禁止调用父 Widget 回调来修改父 Widget 状态

调用父 Widget 传入的回调（如 `onHasChangesChanged`）来修改父 Widget 的 `ValueNotifier` 或 `setState`，同样会在父 Widget 的 build 阶段触发 `markNeedsBuild()`：

```
#0      Element.markNeedsBuild
#6      NovelEditorPage.build.<anonymous closure>
#15     AgentRuleEditPanel.build
```

同一类问题也常见于 **controller listener → `onHasChangesChanged`**（不一定经过 `useEffect`）。外部 controller 编辑面板的完整规避清单见 `.agents/rules/text-input-ime.md`。

```dart
// ❌ 错误：useEffect 内同步调用父 Widget 回调
useEffect(() {
  onHasChangesChanged?.call(form.hasChanged);
  return null;
}, [form.hasChanged]);

// ❌ 错误：useEffect 重置 controller 时同步触发 listener → 父级回调
useEffect(() {
  nameController.text = entity.name; // listener 同步执行
  onHasChangesChanged?.call(true);
  return null;
}, [entity.id]);
```

### 正确做法

用 `addPostFrameCallback` 或 `Future(() { ... })` 推迟修改到当前 build 帧完成后：

```dart
// ✅ 正确：用 addPostFrameCallback 推迟
useEffect(() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    onHasChangesChanged?.call(form.hasChanged);
  });
  return null;
}, [form.hasChanged]);

// ✅ 也正确：用 Future 推迟（适用于 ref.read）
useEffect(() {
  Future(() {
    ref.read(chatProvider.notifier).addMessage('...');
  });
  return null;
}, [key]);

// ✅ 最推荐：在用户交互中修改（如 onPressed）
onPressed: () => onHasChangesChanged?.call(true),
```

## useState / useRef / useMemoized 区分

| Hook | 修改触发重建 | 用途 |
|---|---|---|
| `useState` | ✅ 是 | UI 响应式状态 |
| `useRef` | ❌ 否 | 可变引用（Timer、滚动位置、标志位） |
| `useMemoized` | ❌ 否（keys 不变时） | 缓存计算开销大的对象 |

## 常见场景选择

| 场景 | 推荐 hook |
|---|---|
| 局部开关/计数器/选中项 | `useState` |
| TextField 文本绑定（简单即时 UI，无 form/IME 面板） | `useTextEditingController`；仅当 UI 必须随每键刷新时才 `useValueListenable` |
| 监听 TextEditingController 变化（form 同步、自动保存、dirty） | `useOnListenableChange`（见 `.agents/rules/text-input-ime.md`） |
| 焦点管理 | `useFocusNode` |
| 动画 | `useAnimationController` / `useAnimation` |
| 输入防抖（搜索、校验） | `useDebounced` + `useEffect` |
| 定时器/延迟操作 | `useRef<Timer?>` + `useEffect` |
| 流订阅 | `useStream` / `useFuture` |
| 跨 rebuild 保持引用 | `useRef` |
| 缓存回调 | `useCallback` |

## useOnListenableChange 最佳实践

`useOnListenableChange` 用于监听 `Listenable`（如 `TextEditingController`、`AnimationController` 等）的变化并执行副作用，**不会触发 widget 重建**。

### 优先使用场景

当需要对 `TextEditingController` 等 `Listenable` 对象添加监听器时，**优先使用 `useOnListenableChange`**，而非手动在 `useEffect` 中添加/移除 listener。

### 示例：自动保存文本变化

```dart
// ✅ 推荐：使用 useOnListenableChange
final titleController = useTextEditingController();
final contentController = useTextEditingController();

void scheduleAutoSave() {
  // 延迟保存逻辑
}

useOnListenableChange(titleController, scheduleAutoSave);
useOnListenableChange(contentController, scheduleAutoSave);
```

### 对比：不推荐的做法

```dart
// ❌ 不推荐：手动在 useEffect 中管理 listener
useEffect(() {
  void listener() => scheduleAutoSave();
  titleController.addListener(listener);
  contentController.addListener(listener);
  
  return () {
    // 问题：widget unmount 时 controller 可能已被 dispose
    // 导致 "A TextEditingController was used after being disposed" 错误
    titleController.removeListener(listener);
    contentController.removeListener(listener);
  };
}, const []);
```

### 优势

- 自动处理 listener 的添加/移除，无需手动 cleanup
- 避免 disposed controller 访问错误
- 代码更简洁，每个监听独立一行
- 符合 flutter_hooks 设计哲学
