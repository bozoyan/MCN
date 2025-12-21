# ComfyUI Latent VAE 解码器 (BOZOYAN-Pro V1.1版)

这是一个基于 Python 的独立图形界面工具，旨在无需启动 ComfyUI 服务器的情况下，快速将 `.latent` 或 `.safetensors` 格式的 Latent 文件解码为 PNG 图片。

它采用 **PyQt5** 和 **Fluent Design** 风格组件开发，界面现代美观，并专门针对 **macOS (Apple Silicon)** 进行了深度优化，解决了 MPS 加速下的 BFloat16 兼容性问题。

## ✨ 主要功能

* **无需启动 ComfyUI**：直接调用本地 ComfyUI 核心库，轻量级运行。
* **macOS 深度优化**：
* 支持 **MPS (Metal Performance Shaders)** 硬件加速。
* 内置 **自动权重清洗**，强制将 BFloat16 模型转换为 Float32，彻底解决 Mac 上解码 FLUX 等模型时的崩溃问题。


* **批量处理**：支持拖拽单个文件或整个文件夹，自动扫描 `.latent` 文件。
* **多图解码**：如果 Latent 文件包含 Batch（多张图片），会自动保存所有图片并按序号命名。
* **可视化配置**：内置设置面板，可持久化保存 ComfyUI 路径、VAE 模型路径和默认输出目录。
* **硬件与精度控制**：
* **设备**：支持切换 MPS (Mac) / CUDA (Nvidia) / CPU。
* **精度**：支持 Float32 / BFloat16 / Float16。


* **智能 VAE 预热**：自动识别 SD1.5/SDXL (4通道) 和 FLUX (16通道) 模型并进行预热，消除首次运行卡顿。
* **实时反馈**：卡片式任务列表，显示处理进度和单任务耗时。

## 🛠️ 环境依赖

在运行之前，请确保你已经安装了以下环境：

1. **Python 环境** (建议使用 Conda)。
2. **已安装 ComfyUI** (本工具需要引用 ComfyUI 的 `comfy.sd` 和 `comfy.utils` 模块)。
3. **必要的 Python 库**：

```bash
pip install PyQt5 "PyQt-Fluent-Widgets[full]" torch numpy safetensors pillow scipy

```

## 🚀 快速开始

### 1. 启动程序

在终端中激活你的 ComfyUI 所在的 Python 环境并运行脚本：

```bash
# 示例 (请根据你的实CONDA环境修改)
source ~/.zshrc
conda activate comflowy
python vae.py

```

### 2. 首次配置 (重要)

首次运行时，如果程序未能自动找到路径，请执行以下步骤：

1. 点击左上角标题栏右侧的 **设置图标 (⚙️)**。
2. 在弹出的对话框中填写以下路径：
* **ComfyUI 路径**: 指向你的 ComfyUI 根目录（例如 `/Users/hao/comflowy/ComfyUI`）。
* **VAE 模型路径**: 指向存放 `.safetensors` 或 `.pt` VAE 文件的文件夹。
* **默认输出路径**: 解码后的图片保存位置。


3. 点击 **保存配置**。

> **注意**：修改 ComfyUI 路径后，建议重启程序以确保核心模块被正确加载。

### 3. 解码操作

1. **选择设备与精度**：
* **macOS 用户推荐**：设备选 `MPS`，精度选 `Float32` (最稳定)。
* **Nvidia 用户推荐**：设备选 `CUDA`，精度可选 `Float16`。


2. **选择 VAE 模型**：在下拉框中选择要使用的 VAE（程序会自动尝试选中 `ae.safetensors`）。
3. **导入文件**：
* 点击 **“添加文件”** 按钮选择文件。
* 或者直接将 `.latent` 文件或文件夹 **拖拽** 到右侧列表中。


4. 点击 **“开始解码”**。

## ⚙️ 高级特性说明

### 关于 macOS (MPS) 的 BFloat16 问题

macOS 的 Metal 加速目前对 `BFloat16` 格式支持不佳，导致加载 FLUX 等新版 VAE 时常出现 `Input type (c10::BFloat16) and bias type (float) should be the same` 错误。

**本工具已内置修复方案**：
当你在加载 VAE 时，程序会自动检测并“暴力清洗”模型权重，强制将其转换为你选择的精度（推荐 Float32），从而确保在 Mac 上能稳定运行，无需手动转换模型文件。

### 批量图片保存

如果你的 `.latent` 文件包含 Batch Size > 1 的数据（即一次生成了多张图），本工具会自动识别并保存所有图片。

* **命名规则**：`原文件名_00000.png`, `原文件名_00001.png`...

## ❓ 常见问题排查

**Q: 启动时提示 `ModuleNotFoundError: No module named 'comfy'**`
A: 这说明程序没找到你的 ComfyUI 安装目录。

* **解决方法**：点击设置图标，手动输入正确的 ComfyUI 根目录路径，然后重启程序。

**Q: 提示 `NameError: name 'QDragEnterEvent' is not defined'**`
A: 请确保使用的是最新版的代码（v1.1 及以上），旧版本可能遗漏了导入包。

**Q: 解码出的图片全是噪点或颜色不对？**
A: 可能是 VAE 模型选择错误。

* SD1.5/SDXL 模型生成的 Latent 请使用配套的 `vae-ft-mse-840000` 或 `sdxl_vae.safetensors`。
* FLUX 模型生成的 Latent 请使用 `ae.safetensors`。

**Q: 设置面板里的输入框太短了？**
A: 您可以拉伸设置窗口的边缘，输入框会自动适应宽度。

---

**License**: MIT
**Author**: Hao (Based on ComfyUI & PyQt-Fluent-Widgets)