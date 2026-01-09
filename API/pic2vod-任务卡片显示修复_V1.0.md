# pic2vod.py 任务卡片显示修复 - V1.0

## 📋 更新概述

**更新日期**: 2025-01-09
**更新文件**: `pic2vod.py`
**问题**: Sora2 文生视频和图生视频任务卡片显示错误的参数信息

---

## 🐛 问题描述

### 原始问题
- ✅ **Sora2 文生视频** 和 **Sora2 图生视频** 任务卡片显示的是：
  - ❌ 错误信息：`480×854 · 81帧`（其他模式的尺寸和帧数）
  - ✅ 正确信息：`竖屏 (9:16)` 或 `横屏 (16:9)`（宽高比）

### 根本原因
在 `create_task_status_card` 函数中（第3673-3678行），传递给 `TaskStatusCard` 的 `task_params` 字典**缺少了关键字段**：
- ❌ 缺少 `video_mode`：无法识别是否为 Sora2 模式
- ❌ 缺少 `aspect_ratio`：无法获取宽高比信息

---

## ✅ 修复内容

### 1. 修复任务状态卡片参数传递

**文件位置**: `pic2vod.py:3673-3680`

**修改前**:
```python
task_params = {
    'width': task.get('width', 480),
    'height': task.get('height', 854),
    'num_frames': task.get('num_frames', 81),
    'prompt': task.get('prompt', '')
}
```

**修改后**:
```python
task_params = {
    'width': task.get('width', 480),
    'height': task.get('height', 854),
    'num_frames': task.get('num_frames', 81),
    'prompt': task.get('prompt', ''),
    'video_mode': task.get('video_mode', 'single'),  # ✅ 新增
    'aspect_ratio': task.get('aspect_ratio', '9:16')  # ✅ 新增
}
```

### 2. 宽高比映射确认

**TaskStatusCard** (pic2vod.py:1455-1458):
```python
aspect_map = {
    '9:16': '竖屏 (9:16)',
    '16:9': '横屏 (16:9)'
    # ⚠️ 注意：Sora2 不支持 1:1，已移除
}
```

**VideoResultCard** (pic2vod.py:1703-1706):
```python
aspect_map = {
    '9:16': '竖屏 (9:16)',
    '16:9': '横屏 (16:9)'
    # ⚠️ 注意：Sora2 不支持 1:1，已移除
}
```

---

## 📊 修复效果

### 修复前
- Sora2 任务卡片显示：`480×854 · 81帧` ❌
- 无法区分 Sora2 模式和其他模式

### 修复后
- Sora2 文生视频任务卡片显示：`竖屏 (9:16)` ✅ 或 `横屏 (16:9)` ✅
- Sora2 图生视频任务卡片显示：`竖屏 (9:16)` ✅ 或 `横屏 (16:9)` ✅
- 其他模式任务卡片显示：`480×854 · 81帧` ✅

---

## 🎯 验证方法

### 测试步骤
1. 创建 **Sora2 文生视频** 任务，选择不同的宽高比
2. 创建 **Sora2 图生视频** 任务，选择不同的宽高比
3. 查看任务卡片是否正确显示宽高比信息

### 预期结果
- ✅ 任务卡片第二行显示：
  - `竖屏 (9:16)` - 当选择 9:16 宽高比时
  - `横屏 (16:9)` - 当选择 16:9 宽高比时
- ✅ 不再显示尺寸和帧数信息

---

## 📝 技术说明

### 参数传递流程

1. **任务创建** → 添加 `video_mode` 和 `aspect_ratio`
   ```python
   task = {
       'name': '...',
       'prompt': '...',
       'video_mode': 'sora_t2v',  # 或 'sora_i2v'
       'aspect_ratio': '9:16'     # 或 '16:9'
   }
   ```

2. **任务状态卡片创建** → 传递完整参数
   ```python
   task_params = {
       'video_mode': task.get('video_mode', 'single'),
       'aspect_ratio': task.get('aspect_ratio', '9:16'),
       # ... 其他参数
   }
   ```

3. **TaskStatusCard 显示逻辑** → 根据 `video_mode` 判断
   ```python
   if video_mode in ['sora_t2v', 'sora_i2v']:
       # 显示宽高比
       params_text = aspect_map.get(aspect_ratio, aspect_ratio)
   else:
       # 显示尺寸和帧数
       params_text = f"{width}×{height} · {num_frames}帧"
   ```

---

## ⚠️ 注意事项

### Sora2 宽高比限制
- ✅ **支持的宽高比**: `9:16`（竖屏）、`16:9`（横屏）
- ❌ **不支持的宽高比**: `1:1`（方形）
- 📝 **说明**: BizyAir Sora2 API 目前仅支持以上两种宽高比

### 兼容性
- ✅ **向后兼容**: 其他模式（单图片、首尾帧、视频换人物）的显示不受影响
- ✅ **默认值**: 如果缺少 `video_mode` 或 `aspect_ratio`，使用合理的默认值

---

## 🔗 相关文件

- **主程序**: `pic2vod.py`
- **配置文件**: `video_settings.json`
- **优化文档**: `API/pic2vod-API超时策略优化_V1.0.md`

---

## 📌 版本历史

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| **V1.0** | 2025-01-09 | 修复 Sora2 任务卡片宽高比显示问题 |

---

**文档版本**: V1.0
**最后更新**: 2025-01-09
**维护者**: BOZO-MCN 开发团队
