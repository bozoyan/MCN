# useReducer

## 签名

```dart
Store<StateT, ActionT> useReducer<StateT, ActionT>(
  Reducer<StateT, ActionT> reducer, {
  required StateT initialState,
  required ActionT initialAction,
})
```

其中 `Reducer<State, Action>` 定义为：

```dart
typedef Reducer<State, Action> = State Function(State state, Action action);
```

返回的 `Store<StateT, ActionT>` 提供：
- `.state` — 当前状态（只读）
- `.dispatch(action)` — 派发 action 更新状态

## 用途

使用 reducer 模式管理复杂状态，类似 Redux。适合状态逻辑复杂、有多个操作类型的场景。

## 说明

- 返回一个 `Store<StateT, ActionT>`，通过 `.state` 访问当前状态，`.dispatch(action)` 更新状态
- `initialState` 和 `initialAction` 为**必填命名参数**
- `initialAction` 会在首次调用时立即传给 reducer 生成初始状态
- 适合多个子状态、多种操作类型的复杂状态管理

## 示例

### 计数器 Reducer

```dart
// 定义 action
enum CounterAction { increment, decrement, reset }

// 使用 useReducer
final counter = useReducer(
  _counterReducer,
  initialState: 0,
  initialAction: CounterAction.reset,
);

int _counterReducer(int state, CounterAction action) {
  switch (action) {
    case CounterAction.increment:
      return state + 1;
    case CounterAction.decrement:
      return state - 1;
    case CounterAction.reset:
      return 0;
  }
}

return Column(
  children: [
    Text('Count: ${counter.state}'),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => counter.dispatch(CounterAction.increment),
          child: Text('+'),
        ),
        ElevatedButton(
          onPressed: () => counter.dispatch(CounterAction.reset),
          child: Text('Reset'),
        ),
      ],
    ),
  ],
);
```

### 复杂状态管理

```dart
// 定义状态
class FormState {
  final String name;
  final String email;
  final bool isSubmitting;

  FormState({this.name = '', this.email = '', this.isSubmitting = false});
}

// 定义 action
class UpdateName { final String name; UpdateName(this.name); }
class UpdateEmail { final String email; UpdateEmail(this.email); }
class SubmitForm {}

final form = useReducer(
  _formReducer,
  initialState: FormState(),
  initialAction: UpdateName(''),
);

FormState _formReducer(FormState state, action) {
  if (action is UpdateName) {
    return FormState(name: action.name, email: state.email, isSubmitting: state.isSubmitting);
  }
  if (action is UpdateEmail) {
    return FormState(name: state.name, email: action.email, isSubmitting: state.isSubmitting);
  }
  if (action is SubmitForm) {
    return FormState(name: state.name, email: state.email, isSubmitting: true);
  }
  return state;
}

// 使用 form.state 访问状态
// 使用 form.dispatch(action) 更新状态
```

## 与 useState 对比

| | useReducer | useState |
|---|---|---|
| 适合场景 | 复杂状态、多操作类型 | 简单状态、单一值 |
| 状态更新 | 通过 `dispatch(action)` | 直接修改 `.value` |
| 可预测性 | 高（所有修改都在 reducer 中） | 低（分散在各处） |

## 注意事项

- `Store.state` 是只读的，必须通过 `dispatch(action)` 更新
- `initialAction` 会在首次 build 时同步执行 reducer，作为状态的初始值
- 对于简单状态，使用 `useState` 更简单
