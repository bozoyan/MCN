#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
ComfyUI Latent VAE解码工具
支持批量解码.latent文件为图像

使用前请确保激活 conda 环境：conda activate comflowy
"""

import os
import sys
import json
import torch
import numpy as np
from typing import List, Dict, Any, Optional
from pathlib import Path
from datetime import datetime
import traceback
from concurrent.futures import ThreadPoolExecutor, as_completed

# PyQt5相关导入
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QProgressBar,
                            QScrollArea, QFrame, QSplitter, QFileDialog,
                            QMessageBox, QPushButton, QComboBox, QSpinBox,
                            QCheckBox, QGroupBox, QTextEdit, QLineEdit)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer, QMimeData, QSize
from PyQt5.QtGui import QDragEnterEvent, QDropEvent, QPixmap, QFont, QIcon, QPalette

# qfluentwidgets导入
from qfluentwidgets import (
    FluentIcon as FIF, PushButton, PrimaryPushButton,
    CardWidget, SubtitleLabel, CaptionLabel, BodyLabel, ProgressBar,
    ComboBox, SpinBox, CheckBox, SwitchButton, Slider,
    Theme, setTheme, setThemeColor, isDarkTheme,
    ScrollArea, SmoothScrollArea, ElevatedCardWidget, SimpleCardWidget,
    MessageBox, Dialog, ThemeColor
)

# ComfyUI相关导入（需要根据ComfyUI安装路径调整）
try:
    # 尝试导入ComfyUI的核心模块
    sys.path.append('/Users/hao/comflowy/ComfyUI')  # 根据实际路径调整
    import comfy.sd
    import comfy.utils
    import comfy.model_management
    import comfy.model_base
except ImportError as e:
    print(f"警告：无法导入ComfyUI模块: {e}")
    print("请确保ComfyUI已正确安装并且路径配置正确")


class VAEDecoderThread(QThread):
    """VAE解码工作线程"""
    progress = pyqtSignal(int, int)  # 当前进度, 总数
    finished_one = pyqtSignal(str, bool, str)  # 文件路径, 成功/失败, 消息
    log_message = pyqtSignal(str)  # 日志消息
    finished_all = pyqtSignal()  # 所有任务完成

    def __init__(self, latent_files: List[str], vae_path: str, output_dir: str,
                 device: str = "cpu", max_workers: int = 2):
        super().__init__()
        self.latent_files = latent_files
        self.vae_path = vae_path
        self.output_dir = output_dir
        # macOS 默认使用 CPU
        self.device = "cpu"
        self.max_workers = max_workers
        self.is_running = False
        self.vae = None

    def load_vae(self):
        """加载VAE模型"""
        try:
            self.log_message.emit(f"正在加载VAE模型: {self.vae_path}")
            # 对于macOS，优先使用CPU
            self.log_message.emit("🍎 使用CPU进行解码（macOS优化）")

            # 加载VAE模型文件
            # 修复 PyTorch 2.6+ 的 weights_only 问题
            try:
                vae_data = comfy.utils.load_torch_file(self.vae_path)
            except Exception as e:
                if "weights_only" in str(e):
                    # 尝试使用 weights_only=False
                    import torch
                    vae_data = torch.load(self.vae_path, map_location=self.device, weights_only=False)
                else:
                    raise

            # 尝试使用 ComfyUI 的各种 VAE 加载方法
            try:
                # 方法1：尝试通过模型管理器加载
                self.vae = comfy.model_management.load_vae(vae_data)
            except:
                try:
                    # 方法2：直接使用 sd 模块的 VAE 类
                    self.vae = comfy.sd.VAE(vae_data)
                except:
                    # 方法3：尝试从字典直接初始化
                    if isinstance(vae_data, dict):
                        # 创建 VAE 实例
                        self.vae = comfy.sd.VAE()
                        # 尝试不同的加载方式
                        for key in ['state_dict', 'vae_dict', 'model']:
                            if key in vae_data:
                                self.vae.load_state_dict(vae_data[key])
                                break
                        else:
                            # 如果没有找到特殊键，尝试直接加载
                            self.vae.load_state_dict(vae_data)
                    else:
                        raise ValueError("无法识别的VAE模型格式")

            # 对于macOS，强制使用CPU以确保兼容性
            if hasattr(self.vae, 'first_stage_model'):
                self.vae.first_stage_model.cpu()
            elif hasattr(self.vae, 'decoder'):
                self.vae.decoder.cpu()
            elif hasattr(self.vae, 'vae'):
                # 如果VAE嵌套在其他属性中
                if hasattr(self.vae.vae, 'first_stage_model'):
                    self.vae.vae.first_stage_model.cpu()

            self.log_message.emit(f"✅ VAE模型加载成功，使用CPU进行解码")
            return True
        except Exception as e:
            # 记录更详细的错误信息
            self.log_message.emit(f"❌ VAE模型加载失败: {str(e)}")
            self.log_message.emit(f"💡 提示：请检查VAE模型文件 {os.path.basename(self.vae_path)} 是否有效")
            self.log_message.emit("   支持的格式: .safetensors, .pt, .pth, .ckpt")
            traceback.print_exc()
            return False

    def decode_single_latent(self, latent_file: str) -> tuple:
        """解码单个latent文件"""
        try:
            # 先检查文件大小
            file_size = os.path.getsize(latent_file)
            if file_size == 0:
                raise ValueError("文件为空")

            # 记录文件信息
            self.log_message.emit(f"🔍 分析文件: {os.path.basename(latent_file)} (大小: {file_size:,} 字节)")

            # 读取文件头部和尾部信息
            with open(latent_file, 'rb') as f:
                # 读取前100字节
                header = f.read(100)
                f.seek(-100, 2)  # 读取最后100字节
                footer = f.read(100)

            # 尝试多种加载方法
            latent_data = None
            load_method = ""

            # 方法1: 标准PyTorch加载
            if header.startswith(b'PK'):
                load_method = "PyTorch ZIP格式"
                try:
                    latent_data = torch.load(latent_file, map_location=self.device)
                except Exception as e:
                    if "weights_only" in str(e):
                        latent_data = torch.load(latent_file, map_location=self.device, weights_only=False)
                    else:
                        self.log_message.emit(f"⚠️ PyTorch加载失败: {str(e)}")
                        latent_data = None

            # 方法2: 备用PyTorch加载（使用不同的map_location）
            if latent_data is None:
                try:
                    import torch
                    # 尝试使用不同的参数
                    latent_data = torch.load(latent_file, map_location='cpu')
                    load_method = "PyTorch CPU加载"
                except Exception as e:
                    self.log_message.emit(f"⚠️ 备用PyTorch加载失败: {str(e)}")

            # 方法3: 直接读取为二进制数据
            if latent_data is None:
                try:
                    with open(latent_file, 'rb') as f:
                        # 尝试跳过可能的头部，直接读取数据
                        f.seek(0)
                        # 查找可能的magic number
                        data = f.read()

                    # 尝试解析为numpy数组
                    import numpy as np
                    # 试试看是否是原始的float32数据
                    if len(data) % 4 == 0:
                        # 假设是4字节float32
                        float_count = len(data) // 4
                        import struct
                        values = struct.unpack(f'{float_count}f', data)

                        # 尝试不同的维度组合
                        for dim in [(1, 4, 32, 32), (1, 4, 64, 64), (4, 32, 32), (4, 64, 64)]:
                            if np.prod(dim) == float_count:
                                latent_tensor = torch.tensor(values).reshape(dim)
                                latent_data = latent_tensor
                                load_method = f"原始float32数据 (解析为{dim})"
                                break
                except Exception as e:
                    self.log_message.emit(f"⚠️ 原始数据解析失败: {str(e)}")

            # 方法4: ComfyUI格式（可能使用特定的序列化方式）
            if latent_data is None:
                try:
                    # 读取所有数据作为字节
                    with open(latent_file, 'rb') as f:
                        data = f.read()

                    # 尝试ComfyUI的格式
                    # ComfyUI latent通常是 (b, c, h, w) 格式的tensor
                    import numpy as np

                    # 跳过可能的元数据头部（查找模式）
                    # 典型的latent应该是4通道，尺寸为32x32或64x64
                    expected_sizes = [4*32*32, 4*64*64, 1*4*32*32, 1*4*64*64]

                    for offset in range(0, min(100, len(data))):
                        for expected_size in expected_sizes:
                            if offset + expected_size * 4 <= len(data):
                                # 尝试解释为float32
                                try:
                                    import struct
                                    float_data = struct.unpack(f'{expected_size}f', data[offset:offset+expected_size*4])

                                    # 转换为tensor
                                    if expected_size == 4*32*32:
                                        latent_tensor = torch.tensor(float_data).reshape(4, 32, 32)
                                    elif expected_size == 4*64*64:
                                        latent_tensor = torch.tensor(float_data).reshape(4, 64, 64)
                                    elif expected_size == 1*4*32*32:
                                        latent_tensor = torch.tensor(float_data).reshape(1, 4, 32, 32)
                                    elif expected_size == 1*4*64*64:
                                        latent_tensor = torch.tensor(float_data).reshape(1, 4, 64, 64)

                                    latent_data = latent_tensor
                                    load_method = f"ComfyUI格式 (偏移{offset}, 尺寸{latent_tensor.shape})"
                                    break
                                except:
                                    continue
                        if latent_data is not None:
                            break
                except Exception as e:
                    self.log_message.emit(f"⚠️ ComfyUI格式解析失败: {str(e)}")

            # 方法5: 尝试不同的pickle协议
            if latent_data is None:
                import pickle
                protocols = [pickle.DEFAULT_PROTOCOL, pickle.HIGHEST_PROTOCOL, 2, 3, 4, 5]
                for protocol in protocols:
                    try:
                        with open(latent_file, 'rb') as f:
                            # 使用pickle.load，但忽略可能的部分损坏
                            latent_data = pickle.load(f)
                        load_method = f"Pickle协议 {protocol}"
                        break
                    except:
                        continue

            if latent_data is None:
                # 输出文件的十六进制内容（前200字节）
                with open(latent_file, 'rb') as f:
                    hex_data = f.read(200).hex()
                    hex_str = ' '.join([hex_data[i:i+2] for i in range(0, min(60, len(hex_data)), 2)])
                self.log_message.emit(f"🔍 文件头部十六进制: {hex_str}...")
                raise ValueError(f"无法识别的文件格式。已尝试多种加载方法均失败。\n"
                               f"文件大小: {file_size:,} 字节\n"
                               f"头部特征: {header[:20]}")

            # 记录成功加载
            self.log_message.emit(f"✅ 成功使用 {load_method} 加载文件")

            # 获取latent张量
            if isinstance(latent_data, dict):
                # 新格式：包含'latent'和其他元数据
                latent_tensor = latent_data.get('latent', latent_data.get('samples'))
                metadata = latent_data.get('metadata', {})

                # 记录文件格式信息
                if latent_tensor is not None:
                    self.log_message.emit(f"📋 {os.path.basename(latent_file)}: 检测到字典格式，包含键: {list(latent_data.keys())[:5]}")
            else:
                # 旧格式：直接是latent张量
                latent_tensor = latent_data
                metadata = {}
                self.log_message.emit(f"📋 {os.path.basename(latent_file)}: 检测到张量格式，形状: {latent_tensor.shape}")

            # 确保latent在CPU上（macOS优化）
            if hasattr(latent_tensor, 'to'):
                latent_tensor = latent_tensor.to('cpu')

            # 使用VAE解码
            with torch.no_grad():
                # 确保输入格式正确
                if len(latent_tensor.shape) == 3:
                    latent_tensor = latent_tensor.unsqueeze(0)  # 添加batch维度

                # 尝试不同的解码方法
                try:
                    decoded = self.vae.decode(latent_tensor)
                except:
                    # 如果直接解码失败，尝试使用其他方法
                    try:
                        # 方法2：使用编码器输出
                        decoded = self.vae.first_stage_model.decode(latent_tensor)
                    except:
                        # 方法3：如果有decode方法，尝试调用
                        if hasattr(self.vae, 'decode_from_latent'):
                            decoded = self.vae.decode_from_latent(latent_tensor)
                        else:
                            raise ValueError("无法找到合适的解码方法")

            # 将解码后的张量转换为图像
            if isinstance(decoded, (list, tuple)):
                decoded = decoded[0]

            # 移除batch维度并转到CPU
            if len(decoded.shape) == 4:
                decoded = decoded[0]

            # 转换为numpy数组
            image_np = decoded.cpu().numpy()

            # 转换CHW到HWC并调整范围到[0, 255]
            if image_np.shape[0] == 3:  # RGB
                image_np = np.transpose(image_np, (1, 2, 0))
            elif image_np.shape[0] == 4:  # RGBA
                image_np = np.transpose(image_np, (1, 2, 0))

            # 归一化到0-255
            image_np = (image_np * 255).clip(0, 255).astype(np.uint8)

            # 保存图像
            from PIL import Image
            if len(image_np.shape) == 3 and image_np.shape[2] == 4:
                # RGBA图像
                pil_image = Image.fromarray(image_np, 'RGBA')
            else:
                # RGB图像
                pil_image = Image.fromarray(image_np, 'RGB')

            # 生成输出文件名
            base_name = os.path.splitext(os.path.basename(latent_file))[0]
            output_path = os.path.join(self.output_dir, f"{base_name}_vae_decoded.png")

            # 如果有元数据，保存为JSON
            if metadata:
                meta_path = os.path.join(self.output_dir, f"{base_name}_metadata.json")
                with open(meta_path, 'w', encoding='utf-8') as f:
                    json.dump(metadata, f, indent=2, ensure_ascii=False)

            pil_image.save(output_path)

            return True, output_path, "解码成功"

        except Exception as e:
            error_msg = f"解码失败: {str(e)}"
            return False, "", error_msg

    def run(self):
        """执行解码任务"""
        self.is_running = True

        # 加载VAE模型
        if not self.load_vae():
            self.finished_all.emit()
            return

        self.log_message.emit(f"开始批量处理 {len(self.latent_files)} 个latent文件...")

        # 使用线程池并发处理
        success_count = 0
        fail_count = 0

        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            # 提交所有任务
            future_to_file = {
                executor.submit(self.decode_single_latent, file): file
                for file in self.latent_files
            }

            # 处理完成的任务
            for i, future in enumerate(as_completed(future_to_file), 1):
                if not self.is_running:
                    break

                file = future_to_file[future]
                try:
                    success, output_path, message = future.result()
                    if success:
                        success_count += 1
                        self.log_message.emit(f"✅ ({i}/{len(self.latent_files)}) {os.path.basename(file)} -> {os.path.basename(output_path)}")
                    else:
                        fail_count += 1
                        self.log_message.emit(f"❌ ({i}/{len(self.latent_files)}) {os.path.basename(file)}: {message}")

                    self.finished_one.emit(file, success, message)
                    self.progress.emit(i, len(self.latent_files))

                except Exception as e:
                    fail_count += 1
                    error_msg = f"处理异常: {str(e)}"
                    self.log_message.emit(f"❌ {os.path.basename(file)}: {error_msg}")
                    self.finished_one.emit(file, False, error_msg)

        # 清理VAE模型（macOS CPU）
        if self.vae:
            if hasattr(self.vae, 'first_stage_model'):
                self.vae.first_stage_model.cpu()
            del self.vae
            self.vae = None
            # macOS CPU 不需要清理 CUDA 缓存

        self.log_message.emit(f"\n🎉 批量处理完成！成功: {success_count}, 失败: {fail_count}")
        self.finished_all.emit()

    def stop(self):
        """停止处理"""
        self.is_running = False


class LatentFileCard(ElevatedCardWidget):
    """Latent文件卡片"""
    remove_requested = pyqtSignal(object)

    def __init__(self, file_path: str):
        super().__init__()
        self.file_path = file_path
        self.status = "pending"  # pending, processing, success, error
        self.setFixedSize(350, 100)  # 增加高度以容纳更多信息
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(6)

        # 文件名和移除按钮
        top_layout = QHBoxLayout()

        self.name_label = BodyLabel(os.path.basename(self.file_path))
        self.name_label.setFont(QFont("PingFang SC", 16))
        self.name_label.setWordWrap(True)
        top_layout.addWidget(self.name_label)

        top_layout.addStretch()

        self.remove_btn = PushButton("×")
        self.remove_btn.setFixedSize(24, 24)
        self.remove_btn.clicked.connect(lambda: self.remove_requested.emit(self))
        top_layout.addWidget(self.remove_btn)

        layout.addLayout(top_layout)

        # 文件大小和格式信息
        info_layout = QHBoxLayout()

        # 获取文件大小
        try:
            file_size = os.path.getsize(self.file_path)
            if file_size < 1024:
                size_str = f"{file_size} B"
            elif file_size < 1024 * 1024:
                size_str = f"{file_size/1024:.1f} KB"
            else:
                size_str = f"{file_size/(1024*1024):.1f} MB"
        except:
            size_str = "未知大小"

        self.size_label = CaptionLabel(size_str)
        self.size_label.setStyleSheet("color: #888888;")
        info_layout.addWidget(self.size_label)

        info_layout.addStretch()

        # 格式信息
        try:
            # 检查文件头部
            with open(self.file_path, 'rb') as f:
                header = f.read(10)
                if header.startswith(b'PK'):
                    format_str = "PyTorch格式"
                else:
                    format_str = "其他格式"
        except:
            format_str = "未知格式"

        self.format_label = CaptionLabel(f"({format_str})")
        self.format_label.setStyleSheet("color: #888888;")
        info_layout.addWidget(self.format_label)

        layout.addLayout(info_layout)

        # 状态和进度
        bottom_layout = QHBoxLayout()

        self.status_label = CaptionLabel("等待处理")
        self.status_label.setStyleSheet("color: #666666;")
        bottom_layout.addWidget(self.status_label)

        bottom_layout.addStretch()

        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedSize(100, 4)
        self.progress_bar.setVisible(False)
        bottom_layout.addWidget(self.progress_bar)

        layout.addLayout(bottom_layout)

    def set_status(self, status: str, message: str = ""):
        self.status = status
        if status == "processing":
            self.status_label.setText("处理中...")
            self.status_label.setStyleSheet("color: #0078d4;")
            self.progress_bar.setVisible(True)
            self.progress_bar.setRange(0, 0)  # 不确定进度
        elif status == "success":
            self.status_label.setText("✅ 完成")
            self.status_label.setStyleSheet("color: #107c10;")
            self.progress_bar.setVisible(False)
            if message:
                self.setToolTip(f"输出: {message}")
        elif status == "error":
            self.status_label.setText("❌ 失败")
            self.status_label.setStyleSheet("color: #d13438;")
            self.progress_bar.setVisible(False)
            if message:
                self.setToolTip(f"错误: {message}")


class VAEDecoderUI(QMainWindow):
    """VAE解码器主界面"""

    def __init__(self):
        super().__init__()
        self.latent_files = []
        self.vae_models = {}
        self.current_thread = None

        # 设置窗口
        self.setWindowTitle("ComfyUI VAE解码工具")
        self.setMinimumSize(1000, 750)  # 调整高度

        # 初始化属性
        self.output_dir = "output/decoded"

        # 初始化UI
        self.init_ui()
        self.load_vae_models()

        # 默认显示文件列表选项卡
        if hasattr(self, 'tab_stack'):
            self.tab_stack.setCurrentIndex(0)

        # 设置样式（深色主题）
        self.setStyleSheet("""
            QMainWindow {
                background-color: #1e1e1e;
            }
            QScrollArea {
                background: transparent;
                border: none;
            }
            QGroupBox {
                font-size: 14px;
                font-weight: bold;
                border: 2px solid #333333;
                border-radius: 6px;
                margin: 6px;
                padding-top: 10px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 5px 0 5px;
                color: #e0e0e0;
            }
        """)

    def init_ui(self):
        """初始化界面"""
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(20, 20, 20, 20)
        main_layout.setSpacing(16)

        # 标题
        title_label = SubtitleLabel("ComfyUI VAE解码工具")
        title_label.setAlignment(Qt.AlignCenter)
        main_layout.addWidget(title_label)

        # 创建分割器
        splitter = QSplitter(Qt.Horizontal)
        main_layout.addWidget(splitter)

        # 左侧控制面板
        left_panel = self.create_control_panel()
        left_panel.setFixedWidth(350)
        splitter.addWidget(left_panel)

        # 右侧选项卡面板
        right_panel = self.create_tab_panel()
        splitter.addWidget(right_panel)

    def create_control_panel(self) -> QWidget:
        """创建控制面板"""
        panel = CardWidget()
        layout = QVBoxLayout(panel)
        layout.setSpacing(12)

        # VAE模型选择
        vae_group = QGroupBox("VAE模型设置")
        vae_layout = QVBoxLayout(vae_group)

        self.vae_combo = ComboBox()
        self.vae_combo.setFixedHeight(32)
        vae_layout.addWidget(self.vae_combo)

        self.refresh_vae_btn = PushButton("刷新模型列表")
        self.refresh_vae_btn.clicked.connect(self.load_vae_models)
        vae_layout.addWidget(self.refresh_vae_btn)

        layout.addWidget(vae_group)

        # 输出设置
        output_group = QGroupBox("输出设置")
        output_layout = QVBoxLayout(output_group)

        # 输出目录
        output_dir_layout = QHBoxLayout()
        self.output_dir_label = BodyLabel("output/decoded")
        output_dir_layout.addWidget(self.output_dir_label)

        self.change_output_btn = PushButton("更改")
        self.change_output_btn.setFixedSize(60, 28)
        self.change_output_btn.clicked.connect(self.change_output_dir)
        output_dir_layout.addWidget(self.change_output_btn)

        output_layout.addLayout(output_dir_layout)
        layout.addWidget(output_group)

        # 处理设置
        process_group = QGroupBox("处理设置")
        process_layout = QVBoxLayout(process_group)

        # 设备选择（macOS 优化）
        device_layout = QHBoxLayout()
        device_layout.addWidget(BodyLabel("设备:"))

        self.device_combo = ComboBox()
        self.device_combo.addItems(["cpu"])
        # macOS 默认使用 CPU，支持 M1 和 Intel 芯片
        self.device_combo.setCurrentText("cpu")
        self.device_combo.setEnabled(False)  # 禁用选择，因为只支持CPU
        device_layout.addWidget(self.device_combo)

        # 添加说明标签
        device_info = CaptionLabel("（macOS CPU优化）")
        device_info.setStyleSheet("color: #888888;")
        device_layout.addWidget(device_info)
        device_layout.addStretch()
        process_layout.addLayout(device_layout)

        # 并发数
        concurrent_layout = QHBoxLayout()
        concurrent_layout.addWidget(BodyLabel("并发数:"))

        self.concurrent_spin = SpinBox()
        self.concurrent_spin.setRange(1, 8)
        self.concurrent_spin.setValue(2)
        concurrent_layout.addWidget(self.concurrent_spin)
        concurrent_layout.addStretch()
        process_layout.addLayout(concurrent_layout)

        layout.addWidget(process_group)

        # 操作按钮
        button_group = QGroupBox("操作")
        button_layout = QVBoxLayout(button_group)

        self.clear_files_btn = PushButton("清空列表")
        self.clear_files_btn.clicked.connect(self.clear_file_list)
        button_layout.addWidget(self.clear_files_btn)

        self.start_btn = PrimaryPushButton("开始解码")
        self.start_btn.clicked.connect(self.start_decoding)
        button_layout.addWidget(self.start_btn)

        self.stop_btn = PushButton("停止处理")
        self.stop_btn.clicked.connect(self.stop_decoding)
        self.stop_btn.setEnabled(False)
        button_layout.addWidget(self.stop_btn)

        layout.addWidget(button_group)

        layout.addStretch()

        # 启用拖拽
        panel.setAcceptDrops(True)
        panel.dragEnterEvent = self.dragEnterEvent
        panel.dropEvent = self.dropEvent

        return panel

    def create_tab_panel(self) -> QWidget:
        """创建选项卡面板"""
        # 创建选项卡容器
        tab_container = QWidget()
        tab_layout = QVBoxLayout(tab_container)
        tab_layout.setContentsMargins(0, 0, 0, 0)

        # 创建选项卡按钮
        tab_button_layout = QHBoxLayout()
        tab_button_layout.setContentsMargins(10, 10, 10, 0)

        self.file_tab_btn = PushButton("文件列表")
        self.file_tab_btn.setCheckable(True)
        self.file_tab_btn.setChecked(True)
        self.file_tab_btn.clicked.connect(lambda: self.switch_tab(0))
        tab_button_layout.addWidget(self.file_tab_btn)

        self.log_tab_btn = PushButton("处理日志")
        self.log_tab_btn.setCheckable(True)
        self.log_tab_btn.clicked.connect(lambda: self.switch_tab(1))
        tab_button_layout.addWidget(self.log_tab_btn)

        tab_button_layout.addStretch()
        tab_layout.addLayout(tab_button_layout)

        # 创建内容堆栈
        from PyQt5.QtWidgets import QStackedWidget
        self.tab_stack = QStackedWidget()

        # 添加文件列表小部件
        self.file_widget = self.create_file_list_widget()
        self.tab_stack.addWidget(self.file_widget)

        # 添加日志小部件
        self.log_widget = self.create_log_widget()
        self.tab_stack.addWidget(self.log_widget)

        tab_layout.addWidget(self.tab_stack)

        # 设置按钮样式
        button_style = """
            QPushButton {
                background-color: #2d2d2d;
                border: 1px solid #404040;
                border-radius: 4px;
                padding: 8px 16px;
                font-size: 13px;
                color: #e0e0e0;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
            }
            QPushButton:checked {
                background-color: #0078d4;
                border-color: #0078d4;
                color: white;
            }
        """
        self.file_tab_btn.setStyleSheet(button_style)
        self.log_tab_btn.setStyleSheet(button_style)

        return tab_container

    def create_file_list_widget(self) -> QWidget:
        """创建文件列表小部件"""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(10, 10, 10, 10)

        # 标题栏
        header_layout = QHBoxLayout()
        header_layout.addWidget(BodyLabel("文件列表"))
        self.file_count_label = CaptionLabel("共 0 个文件")
        header_layout.addWidget(self.file_count_label)
        header_layout.addStretch()
        layout.addLayout(header_layout)

        # 添加文件按钮区域
        button_layout = QHBoxLayout()

        self.add_files_btn = PrimaryPushButton("添加文件")
        self.add_files_btn.clicked.connect(self.add_latent_files)
        button_layout.addWidget(self.add_files_btn)

        self.add_folder_btn = PushButton("添加文件夹")
        self.add_folder_btn.clicked.connect(self.add_folder)
        button_layout.addWidget(self.add_folder_btn)

        layout.addLayout(button_layout)

        # 文件夹输入区域
        folder_input_layout = QHBoxLayout()
        folder_input_layout.addWidget(BodyLabel("文件夹路径:"))

        self.folder_path_edit = QLineEdit()
        self.folder_path_edit.setPlaceholderText("输入包含latent文件的文件夹路径")
        folder_input_layout.addWidget(self.folder_path_edit)

        self.browse_folder_btn = PushButton("浏览")
        self.browse_folder_btn.setFixedSize(60, 28)
        self.browse_folder_btn.clicked.connect(self.browse_folder)
        folder_input_layout.addWidget(self.browse_folder_btn)

        layout.addLayout(folder_input_layout)

        # 设置样式
        self.folder_path_edit.setStyleSheet("""
            QLineEdit {
                background-color: #1e1e1e;
                color: #e0e0e0;
                border: 1px solid #404040;
                border-radius: 4px;
                padding: 8px;
            }
            QLineEdit:focus {
                border-color: #0078d4;
            }
        """)

        # 滚动区域
        scroll_area = SmoothScrollArea()
        scroll_area.setWidgetResizable(True)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)

        # 文件卡片容器
        self.file_container = QWidget()
        self.file_layout = QVBoxLayout(self.file_container)
        self.file_layout.setSpacing(8)
        self.file_layout.addStretch()

        scroll_area.setWidget(self.file_container)
        layout.addWidget(scroll_area)

        # 启用拖拽
        widget.setAcceptDrops(True)
        # 为scroll area也启用拖拽
        scroll_area.setAcceptDrops(True)

        # 重写拖拽事件处理
        widget.dragEnterEvent = lambda e: self.handleDragEnterEvent(e, widget)
        widget.dropEvent = lambda e: self.handleDropEvent(e, widget)
        scroll_area.dragEnterEvent = lambda e: self.handleDragEnterEvent(e, widget)
        scroll_area.dropEvent = lambda e: self.handleDropEvent(e, widget)

        # 设置拖拽提示文本
        if hasattr(widget, 'layout'):
            drag_hint = QLabel("📁 拖拽latent文件或文件夹到这里")
            drag_hint.setAlignment(Qt.AlignCenter)
            drag_hint.setStyleSheet("color: #666666; font-size: 14px; padding: 20px;")
            # 在scroll area上方添加提示
            self.file_layout.insertWidget(0, drag_hint)
            # 保存引用以便删除
            self.drag_hint_label = drag_hint

        return widget

    def handleDragEnterEvent(self, event: QDragEnterEvent, widget):
        """处理文件列表的拖拽进入事件"""
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            # 隐藏拖拽提示
            if hasattr(self, 'drag_hint_label'):
                self.drag_hint_label.hide()

    def handleDropEvent(self, event: QDropEvent, widget):
        """处理文件列表的拖拽放下事件"""
        files = []
        for url in event.mimeData().urls():
            if url.isLocalFile():
                file_path = url.toLocalFile()
                if file_path.endswith('.latent'):
                    files.append(file_path)
                elif os.path.isdir(file_path):
                    # 如果是文件夹，查找所有.latent文件
                    for root, dirs, filenames in os.walk(file_path):
                        for filename in filenames:
                            if filename.endswith('.latent'):
                                files.append(os.path.join(root, filename))

        if files:
            self.add_latent_files_list(files)

    def create_log_widget(self) -> QWidget:
        """创建日志小部件"""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(10, 10, 10, 10)

        # 日志标题
        log_header = QHBoxLayout()
        log_header.addWidget(BodyLabel("处理日志"))
        log_header.addStretch()

        self.clear_log_btn = PushButton("清空")
        self.clear_log_btn.setFixedSize(60, 28)
        self.clear_log_btn.clicked.connect(self.clear_log)
        log_header.addWidget(self.clear_log_btn)
        layout.addLayout(log_header)

        # 日志文本
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        layout.addWidget(self.log_text)

        # 设置样式
        self.log_text.setStyleSheet("""
            QTextEdit {
                background-color: #1e1e1e;
                color: #e0e0e0;
                border: 1px solid #404040;
                border-radius: 4px;
                padding: 8px;
                font-family: 'SF Mono', 'Monaco', 'Consolas', monospace;
                font-size: 12px;
            }
            QTextEdit:focus {
                border-color: #0078d4;
            }
        """)

        return widget

    def switch_tab(self, index: int):
        """切换选项卡"""
        # 更新按钮状态
        self.file_tab_btn.setChecked(index == 0)
        self.log_tab_btn.setChecked(index == 1)
        # 切换内容
        self.tab_stack.setCurrentIndex(index)

    def dragEnterEvent(self, event: QDragEnterEvent):
        """拖拽进入事件"""
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            # 传递给文件列表组件
            if hasattr(self, 'file_widget'):
                self.file_widget.dragEnterEvent(event)

    def dropEvent(self, event: QDropEvent):
        """拖拽放下事件"""
        files = []
        for url in event.mimeData().urls():
            if url.isLocalFile():
                file_path = url.toLocalFile()
                if file_path.endswith('.latent'):
                    files.append(file_path)
                elif os.path.isdir(file_path):
                    # 如果是文件夹，查找所有.latent文件
                    for root, dirs, filenames in os.walk(file_path):
                        for filename in filenames:
                            if filename.endswith('.latent'):
                                files.append(os.path.join(root, filename))

        if files:
            self.add_latent_files_list(files)
            # 切换到文件列表选项卡显示添加的文件
            if hasattr(self, 'tab_stack'):
                self.switch_tab(0)

    def load_vae_models(self):
        """加载VAE模型列表"""
        vae_dir = "/Volumes/BO/AI/models/VAE"
        self.vae_combo.clear()
        self.vae_models = {}

        if not os.path.exists(vae_dir):
            self.add_log(f"❌ VAE模型目录不存在: {vae_dir}")
            return

        # 支持的VAE模型格式
        extensions = ['.safetensors', '.sft', '.pt', '.pth', '.ckpt', '.bin']

        for ext in extensions:
            for file in os.listdir(vae_dir):
                if file.lower().endswith(ext.lower()):
                    # 保留完整的文件名（包括扩展名）
                    model_name = file  # 不再移除扩展名
                    model_path = os.path.join(vae_dir, file)
                    self.vae_models[model_name] = model_path

        # 添加到下拉菜单
        for name in sorted(self.vae_models.keys()):
            self.vae_combo.addItem(name)

        if self.vae_combo.count() > 0:
            self.add_log(f"✅ 已加载 {self.vae_combo.count()} 个VAE模型")
        else:
            self.add_log(f"⚠️ 在 {vae_dir} 中未找到VAE模型")

    def change_output_dir(self):
        """更改输出目录"""
        dir_path = QFileDialog.getExistingDirectory(self, "选择输出目录")
        if dir_path:
            self.output_dir = dir_path
            self.output_dir_label.setText(dir_path)
            self.add_log(f"📁 输出目录更改为: {dir_path}")

    def add_latent_files(self):
        """添加latent文件"""
        files, _ = QFileDialog.getOpenFileNames(
            self,
            "选择Latent文件",
            "",
            "Latent Files (*.latent);;All Files (*)"
        )
        if files:
            self.add_latent_files_list(files)

    def add_latent_files_list(self, files: List[str]):
        """添加latent文件列表"""
        new_files = []
        for file in files:
            if file not in self.latent_files and file.endswith('.latent'):
                self.latent_files.append(file)
                new_files.append(file)

        if new_files:
            # 如果是第一次添加文件，移除拖拽提示
            if hasattr(self, 'drag_hint_label') and len(self.latent_files) > 0:
                self.drag_hint_label.hide()

            self.update_file_list()
            self.add_log(f"📁 已添加 {len(new_files)} 个latent文件")

    def clear_file_list(self):
        """清空文件列表"""
        self.latent_files.clear()
        self.update_file_list()

        # 重新显示拖拽提示
        if hasattr(self, 'drag_hint_label'):
            self.drag_hint_label.show()

        self.add_log("🗑️ 已清空文件列表")

    def update_file_list(self):
        """更新文件列表显示"""
        # 清除旧卡片
        for i in reversed(range(self.file_layout.count())):
            child = self.file_layout.itemAt(i).widget()
            if child and isinstance(child, LatentFileCard):
                child.deleteLater()

        # 添加新卡片
        for file_path in self.latent_files:
            card = LatentFileCard(file_path)
            card.remove_requested.connect(self.remove_file_card)
            self.file_layout.insertWidget(self.file_layout.count() - 1, card)

        # 更新计数
        self.file_count_label.setText(f"共 {len(self.latent_files)} 个文件")

    def remove_file_card(self, card: LatentFileCard):
        """移除文件卡片"""
        if card.file_path in self.latent_files:
            self.latent_files.remove(card.file_path)
            card.deleteLater()
            self.file_count_label.setText(f"共 {len(self.latent_files)} 个文件")

    def start_decoding(self):
        """开始解码"""
        # 检查VAE模型
        if self.vae_combo.currentText() not in self.vae_models:
            self.add_log("❌ 请选择VAE模型")
            return

        # 检查文件列表
        if not self.latent_files:
            self.add_log("❌ 请添加latent文件")
            return

        # 获取输出目录
        output_dir = self.output_dir_label.text()
        if not os.path.exists(output_dir):
            os.makedirs(output_dir, exist_ok=True)
            self.add_log(f"📁 创建输出目录: {output_dir}")

        # 禁用控件
        self.start_btn.setEnabled(False)
        self.stop_btn.setEnabled(True)
        self.add_files_btn.setEnabled(False)
        self.clear_files_btn.setEnabled(False)

        # 重置文件状态
        for i in range(self.file_layout.count()):
            child = self.file_layout.itemAt(i).widget()
            if isinstance(child, LatentFileCard):
                child.set_status("pending")

        # 创建并启动线程
        self.current_thread = VAEDecoderThread(
            self.latent_files,
            self.vae_models[self.vae_combo.currentText()],
            output_dir,
            self.device_combo.currentText(),
            self.concurrent_spin.value()
        )

        self.current_thread.progress.connect(self.update_progress)
        self.current_thread.finished_one.connect(self.on_file_finished)
        self.current_thread.log_message.connect(self.add_log)
        self.current_thread.finished_all.connect(self.on_all_finished)

        # 切换到日志选项卡
        self.switch_tab(1)

        self.current_thread.start()
        self.add_log("🚀 开始VAE解码...")

    def stop_decoding(self):
        """停止解码"""
        if self.current_thread and self.current_thread.isRunning():
            self.current_thread.stop()
            self.current_thread.wait()

        # 启用控件
        self.start_btn.setEnabled(True)
        self.stop_btn.setEnabled(False)
        self.add_files_btn.setEnabled(True)
        self.clear_files_btn.setEnabled(True)

        self.add_log("⏹️ 已停止处理")

    def update_progress(self, current: int, total: int):
        """更新进度"""
        # 可以在这里添加总体进度显示
        pass

    def on_file_finished(self, file_path: str, success: bool, message: str):
        """单个文件处理完成"""
        # 更新对应的文件卡片状态
        for i in range(self.file_layout.count()):
            child = self.file_layout.itemAt(i).widget()
            if isinstance(child, LatentFileCard) and child.file_path == file_path:
                if success:
                    child.set_status("success", message)
                else:
                    child.set_status("error", message)
                break

    def on_all_finished(self):
        """所有文件处理完成"""
        # 启用控件
        self.start_btn.setEnabled(True)
        self.stop_btn.setEnabled(False)
        self.add_files_btn.setEnabled(True)
        self.clear_files_btn.setEnabled(True)

        self.add_log("\n✨ 批量处理完成！")

    def add_log(self, message: str):
        """添加日志"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        log_line = f"[{timestamp}] {message}"
        self.log_text.append(log_line)
        # 自动滚动到底部
        self.log_text.verticalScrollBar().setValue(
            self.log_text.verticalScrollBar().maximum()
        )
        # 自动切换到日志选项卡（可选，如果想切换可以取消注释下面这行）
        # self.switch_tab(1)

    def clear_log(self):
        """清空日志"""
        self.log_text.clear()

    def browse_folder(self):
        """浏览文件夹"""
        folder_path = QFileDialog.getExistingDirectory(self, "选择包含latent文件的文件夹")
        if folder_path:
            self.folder_path_edit.setText(folder_path)

    def add_folder_files(self):
        """从文件夹添加latent文件"""
        folder_path = self.folder_path_edit.text().strip()
        if not folder_path:
            self.add_log("⚠️ 请输入文件夹路径")
            return

        if not os.path.exists(folder_path):
            self.add_log(f"❌ 文件夹不存在: {folder_path}")
            return

        # 查找所有latent文件
        latent_files = []
        for root, dirs, filenames in os.walk(folder_path):
            for filename in filenames:
                if filename.endswith('.latent'):
                    latent_files.append(os.path.join(root, filename))

        if latent_files:
            self.add_latent_files_list(latent_files)
            self.folder_path_edit.clear()
        else:
            self.add_log(f"⚠️ 文件夹中没有找到.latent文件: {folder_path}")

    def add_folder(self):
        """添加文件夹（通过选择）"""
        folder_path = QFileDialog.getExistingDirectory(self, "选择包含latent文件的文件夹")
        if folder_path:
            self.folder_path_edit.setText(folder_path)
            # 自动触发添加
            self.add_folder_files()

    def closeEvent(self, event):
        """关闭事件"""
        if self.current_thread and self.current_thread.isRunning():
            reply = MessageBox(
                "处理正在进行中",
                "有文件正在处理中，确定要退出吗？",
                self
            )
            reply.yesButton.setText("确定退出")
            reply.cancelButton.setText("取消")

            if reply.exec():
                self.current_thread.stop()
                self.current_thread.wait()
                event.accept()
            else:
                event.ignore()
        else:
            event.accept()


def main():
    """主函数"""
    # 设置高DPI支持
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps)

    # 创建应用
    app = QApplication(sys.argv)

    # 设置深色主题
    setTheme(Theme.DARK)
    # 设置主题颜色（可选）
    setThemeColor('#0078d4')  # Windows 11 蓝色

    # 设置字体（macOS 使用 SF Pro 或 PingFang）
    font = QFont("PingFang SC", 18)  # macOS 中文字体
    app.setFont(font)

    # 创建主窗口
    window = VAEDecoderUI()
    window.show()

    # 添加初始日志
    window.add_log("🎯 VAE解码工具已启动")
    window.add_log("💡 提示：支持拖拽.latent文件到界面")

    # 运行应用
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()