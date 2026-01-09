# Sora2 API 修复说明 - V1.1

## 修复日期
2025-01-09

## 问题描述

在 Sora2文生视频模式下,程序错误地尝试处理图片数据,导致以下错误:

```
[14:52:50] [Sora2文生视频任务_1] ❌ 无法获取有效的图片数据
[14:52:50] ❌ [task_145250_732] 任务失败: 无法获取有效的图片数据
```

## 根本原因

`SingleVideoGenerationWorker.run()` 方法在 `pic2vod.py` 的 462-550 行无条件地执行图片处理逻辑,但 Sora2文生视频模式 (Text-to-Video) 不需要图片输入,仅需要文本提示词和宽高比参数。

## 修复内容

### 1. 修改图片处理逻辑 (pic2vod.py:462-556)

**原代码结构**:
```python
self.progress_updated.emit(10, "处理图片数据...", self.task_id)
# 无条件执行图片处理逻辑
```

**修复后的代码**:
```python
# Sora2文生视频模式不需要图片输入,跳过图片处理
if self.video_mode == "sora_t2v":
    self.log_message(f"📝 Sora2文生视频模式 - 仅使用文本提示词")
    self.progress_updated.emit(10, "准备文本生成...", self.task_id)
else:
    # 其他模式需要处理图片数据
    self.progress_updated.emit(10, "处理图片数据...", self.task_id)
    # 执行完整的图片处理逻辑
```

### 2. 关键改进点

1. **条件判断**: 添加 `if self.video_mode == "sora_t2v"` 判断
2. **跳过图片处理**: sora_t2v 模式跳过所有图片下载、编码、压缩等步骤
3. **保留缩略图逻辑**: 缩略图保存已有 `if image_data:` 检查,自动跳过
4. **变量初始化**: 在条件分支外初始化 `image_save_path`, `image_value`, `image_data` 为 None

## 修复后的执行流程

### Sora2文生视频模式
1. ✅ 初始化任务
2. ✅ 准备文本生成 (跳过图片处理)
3. ✅ 构建 API 请求 (仅包含 prompt 和 aspect_ratio)
4. ✅ 发送到 BizyAir API (Web App ID: 42921)
5. ✅ 轮询任务状态
6. ✅ 下载视频

### Sora2图生视频模式
1. ✅ 初始化任务
2. ✅ 处理图片数据 (下载/编码/压缩)
3. ✅ 构建 API 请求 (包含 image, prompt 和 aspect_ratio)
4. ✅ 发送到 BizyAir API (Web App ID: 42936)
5. ✅ 轮询任务状态
6. ✅ 下载视频

### 其他模式 (单图转视频/首尾帧转视频/视频换人物)
1. ✅ 初始化任务
2. ✅ 处理图片数据 (完整流程)
3. ✅ 构建 API 请求
4. ✅ 发送到 BizyAir API
5. ✅ 轮询任务状态
6. ✅ 下载视频

## 代码变更详情

### 文件: /Users/yons/AI/MCN/pic2vod.py

**修改的代码段** (行 462-556):

- **移动变量初始化**: 将 `image_save_path`, `image_value`, `image_data` 初始化移到条件判断前
- **添加条件分支**: 为 `sora_t2v` 模式添加专门的处理分支
- **保持缩进**: 修复了原有代码的缩进问题,确保所有图片处理逻辑都在 `else` 分支内

## 测试验证

### 语法检查
```bash
python3 -m py_compile pic2vod.py
```
✅ 通过 - 无语法错误

### 预期行为

#### Sora2文生视频 (Tab 3)
- **输入**: 仅文本提示词 + 宽高比选择
- **不要求**: 图片输入
- **API 调用**:
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

#### Sora2图生视频 (Tab 4)
- **输入**: 图片 + 文本提示词 + 宽高比选择
- **API 调用**:
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

## 兼容性

✅ **完全兼容**: 此修复不影响其他三种视频生成模式的功能
- 单图片转视频 (Tab 0)
- 首尾帧转视频 (Tab 1)
- 视频换人物 (Tab 2)

所有原有功能保持不变。

## 使用建议

1. **Sora2文生视频**:
   - 适用于没有参考图片,仅通过文字描述生成视频的场景
   - 提示词越详细,生成效果越好
   - 推荐宽高比: 9:16 (竖屏短视频)

2. **Sora2图生视频**:
   - 适用于有参考图片,需要基于图片生成视频的场景
   - 图片质量直接影响生成效果
   - 建议使用高清图片作为输入

## 相关文档

- [Sora2-API功能说明-V1.0.md](./Sora2-API功能说明-V1.0.md) - 功能实现文档
- [BizyAIR-api-返回数据.md](./BizyAIR-api-返回数据.md) - API 规格文档

## 修复日志

### V1.1 (2025-01-09)
- 修复 Sora2文生视频模式错误处理图片数据的问题
- 添加条件判断逻辑,跳过 sora_t2v 模式的图片处理
- 通过 Python 语法检查

### V1.0 (2025-01-09)
- 新增 Sora2 文生视频功能
- 新增 Sora2 图生视频功能
- 更新配置管理系统
- 更新 API 设置对话框
- 添加宽高比选择功能
- 实现完整的任务管理和批量处理
