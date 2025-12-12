# BOZO-MCN 多媒体编辑器 2.0 (改进版)

## 📋 改进概述

基于审阅报告的建议，我们对原始的 BOZO-MCN 多媒体编辑器进行了全面改进。主要改进包括：

### 🔧 主要改进点

#### 1. **配置管理优化**
- ✅ 创建了 `ConfigManager` 类来统一管理配置
- ✅ 将硬编码路径移至配置文件 `config.json`
- ✅ 支持运行时配置修改和保存

#### 2. **线程资源管理**
- ✅ 完善的线程生命周期管理
- ✅ 添加任务取消机制
- ✅ 防止内存泄漏的清理机制
- ✅ 并发数量限制

#### 3. **批量处理优化**
- ✅ 实现正确的批量进度计算
- ✅ 批量大小限制（默认10个文件）
- ✅ 并发任务管理

#### 4. **API密钥管理**
- ✅ 专门的API配置对话框
- ✅ 配置文件中安全存储
- ✅ 运行时配置验证

#### 5. **环境检查和依赖验证**
- ✅ 自动环境依赖检查
- ✅ FFmpeg、Whisper等工具验证
- ✅ 目录自动创建
- ✅ 详细的安装指导

#### 6. **错误处理机制**
- ✅ 完善的异常捕获和处理
- ✅ 用户友好的错误提示
- ✅ 操作超时处理
- ✅ 网络请求异常处理


#### 7. **未完成功能实现**
  - 视频分割功能（VideoSplitThread）
  - 基础视频合并功能（MergeVideoAudioThread）
  - 带缩放效果的视频合并（MergeVideoWithZoomThread）

#### 8. **文件编码优化**
- ✅ 自动编码检测（使用chardet）
- ✅ 多编码格式支持
- ✅ 编码错误容错处理

## 📁 文件结构

```
MCN/
├── config.json              # 配置文件
├── run_improved.py          # 主运行程序（简化演示版）
├── install_deps.py          # 依赖安装脚本
├── README.md       # 改进说明文档
├── MCN_improved.py          # 核心功能模块（第1部分）
├── MCN_improved_pages.py    # 页面类模块（第2部分）
├── MCN_improved_main.py     # 主窗口模块（第3部分）
├── MCN.py                   # 原始程序（参考）
└── README_pyqt.md           # 原始文档
```

## 🚀 快速开始

### 1. 环境准备

```bash
# 安装依赖
python install_deps.py

# 或者手动安装
pip install pyqt5 qfluentwidgets pillow requests chardet opencv-python
```

### 2. 配置设置

首次运行会自动创建 `config.json` 配置文件：

```json
{
    "paths": {
        "whisper_binary": "whisper.cpp/build/bin/whisper-cli",
        "whisper_model": "whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin",
        "ffmpeg_binary": "ffmpeg"
    },
    "api": {
        "siliconcloud_key": "",
        "base_url": "https://api.siliconflow.cn/v1/chat/completions",
        "model": "Qwen/Qwen2.5-Coder-32B-Instruct"
    },
    "processing": {
        "max_concurrent_workers": 4,
        "batch_size": 10,
        "timeout_seconds": 120
    },
    "ui": {
        "theme": "dark",
        "window_width": 1400,
        "window_height": 900
    }
}
```

### 3. 运行程序

```bash
# 使用conda环境（推荐）
conda activate modelscope
python run_improved.py

# 或直接运行
python run_improved.py
```

## 🛠️ 环境要求

### 系统要求
- **Python**: 3.7+
- **操作系统**: Windows 10+, macOS 10.14+, Linux (Ubuntu 18.04+)

### 必需依赖
- **FFmpeg**: 视频处理核心
- **PyQt5**: GUI框架
- **qfluentwidgets**: 现代化UI组件

### 可选依赖
- **whisper.cpp**: 字幕生成（需要手动编译）
- **OpenCV**: 图像处理增强

## 🔧 配置说明

### API配置
在设置页面配置SiliconCloud API密钥以启用翻译功能：
1. 打开设置页面
2. 点击"配置API密钥"
3. 输入API密钥和相关设置
4. 保存配置

### 路径配置
根据实际安装路径调整：
- `ffmpeg_binary`: FFmpeg可执行文件路径
- `whisper_binary`: Whisper CLI路径
- `whisper_model`: Whisper模型文件路径

### 性能配置
- `max_concurrent_workers`: 最大并发线程数
- `batch_size`: 批量处理文件数量限制
- `timeout_seconds`: 操作超时时间

## 📊 性能改进

### 内存管理
- 线程池复用，减少创建开销
- 及时清理临时文件
- 批量处理内存优化

### 处理效率
- 并发处理支持
- 进度显示优化
- 错误恢复机制

### 用户体验
- 实时进度反馈
- 详细错误提示
- 配置持久化

## 🐛 已知问题与解决方案

### 1. Whisper路径问题
**问题**: 硬编码路径导致跨平台兼容性问题
**解决**: 使用配置文件管理路径，支持相对路径

### 2. 批量处理进度不准确
**问题**: 多任务并行时进度计算错误
**解决**: 实现加权进度计算算法

### 3. 线程资源泄漏
**问题**: 程序退出时线程未正确清理
**解决**: 添加完善的线程生命周期管理

### 4. API密钥管理
**问题**: 缺少安全的API密钥管理机制
**解决**: 专门的配置对话框和加密存储

## 🔮 未来改进计划

### 短期目标
- [ ] 添加更多视频格式支持
- [ ] 优化whisper集成
- [ ] 增加插件系统

### 长期目标
- [ ] 云端处理支持
- [ ] AI增强功能
- [ ] 多语言界面

## 📝 开发说明

### 代码结构
- **模块化设计**: 功能分离，易于维护
- **配置驱动**: 通过配置文件控制行为
- **异常安全**: 完善的错误处理机制

### 测试建议
1. 在不同操作系统上测试
2. 验证各种文件格式支持
3. 测试并发处理稳定性

## 🤝 贡献指南

欢迎提交Issue和Pull Request来改进项目。

### 开发环境设置
```bash
git clone <repository>
cd MCN
python install_deps.py
python run_improved.py
```

## 📄 许可证

本项目基于原始BOZO-MCN项目进行改进，遵循相同的开源许可证。

---

**注意**: 这是基于审阅建议的改进版本。主要改进了代码架构、错误处理、资源管理等方面，提高了程序的稳定性和可维护性。