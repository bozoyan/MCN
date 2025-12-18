# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

BOZO-MCN 是一个基于 PyQt5 和 qfluentwidgets 开发的多媒体内容创作工具集，包含多个核心模块：

1. **MCN.py** - 主程序，提供多媒体编辑功能
2. **storyboard_generator.py** - AI分镜脚本与图片生成器
3. **pic2vod.py** - 图片转视频功能模块
4. **aigc.py** - AI模型启动器

## 开发环境配置

### 依赖安装

```bash
# 安装主程序依赖
pip install -r requirements.txt

# 安装分镜生成器依赖（可选）
pip install -r requirements_storyboard.txt
```

### 核心依赖项

- **PyQt5** - GUI框架
- **qfluentwidgets** - Fluent Design风格组件
- **requests** - HTTP API调用
- **Pillow** - 图像处理
- **chardet** - 字符编码检测
- **openai** - AI模型API接口

### 外部工具依赖

- **FFmpeg** - 视频处理（必须系统可执行）
- **whisper.cpp** - 语音转文本功能

### 环境变量配置

```bash
export SiliconCloud_API_KEY="your_api_key_here"
export MODELSCOPE_SDK_TOKEN="your_modelscope_token"
export AIPATH="/Volumes/AI/AI/"
```

## 项目架构

### 核心模块结构

```
MCN/
├── MCN.py                    # 主程序入口，多媒体编辑器
├── storyboard_generator.py   # AI分镜脚本生成器（独立程序）
├── pic2vod.py               # 图片转视频模块（集成在MCN中）
├── run.py                   # 通用运行脚本
├── check_requirements.py    # 依赖检查工具
├── storyboard_config.json   # 分镜生成器配置
├── video_settings.json      # 视频生成配置
├── buttons.json             # 按钮配置
├── requirements*.txt        # 依赖文件
└── 工作目录/
    ├── temp/                # 临时文件
    ├── SRT/                 # 字幕文件
    ├── speech/              # 音频文件
    ├── font/                # 字体文件
    └── output/              # 输出文件
```

### 多线程架构

项目使用 QThread 基类实现多线程处理：

- **WorkerThread** - 所有工作线程的基类
- **VideoConversionThread** - 视频转换线程
- **ImageToVideoThread** - 图片转视频线程
- **SRTGenerationThread** - 字幕生成线程
- **ThreadPoolExecutor** - 线程池管理

### 配置管理系统

- **config.json** - 主程序配置（API密钥、路径、并发设置等）
- **storyboard_config.json** - 分镜生成器配置
- **video_settings.json** - 视频生成设置持久化
- **buttons.json** - 界面按钮配置

## 常用开发命令

### 运行程序

```bash
# 运行主程序（多媒体编辑器）
python MCN.py

# 运行分镜生成器
python storyboard_generator.py

# 检查依赖环境
python check_requirements.py
```

### 调试和测试

```bash
# 检查FFmpeg是否可用
ffmpeg -version

# 检查whisper.cpp配置
ls -la whisper.cpp/build/bin/
ls -la whisper.cpp/models/

# 测试API连接
python -c "import requests; print(requests.get('https://api.siliconflow.cn/v1/models').status_code)"
```

### 维护命令

```bash
# 清理临时文件
rm -rf temp/*

# 清理日志文件
rm -f logs/*.log

# 重置配置（谨慎使用）
rm config.json storyboard_config.json video_settings.json
```

## 核心功能模块

### 1. 多媒体编辑器 (MCN.py)

主要功能模块：
- 视频转换（无声视频、音频提取）
- 图片转视频（单张/批量、模糊背景、自定义尺寸）
- 视频音频合并（封面、缩放动画、滤镜）
- 字幕生成（API语音转文本、Whisper本地处理）
- 字幕编辑和翻译
- 视频字幕整合

### 2. AI分镜生成器 (storyboard_generator.py)

核心功能：
- AI生成9个分镜标题和描述
- 支持多种AI绘图模型（Flux、SDXL、SD1.5）
- 批量图片生成和预览
- 模板管理系统
- Markdown文档导出

### 3. 图片转视频 (pic2vod.py)

特色功能：
- 基于BizyAir API的高质量视频生成
- 支持拖拽上传和Base64编码
- 多密钥并发处理
- 批量任务队列管理
- 深色主题界面

### 4. AI模型启动器 (aigc.py)

功能：
- 基于tkinter的模型选择界面
- 支持多种AI模型快速启动
- 分类管理（文本、图像、语音等）

## API接口配置

### SiliconCloud API

- **基础URL**: `https://api.siliconflow.cn/v1/chat/completions`
- **模型**: Qwen/Qwen3-235B-A22B-Instruct
- **密钥环境变量**: `SiliconCloud_API_KEY`

### ModelScope API

- **基础URL**: `https://api-inference.modelscope.cn/v1/`
- **文本模型**: Qwen/Qwen3-235B-A22B-Thinking-2507
- **图片模型**: bozoyan/F_fei (Flux), AI-ModelScope/stable-diffusion-xl-base-1.0
- **密钥环境变量**: `MODELSCOPE_SDK_TOKEN`

### BizyAir API

- **Web App ID**: 39386
- **功能**: 图片转视频
- **输出格式**: MP4
- **最大超时**: 10分钟

## 开发注意事项

### 代码规范
- 所有用户界面文本使用简体中文
- 函数和变量名使用英文
- 注释使用中文
- 遵循PEP 8代码风格

### 线程安全
- 所有耗时操作必须在独立线程中执行
- 使用pyqtSignal进行线程间通信
- 避免在子线程中直接操作UI

### 错误处理
- 使用try-except包装所有外部API调用
- 提供友好的中文错误提示
- 记录详细的错误日志

### 资源管理
- 及时清理临时文件
- 控制并发线程数量（默认最大4个）
- 合理管理内存使用，处理大文件时注意流式处理

### 配置管理
- 所有用户设置自动持久化到JSON文件
- 配置文件缺失时使用默认值
- 支持配置热重载

## 界面设计原则

### Fluent Design风格
- 使用qfluentwidgets组件
- 默认深色主题 (#1e1e1e背景)
- 统一的圆角设计 (6-8px)
- 标准间距 (12px)

### 用户体验
- 实时进度显示
- 清晰的状态反馈
- 支持文件拖拽上传
- 批量操作支持

## 故障排除

### 常见问题
1. **FFmpeg未找到** - 确保FFmpeg在系统PATH中
2. **whisper配置错误** - 检查whisper.cpp路径和模型文件
3. **API密钥未配置** - 设置相应的环境变量
4. **依赖缺失** - 运行 `pip install -r requirements.txt`
5. **界面显示异常** - 检查DPI设置和主题配置

### 日志位置
- 主程序日志: 控制台输出
- 视频生成日志: `logs/video_generation.log`
- 分镜生成器日志: 控制台输出

## 扩展开发

### 添加新功能模块
1. 创建新的线程类继承WorkerThread
2. 创建对应的页面类继承BasePage
3. 在主窗口中添加导航项
4. 更新配置文件结构

### 集成新的AI模型
1. 在配置文件中添加模型信息
2. 创建相应的API调用函数
3. 更新界面模型选择器
4. 测试模型兼容性

### 自定义主题
1. 修改qfluentwidgets主题设置
2. 更新颜色常量
3. 调整组件样式
4. 测试界面一致性