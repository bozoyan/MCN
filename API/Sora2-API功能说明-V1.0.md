# Sora2 API 功能集成说明 - V1.0

## 概述
本文档详细说明了在 pic2vod.py 中新增的 Sora2 文生视频和 Sora2 图生视频功能的实现细节。

## 新增功能

### 1. Sora2 文生视频 (Text-to-Video)
- **选项卡名称**: Sora2文生视频
- **Web App ID**: 42921
- **功能**: 通过文本提示词生成视频，无需输入图片
- **API端点**: `57:BizyAir_Sora_V2_T2V_API`

### 2. Sora2 图生视频 (Image-to-Video)
- **选项卡名称**: Sora2图生视频
- **Web App ID**: 42936
- **功能**: 基于输入图片和文本提示词生成视频
- **API端点**: `18:LoadImage.image`, `6:CR Prompt Text.prompt`, `54:BizyAir_Sora_V2_I2V_API`

## API 调用格式

### Sora2 文生视频 API
```json
{
  "web_app_id": 42921,
  "suppress_preview_output": true,
  "input_values": {
    "57:BizyAir_Sora_V2_T2V_API.prompt": "提示词内容",
    "57:BizyAir_Sora_V2_T2V_API.aspect_ratio": "9:16"
  }
}
```

### Sora2 图生视频 API
```json
{
  "web_app_id": 42936,
  "suppress_preview_output": true,
  "input_values": {
    "18:LoadImage.image": "data:image/jpeg;base64,...",
    "6:CR Prompt Text.prompt": "提示词内容",
    "54:BizyAir_Sora_V2_I2V_API.aspect_ratio": "9:16"
  }
}
```

## 宽高比支持
两种 Sora2 模式均支持以下宽高比：
- `9:16` - 竖屏格式（适合手机短视频）
- `16:9` - 横屏格式（适合传统视频）
- `1:1` - 方形格式（适合社交媒体）

## 代码实现细节

### 1. 配置管理 (VideoSettingsManager)
新增配置项：
```python
"web_app_id_sora_t2v": 42921,  # Sora2 文生视频 Web App ID
"web_app_id_sora_i2v": 42936,  # Sora2 图生视频 Web App ID
```

### 2. API 密钥管理器 (APIKeyManager)
新增属性：
```python
self.web_app_id_sora_t2v = 42921
self.web_app_id_sora_i2v = 42936
```

### 3. 视频生成工作线程 (SingleVideoGenerationWorker)
新增两种视频模式支持：
- `video_mode = "sora_t2v"` - Sora2 文生视频
- `video_mode = "sora_i2v"` - Sora2 图生视频

### 4. UI 组件
新增方法：
- `create_sora_t2v_tab()` - 创建 Sora2 文生视频选项卡
- `create_sora_i2v_tab()` - 创建 Sora2 图生视频选项卡
- `create_sora_prompt_group()` - 创建 Sora2 提示词输入组
- `create_sora_aspect_ratio_group()` - 创建宽高比选择组
- `create_batch_group_sora_t2v()` - 创建 Sora2 文生视频批量任务组
- `create_batch_group_sora_i2v()` - 创建 Sora2 图生视频批量任务组

### 5. 任务管理
新增方法：
- `add_to_batch_tasks_sora_t2v()` - 添加 Sora2 文生视频任务
- `update_task_list_display_sora_t2v()` - 更新 Sora2 文生视频任务列表
- `create_task_card_sora_t2v()` - 创建 Sora2 文生视频任务卡片
- `remove_task_sora_t2v()` - 删除 Sora2 文生视频任务
- `clear_batch_tasks_sora_t2v()` - 清空 Sora2 文生视频任务
- `add_to_batch_tasks_sora_i2v()` - 添加 Sora2 图生视频任务
- `update_task_list_display_sora_i2v()` - 更新 Sora2 图生视频任务列表
- `create_task_card_sora_i2v()` - 创建 Sora2 图生视频任务卡片
- `remove_task_sora_i2v()` - 删除 Sora2 图生视频任务
- `clear_batch_tasks_sora_i2v()` - 清空 Sora2 图生视频任务

### 6. 生成功能更新
更新的方法：
- `generate_single_video()` - 支持两种新模式（索引 3 和 4）
- `generate_batch_videos()` - 支持两种新模式的批量处理

## 使用方式

### Sora2 文生视频
1. 切换到"Sora2文生视频"选项卡
2. 输入视频生成的提示词
3. 选择视频宽高比（9:16、16:9 或 1:1）
4. 点击"单个生成"或"添加到任务列表"后批量生成

### Sora2 图生视频
1. 切换到"Sora2图生视频"选项卡
2. 上传参考图片或输入图片URL
3. 输入视频生成的提示词
4. 选择视频宽高比（9:16、16:9 或 1:1）
5. 点击"单个生成"或"添加到任务列表"后批量生成

## 特性支持

### 单个生成
- 支持单个任务的视频生成
- 实时进度显示
- 任务状态跟踪

### 批量生成
- 支持多任务队列
- 自动密钥轮换
- 并发任务处理（60秒间隔）
- 批量进度显示

### 任务管理
- 任务添加、删除、清空
- 任务卡片可视化展示
- 任务状态实时更新

### 视频结果展示
- 自动下载到 output 目录
- 本地播放支持
- URL 复制功能
- 完成时间显示

## API 密钥配置

在 API 设置对话框中，可以配置以下 Web App ID：
- 单图片转视频 ID: 39386
- 首尾帧转视频 ID: 39388
- 视频换人物 ID: 38808
- **Sora2文生视频 ID: 42921** (新增)
- **Sora2图生视频 ID: 42936** (新增)

## 配置文件更新

`video_settings.json` 文件会自动保存新增的配置：
```json
{
  "api_settings": {
    "web_app_id_sora_t2v": 42921,
    "web_app_id_sora_i2v": 42936,
    ...
  }
}
```

## 注意事项

1. **API 密钥**: 确保配置有效的 BizyAir API 密钥
2. **网络连接**: Sora2 API 需要稳定的网络连接
3. **任务间隔**: 批量任务之间有 60 秒的间隔，避免 API 限流
4. **宽高比选择**: 根据目标平台选择合适的宽高比
5. **提示词质量**: 详细和准确的提示词能获得更好的生成效果

## 兼容性

- 与现有的三个选项卡完全兼容
- 不影响原有功能的使用
- 共享相同的 API 密钥管理系统
- 统一的任务调度和进度显示

## 更新日志

### V1.0 (2025-01-09)
- 新增 Sora2 文生视频功能
- 新增 Sora2 图生视频功能
- 更新配置管理系统
- 更新 API 设置对话框
- 添加宽高比选择功能
- 实现完整的任务管理和批量处理

## 技术支持

如有问题，请查看：
1. 程序日志文件：`logs/pic2vod_generation.log`
2. 操作日志：界面中的"操作日志"选项卡
3. API 文档：BizyAIR-api-返回数据.md
