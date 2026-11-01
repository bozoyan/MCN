# useMemoized

## 签名

```dart
T useMemoized<T>(T Function() valueBuilder, [List<Object?> keys = const <Object>[]])
```

## 用途

缓存复杂对象的实例，只有当 `keys` 变化时才会重新创建。

## 说明

- 首次调用时执行 `valueBuilder` 并缓存结果
- 后续 rebuild 时，如果 `keys` 没变，直接返回缓存值
- 如果 `keys` 中任一值变化，重新执行 `valueBuilder` 创建新实例
- 适合缓存创建开销大的对象（如复杂计算、数据转换等）

## 示例

### 缓存计算结果

```dart
final numbers = useState<List<int>>([1, 2, 3, 4, 5]);

// 只有 numbers.value 变化时才重新计算
final sum = useMemoized(() {
  print('Computing sum...'); // 只有在 numbers 变化时才会打印
  return numbers.value.reduce((a, b) => a + b);
}, [numbers.value]);

// 组件重建时，如果 numbers.value 没变，直接返回缓存的 sum
```

### 缓存复杂对象

```dart
final userId = useState('user_123');

final userRepository = useMemoized(() {
  print('Creating new UserRepository');
  return UserRepository(userId: userId.value);
}, [userId.value]); // userId 变化时才创建新的 repository
```

### 缓存 List/Map

```dart
final items = useState<List<Item>>([]);

// 过滤和排序是昂贵操作时，使用 useMemoized 缓存结果
final filteredItems = useMemoized(() {
  return items.value
    .where((item) => item.isActive)
    .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}, [items.value]);
```

### 与 useCallback 的关系

`useCallback` 是 `useMemoized` 的语法糖：

```dart
// 这两者是等价的
final cachedFn1 = useCallback(() => print('hello'), []);
final cachedFn2 = useMemoized(() => () => print('hello'), []);
```
