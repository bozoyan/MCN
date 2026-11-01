# Reveric 深度原生模块

此模块提供 `reveric-depth-native` 独立任务进程、ONNX Runtime 构建打包及性能验证工具。
上游来源、版本和本地改动见 [depth-native_UPSTREAM.md](../depth-native_UPSTREAM.md)。
模型导出与 Hugging Face 发布由独立的 `video-depth-anything-small-onnx` 仓库维护。

## 文件职责

| 文件 | 职责 |
|---|---|
| `depth.cpp` / `depth.h` | RGB 归一化、32 帧窗口推理、窗口间对齐 |
| `depth_io.cpp` / `depth_io.h` | 分批百分位计算与全片灰度映射 |
| `main.cpp` | 独立进程入口、JSONL 进度、宿主退出检测 |
| `CMakeLists.txt` / `depth_io_test.cpp` | 构建、安装与原生 IO 回归测试 |
| `prepare-product-macos.sh` / `prepare-product-windows.ps1` | 准备桌面 CPU 运行包 |
| `build-reduced-macos.sh` / `package_reduced.py` | 构建 CPU 裁剪库、签名与体积测量 |
| `embed-macos.sh` | Xcode 阶段编译、嵌入和签名 |
| `required_operators.config` / `reduced_config.py` | 固定算子清单及升级时的清单审计 |
| `run-native.sh` / `bounded-run.py` | 原生媒体基准与内存预算运行器 |
| `benchmark_report.py` / `memory_report.py` | 耗时、执行后端、内存与输出一致性比较 |
| `dynamic-validate.py` / `validate-dynamic-profiles.py` | 动态画幅的官方 PyTorch 数值对照 |
| `requirements-validation.txt` | 可选验证依赖；产品构建不依赖这些包 |
| `LICENSE.vda` | 上游 Apache-2.0 许可证 |

## 应用接入

- Dart 调用位于 `lib/shared/services/depth/`，应用级控制器由 `lib/shared/providers/depth.dart` 装配。
- 视频菜单“深度动作捕捉”在模型就绪时直接开始；未安装时提示准备模型。制作页工具栏可重新查看任务。
- 模型放应用数据目录的 `cache/modles/`，每次复用前检查大小和 SHA-256；任务记录和临时文件放 `cache/depth/`。
- 默认从 [looplj/video-depth-anything-small-onnx](https://huggingface.co/looplj/video-depth-anything-small-onnx) 匿名下载模型，固定 revision 为 `ff810849333df46d37ea18a885fc11689661fe96`，文件名为 `video-depth-anything-small-dynamic-fp32.onnx`。
- `REVERIC_DEPTH_MODEL_SOURCE` 仍可通过 Dart define 或环境变量覆盖为本地模型或其他 HTTPS 来源；HTTP 只用于本机测试服务器。下载后必须通过相同的大小与 SHA-256 校验。
- 原生程序随应用打包：macOS 为 `Contents/Resources/depth/bin/reveric-depth-native`，Windows 为应用目录下的 `depth/bin/reveric-depth-native.exe`。
- 开发时可用 `REVERIC_DEPTH_EXECUTABLE` 指定运行程序。应用运行时不依赖 Python、PyTorch 或模型导出工具。
- FFmpegKit 处理解码和编码，保留旋转与 VFR 时间戳；结果恢复显示尺寸，输出无音轨 H.264 MP4。成功后入素材库并挂接派生节点，来源变化时仍保留素材。
- 任务串行运行，每个任务创建一个 Session，在窗口间复用。关闭弹窗或切换页面不停止任务；取消和应用退出会停止处理。

## 构建

所有命令从项目根目录运行。产物、依赖和验证数据都在 `build/depth-native/`，不进入源码目录。

macOS ARM64：

```bash
bash third/depth-native/prepare-product-macos.sh
fvm flutter build macos --debug
```

准备脚本下载校验过的 SDK，使用钉选的 ONNX Runtime 1.31.0 源码、
`required_operators.config` 和独立的构建 Python 环境生成裁剪库。
它不读取本机模型导出环境，也不下载模型或 PyTorch。需要 CMake、Ninja、Python 3 和 Apple 工具链。
Xcode 构建阶段自动调用 `embed-macos.sh`，使用应用签名身份；ad-hoc 开发签名不启用要求 Team ID 的库验证。

Windows x64：

```powershell
./third/depth-native/prepare-product-windows.ps1
fvm flutter build windows
```

Windows 使用校验过的官方 CPU SDK，将 DLL 与进程放在同一 `bin/` 目录。
Android 不注册此能力，也不打包这些原生文件。Windows 实际构建与运行仍需 Windows 环境验收。

## 模型与进程合同

- 模型：动态宽高、FP32、opset 17；输入 `frames: [1,32,3,H,W]`，输出 `depth: [1,32,H,W]`。
- 模型大小：116,528,885 字节；SHA-256：`eb5926ad36741e911c43cb010cc2f74604aa524744feeaf57979c178ede4bb99`。
- H/W 为 14 的倍数，推理最多 141,120 像素。常见横屏为 504×280、竖屏为 280×504、方形为 280×280。
- RGB24 先除以 255，再按 mean `[0.485,0.456,0.406]`、std `[0.229,0.224,0.225]` 归一化。
- 输出是相对逆深度，不是米制距离或人体骨骼。灰度预览使用全片统一范围。

```text
reveric-depth-native [--job] MODEL RGB FLOATS GRAY WIDTH HEIGHT FRAMES PROVIDER
```

`RGB`、`FLOATS`、`GRAY` 分别为原始 RGB24、float32 深度、8 位灰度文件。
产品 `--job` 模式只接受 CPU（`PROVIDER=0`），stdout 为 JSONL 进度，stderr 为诊断。
宿主必须保持 stdin 管道打开；关闭管道时进程退出。宿主等待进程退出后清理任务临时文件。
验证模式保留 `PROVIDER=1` 的 CoreML 分支，需要自行提供支持 CoreML 的完整版 SDK；产品裁剪包仅包含 CPU。

## 验证与性能比较

原生 IO 回归：

```bash
cmake -S third/depth-native -B build/depth-native/native-tests \
  -DORT_ROOT="$PWD/build/depth-native/ort-reduced-1.31.0/dist"
cmake --build build/depth-native/native-tests --parallel 4
ctest --test-dir build/depth-native/native-tests --output-on-failure
```

应用与原生媒体测试：

```bash
fvm flutter test test/shared/production/depth_test.dart
fvm flutter test test/shared/production/depth_native_test.dart test/shared/production/depth_task_test.dart \
  --dart-define=FFMPEG_TEST_BIN=/path/to/ffmpeg
fvm flutter test integration_test/production/depth_capture_test.dart -d macos \
  --dart-define=DEPTH_TEST_MODEL=/path/to/model.onnx
```

原生专项测试额外提供 `DEPTH_TEST_BIN` 和 `DEPTH_TEST_MODEL` 时执行真实模型与取消用例，否则该用例显式跳过。
宿主集成测试使用实际打包的 FFmpegKit、原生进程和模型；临时数据库不接触用户数据。

macOS CPU 媒体基准（固定 24 fps，仅供性能比较，不是产品帧率策略）：

```bash
DEPTH_MODEL=/path/to/model.onnx \
  bash third/depth-native/run-native.sh build/depth-native/benchmark /path/to/video.mp4 448 252 48
```

程序默认取 `build/depth-native/native-macos/reveric-depth-native`，可用 `DEPTH_NATIVE_BIN` 覆盖。
运行日志含 `/usr/bin/time -l` 内存测量，输入、中间深度及对比视频都写入指定目录。
更长任务可用 `bounded-run.py LOG COMMAND ...`，超过 6 GiB 采样物理内存或 15 分钟停止。

保留的比较工具：

- `benchmark_report.py WORK`：读取 `cpu/`、`cold/`、`warm/` 下的 `run.log`、`profile_*.json`、`native.f32`，比较 CPU 与 CoreML 冷/热缓存。采集时设置 `DEPTH_PROFILE`，CoreML 任务设置 `DEPTH_COREML_CACHE`。需要 NumPy。
- `memory_report.py WORK`：读取 `baseline-6/`、`baseline-30/`、`stream-6/`、`stream-30/`，比较 448×252、144/720 帧的全量缓存与分窗口版本；校验 float32/灰度文件哈希，只使用标准 Python 库。
- `validate-dynamic-profiles.py [WIDTHxHEIGHT ...]`：依次执行准备、官方 PyTorch、ONNX 和误差比较，支持六种已验收尺寸。使用 `build/depth-native/venv/bin/python`；可按 `requirements-validation.txt` 准备 Python 3.12 验证环境。

动态画幅验证须自行准备钉选的上游源码目录、官方 Small `.pth`、动态 ONNX 和
`second-video/input.rgb`（至少 32 帧、448×252 RGB24），置于 `build/depth-native/` 下相应位置。
参考分支直接加载未经导出适配的上游模型，不依赖本仓库以外的导出脚本。

当前 CPU 验证：

- ONNX Runtime 1.31.0 裁剪库约 7.74 MB（gzip 约 3.11 MB），相对官方 44.83 MB 减少约 82.73%。
- 库和进程以 macOS 12 为最低部署目标编译；尚未在 macOS 12 实机验收。
- 145 帧、448×252 输出与完整版 1.31.0 CPU 逐值相同。六种画幅与官方 PyTorch 对照均通过归一化 RMSE < 0.001、相关系数 > 0.999。
- 1000 帧、280×280 的 40 秒视频完成推理及 MP4 全片解码，单次峰值 memory footprint 约 1.17 GB。
- macOS 宿主旋转/VFR 测试输出 64×96、8 帧、440 ms，帧时间戳一致且素材与节点登记成功。

历史性能基线使用 ONNX Runtime 1.23.2，保留在 Git 忽略的 `coreml-benchmark/` 和 `memory-benchmark/`，
不能代替当前版本验收。CPU/CoreML 145 帧任务的推理时间分别约 45.29/21.27 秒；
分窗口版本的 CoreML 6 秒/30 秒输入峰值约 5.640/5.658 GB。均为单机、单次测量，不能当作跨机器性能保证。
