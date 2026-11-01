# 深度原生模块来源

`depth-native/` 是 Reveric 维护的独立 C++ 任务进程及构建、验证工具，不是 Flutter 插件，
也不是未经修改的上游源码镜像。应用通过进程协议调用它。

## Video Depth Anything

- 上游：https://github.com/DepthAnything/Video-Depth-Anything
- 钉选 commit：`4f5ae23172ba60fd7bc11ef671cca678842c7072`
- 来源模型：`depth-anything/Video-Depth-Anything-Small`
- Small 权重 SHA-256：`13379300b739e659f076a59d52e9801bd8d38c541a7e71f73bbca4dcfb013609`
- 许可证：Apache-2.0，保留在 `depth-native/LICENSE.vda`。

本地实现将窗口选择、关键帧对齐和接缝混合算法移植到 C++，以分窗口文件读写限制内存增长，
增加全片灰度映射、JSONL 进度和宿主退出检测。模型转换与发布由独立的
`video-depth-anything-small-onnx` 仓库维护，此处不保留模型导出或发布脚本。

## ONNX Runtime

- 上游：https://github.com/microsoft/onnxruntime
- 版本：1.31.0
- commit：`402979ac1bef89dcd55add41eaa7277c407599eb`
- 许可证：MIT；构建时从官方 SDK 复制 `LICENSE` 和 `ThirdPartyNotices.txt`，随应用分发。

macOS ARM64 使用算子清单、CPU 后端与 LTO 自行构建，最低部署目标为 macOS 12。
Windows x64 使用校验 SHA-256 的官方 CPU SDK。下载地址与校验值位于对应准备脚本。
上游源码、SDK、模型、编译产物和性能测试视频均留在 Git 忽略的 `build/depth-native/`。

升级模型或运行库时，重新核对 `required_operators.config`，覆盖优化器生成的融合算子，
运行原生测试、数值比较和桌面媒体集成测试，再检查各平台打包与动态库加载。
Windows 与 macOS 12 实机验收不由本机 ARM64 构建结果替代。
