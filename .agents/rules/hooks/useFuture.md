# useFuture

## 签名

```dart
AsyncSnapshot<T> useFuture<T>(Future<T>? future, {T? initialData, bool preserveState = true})
```

## 用途

监听 `Future` 并以 `AsyncSnapshot` 的形式返回其当前状态。

## 说明

- 返回一个 `AsyncSnapshot<T>`，包含 future 的最新状态
- 自动处理 future 的生命周期
- `snapshot.data` 包含成功返回的数据
- `snapshot.connectionState` 表示状态（waiting、done）
- `snapshot.error` 包含错误信息（如果有）
- 适合一次性异步操作（如 API 调用、数据库查询等）

## 示例

### 基本用法 - 加载数据

```dart
final userId = useState('123');

final future = useMemoized(
  () => fetchUser(userId.value),
  [userId.value], // userId 变化时重新执行
);

final snapshot = useFuture(future);

if (snapshot.connectionState == ConnectionState.waiting) {
  return CircularProgressIndicator();
}

if (snapshot.hasError) {
  return Text('Error: ${snapshot.error}');
}

final user = snapshot.data;
return UserProfile(user: user);
```

### 带初始数据

```dart
final future = useMemoized(() => fetchConfig(), []);
final snapshot = useFuture(future, initialData: defaultConfig);

// snapshot.data 初始为 defaultConfig，future 完成后更新
return ConfigView(config: snapshot.data);
```

### 配合下拉刷新

```dart
final refreshKey = useMemoized(() => GlobalKey<RefreshIndicatorState>());
final fetchFuture = useMemoized(() => fetchItems(), [refreshKey]);

final snapshot = useFuture(fetchFuture);

return RefreshIndicator(
  key: refreshKey,
  onRefresh: () async {
    // 触发重新获取（通过某种方式使 future 重新创建）
  },
  child: snapshot.hasData
      ? ListView.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) => ItemTile(snapshot.data![index]),
        )
      : Center(child: CircularProgressIndicator()),
);
```

## AsyncSnapshot 状态处理

```dart
final snapshot = useFuture(someFuture);

// 方式 1: 使用 connectionState
if (snapshot.connectionState == ConnectionState.waiting) {
  return LoadingWidget();
}

// 方式 2: 使用 hasData
if (snapshot.hasData) {
  return DataWidget(data: snapshot.data!);
}

// 方式 3: 使用 when 语法（如果定义了扩展）
return snapshot.when(
  data: (data) => DataWidget(data: data),
  loading: () => LoadingWidget(),
  error: (err) => ErrorWidget(err),
);
```

## 注意事项

- Future 变化时（new future instance），会重新监听
- 使用 `useMemoized` 缓存 future，避免每次 build 创建新的
- Future 完成后状态保持在 `ConnectionState.done`
- 适合一次性异步操作，持续的数据流应使用 `useStream`
