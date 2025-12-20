# BOZO-MCN 多媒体编辑器 - Gemini 互动指南

## 项目概述
**BOZO-MCN 多媒体编辑器 2.0** 是一个基于 **PyQt5** 和 **PyQt-Fluent-Widgets[full]** 框架重新开发的专业多媒体处理工具。它采用了 Fluent Design 设计语言，旨在提供现代化、高性能且用户体验友好的桌面应用环境。

### 核心目标
1.  **框架迁移**：将现有的插件（包括 ComfyUI 插件、Gradio 程序或其他 Python 库）转换并集成到 PyQt5 + PyQt-Fluent-Widgets[full] 框架中。
2.  **现代化 UI**：全面使用 `PyQt-Fluent-Widgets[full]` 组件，确保界面符合 Fluent Design 规范。
3.  **高性能异步**：通过多线程架构确保耗时任务（视频处理、AI 生成等）不会阻塞 UI 界面。

## Gemini 互动规则
为了确保我们能够高效协作，请遵循以下规则：

### 1. 语言偏好
-   **全程中文交流**：所有的沟通、解释、建议及代码注释（除非是必要的 API 命名）都应使用中文。

### 2. 技术栈约束
-   **UI 框架**：必须使用 `PyQt5` 和 `PyQt-Fluent-Widgets[full]`。
-   **设计风格**：遵循 Fluent Design 风格。
-   **异步处理**：耗时操作必须继承 `WorkerThread` (QThread) 并在后台运行，通过信号（Signal）与主线程通信。
-   **组件库**：优先使用 `-   **UI 框架**：必须使用 `PyQt5` 和 `PyQt-Fluent-Widgets[full]`。
` 提供的组件（如 `PrimaryPushButton`, `LineEdit`, `InfoBar`, `Pivot` 等），避免使用原始的 `QtWidgets` 样式。

### 3. 代码架构规范
-   **页面结构**：所有新功能页面应继承自 `BasePage` 或遵循项目已有的页面组织方式。
-   **线程安全**：严禁在子线程中直接修改 UI 元素，必须使用信号槽机制。
-   **资源管理**：确保临时文件（存储在 `temp/`, `SRT/`, `speech/` 等）的合理创建与清理。

### 4. 插件转换逻辑
在转换 ComfyUI、Gradio 或其他 Python 程序时：
-   **逻辑解耦**：将核心算法逻辑从原始 UI 框架中剥离。
-   **界面重构**：使用 -   **UI 框架**：必须使用 `PyQt5` 和 `PyQt-Fluent-Widgets[full]`。
` 重新设计交互界面。
-   **进度反馈**：必须为长耗时任务添加 `ProgressBar` 和 `InfoBar` 反馈。

## 项目结构关键点
-   `MCN.py`: 主程序入口，包含主窗口逻辑及导航。
-   `WorkerThread`: 位于 `MCN.py` 中的异步任务基类。
-   `BasePage`: 页面基类。
-   `requirements.txt`: 核心依赖清单。
-   `templates/`: 存放相关配置文件或模板。

## 开发常用命令
-   **运行程序**：`python MCN.py`
-   **检查依赖**：`python check_requirements.py`
-   **安装依赖**：`pip install -r requirements.txt`

---
*此文件作为 Gemini 的上下文指令，旨在确保 AI 在协助开发时保持技术栈的一致性和语言的准确性。*
