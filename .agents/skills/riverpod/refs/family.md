# Family

**Family** 让一个 Provider 按参数独立缓存多份状态（类似 `Map<参数, 状态>`）。

## 声明

```dart
// Manual
final userProvider = FutureProvider.autoDispose.family<User, String>((ref, id) async {
  final response = await dio.get('https://api.example.com/users/$id');
  return User.fromJson(response.data);
});

// Codegen: 函数加参数即可
@riverpod
Future<User> user(Ref ref, String id) async { ... }
// 生成 userProvider(id)
```

### Notifier + Family

```dart
final userProvider = AsyncNotifierProvider.autoDispose.family<UserNotifier, User, String>(
  UserNotifier.new,
);

class UserNotifier extends AsyncNotifier<User> {
  UserNotifier(this.id);
  final String id;

  @override
  Future<User> build() async { ... }
}
```

## 使用

```dart
final user = ref.watch(userProvider('123'));
final other = ref.watch(userProvider('456')); // 独立状态
```

## 参数要求

- 必须有稳定的 `==` 和 `hashCode`。
- 不要传可变对象或 list/map 字面量：`ref.watch(myProvider([1,2,3]))` 是错误的。
- 启用 `riverpod_lint` 的 `provider_parameters` 规则检查。

## 测试覆盖

- **单参数覆盖**: `userProvider('123').overrideWith((ref) => User(...))`
- **所有参数覆盖**: `userProvider.overrideWith((ref, arg) => User(name: 'User $arg'))`
