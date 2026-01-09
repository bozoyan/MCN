# Sora2 API 修复说明 - V1.3

## 修复日期
2025-01-09

## 问题描述

Sora2文生视频和Sora2图生视频模式不支持自定义尺寸和帧数参数，只有固定的宽高比选择（9:16, 16:9, 1:1）。但在视频列表和任务结果显示中，仍然按照默认的 480x854 81帧 来显示，这与实际的 API 参数不匹配。

**显示问题**:
1. **视频任务卡片** (TaskStatusCard) - 显示 "480×854 · 81帧"
2. **视频结果卡片** (VideoResultCard) - 显示 "尺寸: 480×854" 和 "帧数: 81帧"
3. **操作日志** - 通过 result_data 传递的数据也包含默认的 width/height/num_frames

**实际需求**:
- Sora2 模式应该显示宽高比（如 "竖屏 (9:16)"）
- 其他模式继续显示尺寸和帧数（如 "480×854 · 81帧"）

## 根本原因

1. **API 参数不同**:
   - Sora2 模式: 只有 `aspect_ratio` 参数 (9:16, 16:9, 1:1)
   - 其他模式: 有 `width`, `height`, `num_frames` 参数

2. **显示逻辑未区分**:
   - TaskStatusCard 和 VideoResultCard 固定显示 width/height/num_frames
   - 没有根据 video_mode 判断显示不同的参数信息

3. **数据传递不完整**:
   - result_data 中没有包含 `video_mode` 和 `aspect_ratio` 字段
   - 导致 VideoResultCard 无法判断使用哪种显示格式

## 修复内容

### 1. 任务状态卡片显示 (TaskStatusCard)

**文件**: pic2vod.py:1398-1419

**原代码**:
```python
# 帧数、尺寸信息
width = self.task_params.get('width', 480)
height = self.task_params.get('height', 854)
num_frames = self.task_params.get('num_frames', 81)

params_text = f"{width}×{height} · {num_frames}帧"
self.params_label = CaptionLabel(params_text)
```

**修复后**:
```python
# 根据视频模式显示不同的参数信息
video_mode = self.task_params.get('video_mode', 'single')

if video_mode in ['sora_t2v', 'sora_i2v']:
    # Sora2 模式：显示宽高比
    aspect_ratio = self.task_params.get('aspect_ratio', '9:16')
    aspect_map = {
        '9:16': '竖屏 (9:16)',
        '16:9': '横屏 (16:9)',
        '1:1': '方形 (1:1)'
    }
    params_text = aspect_map.get(aspect_ratio, aspect_ratio)
else:
    # 其他模式：显示帧数、尺寸信息
    width = self.task_params.get('width', 480)
    height = self.task_params.get('height', 854)
    num_frames = self.task_params.get('num_frames', 81)
    params_text = f"{width}×{height} · {num_frames}帧"

self.params_label = CaptionLabel(params_text)
```

**效果**:
- Sora2模式: 显示 "竖屏 (9:16)" 或 "横屏 (16:9)" 或 "方形 (1:1)"
- 其他模式: 显示 "480×854 · 81帧"

### 2. 视频结果卡片显示 (VideoResultCard)

**文件**: pic2vod.py:1647-1676

**原代码**:
```python
# 视频信息
info_layout = QHBoxLayout()

size_label = CaptionLabel(f"尺寸: {self.video_data.get('width', 480)}×{self.video_data.get('height', 854)}")
size_label.setStyleSheet("color: #cccccc; font-size: 12px;")
info_layout.addWidget(size_label)

info_layout.addSpacing(15)

frames_label = CaptionLabel(f"帧数: {self.video_data.get('num_frames', 81)}帧")
frames_label.setStyleSheet("color: #cccccc; font-size: 12px;")
info_layout.addWidget(frames_label)

info_layout.addStretch()
```

**修复后**:
```python
# 视频信息
info_layout = QHBoxLayout()

# 根据视频模式显示不同的参数信息
video_mode = self.video_data.get('video_mode', 'single')

if video_mode in ['sora_t2v', 'sora_i2v']:
    # Sora2 模式：显示宽高比
    aspect_ratio = self.video_data.get('aspect_ratio', '9:16')
    aspect_map = {
        '9:16': '竖屏 (9:16)',
        '16:9': '横屏 (16:9)',
        '1:1': '方形 (1:1)'
    }
    params_text = f"宽高比: {aspect_map.get(aspect_ratio, aspect_ratio)}"
    params_label = CaptionLabel(params_text)
    params_label.setStyleSheet("color: #cccccc; font-size: 12px;")
    info_layout.addWidget(params_label)
else:
    # 其他模式：显示尺寸和帧数
    size_label = CaptionLabel(f"尺寸: {self.video_data.get('width', 480)}×{self.video_data.get('height', 854)}")
    size_label.setStyleSheet("color: #cccccc; font-size: 12px;")
    info_layout.addWidget(size_label)

    info_layout.addSpacing(15)

    frames_label = CaptionLabel(f"帧数: {self.video_data.get('num_frames', 81)}帧")
    frames_label.setStyleSheet("color: #cccccc; font-size: 12px;")
    info_layout.addWidget(frames_label)

info_layout.addStretch()
```

**效果**:
- Sora2模式: 显示 "宽高比: 竖屏 (9:16)"
- 其他模式: 显示 "尺寸: 480×854" 和 "帧数: 81帧"

### 3. 任务结果数据传递

**文件**: pic2vod.py:791-804

**原代码**:
```python
result = {
    'id': request_id,
    'url': video_url,
    'width': width,
    'height': height,
    'num_frames': num_frames,
    'prompt': prompt,
    'task_name': task_name,
    'timestamp': datetime.now().isoformat(),
    'base_filename': base_filename,
    'thumbnail_path': image_save_path
}
```

**修复后**:
```python
result = {
    'id': request_id,
    'url': video_url,
    'width': width,
    'height': height,
    'num_frames': num_frames,
    'prompt': prompt,
    'task_name': task_name,
    'timestamp': datetime.now().isoformat(),
    'base_filename': base_filename,
    'thumbnail_path': image_save_path,
    'video_mode': self.video_mode,  # 添加视频模式
    'aspect_ratio': self.task.get('aspect_ratio', '9:16')  # 添加宽高比
}
```

**说明**:
- 添加 `video_mode` 字段，让 VideoResultCard 能判断使用哪种显示格式
- 添加 `aspect_ratio` 字段，让 VideoResultCard 能显示宽高比
- 保留原有的 `width`, `height`, `num_frames` 字段（用于其他模式）

## 显示效果对比

### Sora2文生视频 / Sora2图生视频

**任务卡片**:
```
任务名称: Sora2文生视频任务_1
参数信息: 竖屏 (9:16)
密钥类型: 文件密钥
提示词: @yanbo1984 这个男人去爬山...
进度: ████████░░ 80%
时间: 00:02:35
```

**结果卡片**:
```
任务名称: Sora2文生视频单个任务_150259
下载状态: 下载完成 · 01-09 15:03:45
参数信息: 宽高比: 竖屏 (9:16)
提示词: @yanbo1984 这个男人去爬山，男人正视相机镜头
视频URL: https://storage.bizyair.cn/outputs/...
```

### 单图片转视频 / 首尾帧转视频 / 视频换人物

**任务卡片**:
```
任务名称: 单图片转视频任务_1
参数信息: 480×854 · 81帧
密钥类型: 文件密钥
提示词: 一个美丽的风景...
进度: ████████░░ 80%
时间: 00:02:35
```

**结果卡片**:
```
任务名称: 单图片转视频任务_1
下载状态: 下载完成 · 01-09 15:03:45
参数信息: 尺寸: 480×854    帧数: 81帧
提示词: 一个美丽的风景...
视频URL: https://storage.bizyair.cn/outputs/...
```

## 宽高比映射

| API 值 | 显示文本 | 说明 |
|--------|----------|------|
| 9:16 | 竖屏 (9:16) | 适合手机短视频 |
| 16:9 | 横屏 (16:9) | 适合传统视频 |
| 1:1 | 方形 (1:1) | 适合社交媒体 |

## 兼容性

✅ **完全兼容**: 此修复不影响任何现有功能

### 不受影响的模式
1. **单图片转视频** (Tab 0) - 继续显示尺寸和帧数
2. **首尾帧转视频** (Tab 1) - 继续显示尺寸和帧数
3. **视频换人物** (Tab 2) - 继续显示尺寸和帧数

### 改进的显示
1. **Sora2文生视频** (Tab 3) - 现在正确显示宽高比
2. **Sora2图生视频** (Tab 4) - 现在正确显示宽高比

## 测试验证

### 语法检查
```bash
python3 -m py_compile pic2vod.py
```
✅ 通过 - 无语法错误

### 功能测试建议

1. **Sora2文生视频模式**:
   - 创建任务，选择不同宽高比（9:16, 16:9, 1:1）
   - 验证任务卡片显示正确的宽高比文本
   - 验证结果卡片显示正确的宽高比文本

2. **Sora2图生视频模式**:
   - 创建任务，上传图片，选择不同宽高比
   - 验证显示正确

3. **其他模式**:
   - 创建单图片转视频任务
   - 验证仍显示 "480×854 · 81帧" 格式
   - 确保没有回归问题

## 相关文档

- [Sora2-API功能说明-V1.0.md](./Sora2-API功能说明-V1.0.md) - 功能实现文档
- [Sora2-API修复说明-V1.1.md](./Sora2-API修复说明-V1.1.md) - 文生视频图片处理修复
- [Sora2-API修复说明-V1.2.md](./Sora2-API修复说明-V1.2.md) - SOCKS 代理依赖修复
- [BizyAIR-api-返回数据.md](./BizyAIR-api-返回数据.md) - API 规格文档

## 修复日志

### V1.3 (2025-01-09)
- 修复 Sora2 模式视频列表和结果显示宽高比
- 修复 TaskStatusCard 显示逻辑，根据 video_mode 显示不同参数
- 修复 VideoResultCard 显示逻辑，根据 video_mode 显示不同参数
- 在 result 数据中添加 video_mode 和 aspect_ratio 字段
- 通过 Python 语法检查

### V1.2 (2025-01-09)
- 修复 SOCKS 代理依赖问题
- 使用 `session.trust_env = False` 完全禁用环境变量代理
- 更新所有 API 请求、状态查询和视频下载代码

### V1.1 (2025-01-09)
- 修复 Sora2文生视频模式错误处理图片数据的问题
- 添加条件判断逻辑,跳过 sora_t2v 模式的图片处理

### V1.0 (2025-01-09)
- 新增 Sora2 文生视频功能
- 新增 Sora2 图生视频功能
- 更新配置管理系统
- 更新 API 设置对话框
- 添加宽高比选择功能
- 实现完整的任务管理和批量处理
