# 🎬 BOZO-MCN 分镜脚本与图片生成器 v2.0
一个基于 PyQt5 和 qfluentwidgets 开发的专业AI分镜创作工具，支持一键生成故事分镜标题、描述和配图。

## ✨ 主要功能

### 🎭 分镜脚本生成
- **智能标题生成**: 根据故事内容自动生成9个完整的分镜标题
- **详细描述生成**: 为每个分镜生成专业的视频脚本描述
- **导演级镜头语言**: 包含景别、视角、运镜等专业术语
- **模板管理**: 支持自定义和管理提示词模板

### 🎨 AI图片生成
- **多模型支持**: 支持Flux、SDXL、SD1.5等多种生成模型
- **参数自定义**: 可调节采样步数、引导强度、采样器等参数
- **批量生成**: 支持1-20张图片的批量生成
- **智能提示词**: 自动生成专业的英文AI绘图提示词

### 🛠️ 高级功能
- **一键生成**: 输入故事内容，一键完成所有步骤
- **实时进度**: 显示详细的生成进度和状态
- **图片预览**: 实时预览生成的图片
- **导出功能**: 支持导出Markdown文档和批量保存图片
- **配置管理**: 完整的配置文件管理系统

## 🚀 快速开始

### 环境要求
- Python 3.8+
- ModelScope API密钥

### 安装步骤

1. **克隆或下载项目**
```bash
git clone <repository-url>
cd MCN
```

2. **安装依赖**
```bash
pip install -r requirements_storyboard.txt
```

3. **配置API密钥**
```bash
# 方法1: 设置环境变量
export MODELSCOPE_SDK_TOKEN="your_api_key_here"

# 方法2: 在应用设置中配置
```

4. **运行应用**
```bash
python run_storyboard.py
```

## 📖 使用指南

### 基本使用流程

1. **输入故事内容**
   - 在左侧文本框输入您的故事或创意描述
   - 可以使用"加载示例"按钮查看示例内容

2. **生成分镜标题**
   - 点击"生成分镜标题"按钮
   - AI会分析内容并生成9个分镜标题

3. **生成分镜描述**
   - 基于标题生成分镜描述
   - 包含详细的镜头语言和画面描述

4. **生成图片**
   - 自动生成AI绘图提示词
   - 批量生成配图

5. **导出结果**
   - 导出为Markdown文档
   - 批量保存图片

### 高级功能

#### 📝 模板管理
- 点击"模板管理"按钮
- 可以编辑、保存、删除自定义模板
- 支持故事标题、描述、图片提示词等多种模板

#### ⚙️ 参数设置
- 点击"图片参数"按钮
- 调整生成模型、图片尺寸、采样参数等
- 支持保存为默认设置

#### 🔑 API配置
- 在设置页面配置ModelScope API密钥
- 支持自定义API基础URL和文本模型

## 🏗️ 项目结构

```
MCN/
├── storyboard_generator.py     # 主程序文件
├── run_storyboard.py          # 启动脚本
├── requirements_storyboard.txt # 依赖包列表
├── README_storyboard.md       # 项目文档
├── storyboard_config.json     # 配置文件（自动生成）
├── output/                     # 输出目录
│   ├── <model_name>/          # 按模型分类的图片
├── temp/                       # 临时文件
└── templates/                  # 模板文件
```

## ⚙️ 配置说明

### 配置文件结构
应用使用 `storyboard_config.json` 存储配置：

```json
{
  "api": {
    "base_url": "https://api-inference.modelscope.cn/v1/",
    "text_model": "Qwen/Qwen3-235B-A22B-Thinking-2507",
    "enable_thinking": true,
    "api_key": ""
  },
  "image_models": {
    "default": "bozoyan/F_fei",
    "available": [...]
  },
  "image_params": {
    "default": {...}
  },
  "prompt_templates": {...},
  "ui": {...}
}
```

### 环境变量
- `MODELSCOPE_SDK_TOKEN`: ModelScope API密钥

## 🎯 支持的模型

### 文本生成模型
- Qwen/Qwen3-235B-A22B-Thinking-2507 (默认)

### 图片生成模型
- Flux (bozoyan/F_fei) - 高质量，速度约60秒
- SDXL (AI-ModelScope/stable-diffusion-xl-base-1.0) - 平衡，速度约20秒  
- SD1.5 (AI-ModelScope/stable-diffusion-v1-5) - 快速，速度约10秒

## 🔧 故障排除

### 常见问题

1. **API密钥未配置**
   - 在设置页面配置或设置环境变量
   - 确保密钥格式正确

2. **图片生成失败**
   - 检查网络连接
   - 确认API配额充足
   - 尝试更换生成模型

3. **启动失败**
   - 检查Python版本（需要3.8+）
   - 确认所有依赖包已安装
   - 检查是否缺少系统字体

4. **界面显示异常**
   - 尝试切换主题
   - 检查系统DPI设置

### 日志查看
应用运行时会输出详细日志，包括：
- API请求状态
- 图片生成进度
- 错误信息和调试信息

## 🤝 开发说明

### 技术栈
- **GUI框架**: PyQt5 + qfluentwidgets
- **AI接口**: ModelScope API
- **图像处理**: PIL/Pillow
- **配置管理**: JSON配置文件

### 扩展开发
项目采用模块化设计，支持：
- 自定义模板
- 新增生成模型
- 扩展导出格式
- 添加新的AI功能

## 📄 许可证

本项目基于 MIT 许可证开源。

## 🙏 致谢

- ModelScope - 提供强大的AI模型服务
- PyQt5 & qfluentwidgets - 优秀的GUI框架
- OpenAI - 兼容的API接口

---

如有问题或建议，欢迎提交Issue或Pull Request！ 🚀
