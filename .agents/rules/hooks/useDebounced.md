# useDebounced

## 签名

```dart
T? useDebounced<T>(T toDebounce, Duration timeout)
```

## 用途

对值进行防抖（debounce）处理，只在指定时间间隔内没有新值时才更新返回值。

## 说明

- 输入值 `toDebounce`，返回 debounce 后的 `T?`（初始为 `null`）
- 在 `timeout` 时间内没有新值变化时，才更新返回值并触发重建
- 适合搜索输入、表单校验等需要延迟响应的场景
- 首次调用返回 `null`，之后在 timeout 后返回最新的 debounced 值

## 示例

### 搜索防抖

```dart
final controller = useTextEditingController();
final debouncedText = useDebounced(
  controller.text,
  Duration(milliseconds: 400),
);

useEffect(() {
  if (debouncedText == null) return null;
  // 在用户停止输入 400ms 后执行搜索
  print('Searching: $debouncedText');
  // searchApi(debouncedText);
  return null;
}, [debouncedText]);
```

### 表单校验防抖

```dart
final emailController = useTextEditingController();
final debouncedEmail = useDebounced(
  emailController.text,
  Duration(milliseconds: 300),
);
final isValid = useState<bool?>(null);

useEffect(() {
  if (debouncedEmail == null) return null;
  // 延迟校验邮箱格式
  isValid.value = debouncedEmail.contains('@');
  return null;
}, [debouncedEmail]);

return Column(
  children: [
    TextField(controller: emailController),
    if (isValid.value != null)
      Text(isValid.value! ? 'Valid' : 'Invalid'),
  ],
);
```

### 配合 useValueListenable 实时监听

```dart
final controller = useTextEditingController();
final textValue = useValueListenable(controller); // 实时值
final debouncedText = useDebounced(textValue.text, Duration(milliseconds: 300));

// textValue.text 每次输入都变化
// debouncedText 只在停止输入 300ms 后变化
```

## 注意事项

- 返回值是 `T?`，首次调用或 timeout 未到时返回 `null`
- 需要在 `useEffect` 中检查 `null`，避免初始值触发副作用
- `timeout` 期间如果 `toDebounce` 变化，会重置计时器
- 适合需要等待用户"停止输入"后再执行的场景
