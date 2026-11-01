# useCallback

## 签名

```dart
T useCallback<T extends Function>(T callback, [List<Object?> keys = const <Object>[]])
```

## 用途

缓存函数实例，避免每次 build 都创建新的函数对象。是 `useMemoized` 的语法糖。

## 说明

- 返回一个被缓存的函数，只有当 `keys` 变化时才会更新
- 本质是 `useMemoized(() => callback, keys)`
- 适合传递给子组件的回调，避免子组件不必要的重建
- 常用于 `VoidCallback`、`ValueChanged<T>` 等函数类型

## 示例

### 基本用法 - 缓存回调

```dart
final counter = useState(0);

// 每次 build 不会创建新的函数，除非 counter 变化
final increment = useCallback(() {
  counter.value++;
}, [counter]);

return ElevatedButton(
  onPressed: increment, // 稳定的函数引用
  child: Text('Count: ${counter.value}'),
);
```

### 传递给子组件

```dart
final userId = useState('123');

// 缓存回调函数，避免子组件不必要的重建
final onUserSelected = useCallback((String id) {
  userId.value = id;
  print('Selected: $id');
}, [userId]); // userId 变化时才更新回调

return UserList(onSelected: onUserSelected);
```

### 与直接创建函数的对比

```dart
// ❌ 每次 build 都创建新的函数，可能导致子组件重建
Widget build(BuildContext context) {
  return ElevatedButton(
    onPressed: () => counter.value++, // 新函数每次 build
    child: Text('Press'),
  );
}

// ✅ 使用 useCallback 缓存函数
Widget build(BuildContext context) {
  final onPressed = useCallback(() {
    counter.value++;
  }, [counter]);

  return ElevatedButton(
    onPressed: onPressed, // 稳定的引用
    child: Text('Press'),
  );
}
```

## 注意事项

- 如果回调依赖某些变量，必须将它们加入 `keys`
- 对于简单场景，直接传递匿名函数也可以，只有当子组件有性能问题或需要稳定引用时才需要用 `useCallback`
