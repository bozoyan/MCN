# useRef

## 签名

```dart
ObjectRef<T> useRef<T>(T initialValue)
```

## 用途

创建一个在多次 rebuild 之间保持的可变引用，**修改不会触发重建**。

## 说明

- 返回一个 `ObjectRef<T>` 对象，通过 `.value` 属性访问/修改值
- 修改 `.value` **不会**触发 widget 重建
- 适合存储不需要触发 UI 更新的临时数据（如 Timer、滚动位置、标志位等）
- 本质是 `useMemoized(() => ObjectRef<T>(initialValue))` 的语法糖

## ObjectRef 类

```dart
class ObjectRef<T> {
  T value; // 可读写，修改不触发重建
}
```

## 示例

### 存储 Timer 引用

```dart
final timerRef = useRef<Timer?>(null);

void startTimer() {
  timerRef.value = Timer.periodic(Duration(seconds: 1), (_) {
    print('Tick');
  });
}

void stopTimer() {
  timerRef.value?.cancel();
  timerRef.value = null;
}
// 修改 timerRef.value 不会触发重建
```

### 标志位 - 防止重复触发

```dart
final hasFetched = useRef(false);

useEffect(() {
  if (!hasFetched.value) {
    hasFetched.value = true;
    fetchData();
  }
  return null;
}, []);
```

### 存储滚动位置

```dart
final scrollPosition = useRef(0.0);
final controller = useScrollController();

useEffect(() {
  void listener() {
    scrollPosition.value = controller.offset;
    // 不会触发重建，只是保存值
  }
  controller.addListener(listener);
  return () => controller.removeListener(listener);
}, [controller]);
```

### 与 useState 对比

```dart
// useState - 修改会触发重建
final counter1 = useState(0);
counter1.value++; // 触发重建 ✅

// useRef - 修改不会触发重建
final counter2 = useRef(0);
counter2.value++; // 不触发重建 ❌（如果需要重建，应该用 useState）
```
