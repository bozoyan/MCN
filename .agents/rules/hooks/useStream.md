# useStream

## 签名

```dart
AsyncSnapshot<T> useStream<T>(Stream<T>? stream, {T? initialData, bool preserveState = true})
```

## 用途

订阅 `Stream` 并以 `AsyncSnapshot` 的形式返回其当前状态。

## 说明

- 返回一个 `AsyncSnapshot<T>`，包含 stream 的最新状态
- 自动管理订阅的生命周期（widget dispose 时取消订阅）
- `snapshot.data` 包含最新数据，`snapshot.hasData` 检查是否有数据
- `snapshot.connectionState` 表示连接状态（waiting、active、done）
- `snapshot.error` 包含错误信息（如果有）

## 示例

### 基本用法 - 监听 Stream

```dart
final stream = useMemoized(() => getNumberStream(), []);

final snapshot = useStream(stream);

if (snapshot.hasError) {
  return Text('Error: ${snapshot.error}');
}

if (!snapshot.hasData) {
  return CircularProgressIndicator();
}

return Text('Value: ${snapshot.data}');
```

### 带初始数据

```dart
final stream = useMemoized(() => fetchDataStream(), []);

final snapshot = useStream(
  stream,
  initialData: 'Loading...',
);

return Text(snapshot.data ?? 'No data');
```

### 监听 Firestore/数据库 Stream

```dart
final userId = useState('123');

final usersStream = useMemoized(
  () => firestore.collection('users').doc(userId.value).snapshots(),
  [userId.value],
);

final snapshot = useStream(usersStream);

return snapshot.hasData
    ? UserProfile(user: snapshot.data!)
    : CircularProgressIndicator();
```

### AsyncSnapshot 状态判断

```dart
final snapshot = useStream(someStream);

switch (snapshot.connectionState) {
  case ConnectionState.waiting:
    return Text('Waiting...');
  case ConnectionState.active:
    if (snapshot.hasData) {
      return Text('Data: ${snapshot.data}');
    } else if (snapshot.hasError) {
      return Text('Error: ${snapshot.error}');
    }
    return Text('No data');
  case ConnectionState.done:
    return Text('Stream closed');
  default:
    return Text('Unknown state');
}
```

## 注意事项

- Stream 变化时（new stream instance），会取消旧的订阅并建立新的
- 使用 `useMemoized` 缓存 stream 实例，避免每次 build 创建新的
- `preserveState` 控制是否在 stream 变化时保留之前的 data/error
