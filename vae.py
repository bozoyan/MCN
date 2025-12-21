#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
ComfyUI Latent VAE 解码工具 (BOZOYAN-Pro v1.1 - Fixed Imports)
修复: 补全 QDragEnterEvent/QDropEvent 导入，解决 NameError。
功能:
1. 配置对话框 (路径记忆)。
2. 硬件/精度控制 (MPS/CPU/CUDA, Float32/BFloat16)。
3. 自动选中 ae.safetensors。
4. 批量解码 + 计时。
"""

import os
import sys
import time
import json
import torch
import numpy as np
from typing import List
from concurrent.futures import ThreadPoolExecutor

# --- PyQt5 & Fluent Widgets 导入 ---
try:
    from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                                QHBoxLayout, QFileDialog, QLineEdit, QDesktopWidget,
                                QDialog, QFormLayout, QLabel)
    from PyQt5.QtCore import Qt, QThread, pyqtSignal, QSettings
    # 修复：补全 QDragEnterEvent, QDropEvent
    from PyQt5.QtGui import QFont, QIcon, QDragEnterEvent, QDropEvent
    
    from qfluentwidgets import (
        PushButton, PrimaryPushButton, CardWidget, SubtitleLabel, CaptionLabel, 
        BodyLabel, ProgressBar, ComboBox, Theme, setTheme, setThemeColor,
        SmoothScrollArea, MessageBox, ToolButton, FluentIcon
    )
except ImportError:
    print("❌ 缺少界面库，请安装: pip install PyQt5 \"PyQt-Fluent-Widgets[full]\"")
    sys.exit(1)

# ================= 全局配置管理 =================
class ConfigManager:
    def __init__(self):
        self.settings = QSettings("ComfyTool", "VAEDecoder")
        
        # 默认值
        self.defaults = {
            "COMFYUI_PATH": "/Users/hao/comflowy/ComfyUI",
            "VAE_MODELS_DIR": "/Volumes/BO/AI/models/VAE",
            "DEFAULT_OUTPUT_DIR": os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")
        }

    def get(self, key):
        return self.settings.value(key, self.defaults.get(key, ""))

    def set(self, key, value):
        self.settings.setValue(key, value)

# 初始化配置
CONFIG = ConfigManager()

# 获取当前路径（用于注入环境）
COMFYUI_PATH = CONFIG.get("COMFYUI_PATH")
VAE_MODELS_DIR = CONFIG.get("VAE_MODELS_DIR")

# --- 环境注入 ---
if os.path.exists(COMFYUI_PATH):
    if COMFYUI_PATH not in sys.path:
        sys.path.append(COMFYUI_PATH)
else:
    print(f"⚠️ 警告: 找不到 ComfyUI 路径: {COMFYUI_PATH}，请在 GUI 设置中修正。")

# --- 核心模块导入 ---
HAS_COMFY = False
try:
    try:
        from safetensors.torch import load_file as load_safetensors
        HAS_SAFETENSORS = True
    except ImportError:
        HAS_SAFETENSORS = False

    import comfy.sd
    import comfy.utils
    HAS_COMFY = True
    print("✅ 成功导入 ComfyUI 核心模块")
except ImportError as e:
    print(f"❌ 导入失败 (如果是首次运行，请点击设置配置路径): {e}")


class ConfigDialog(QDialog):
    """设置对话框"""
    config_saved = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("环境配置")
        self.resize(500, 300)
        self.setStyleSheet("background-color: #2b2b2b; color: white;")
        
        layout = QVBoxLayout(self)
        form_layout = QFormLayout()
        form_layout.setSpacing(15)

        # 样式
        style = "QLineEdit { padding: 8px; border-radius: 5px; background: #333; border: 1px solid #555; color: white; }"
        label_style = "QLabel { font-size: 14px; font-weight: bold; color: #ddd; }"

        # 输入框
        self.comfy_edit = QLineEdit(CONFIG.get("COMFYUI_PATH"))
        self.comfy_edit.setStyleSheet(style)
        self.comfy_edit.setMinimumWidth(300)
        self.vae_edit = QLineEdit(CONFIG.get("VAE_MODELS_DIR"))
        self.vae_edit.setStyleSheet(style)
        self.vae_edit.setMinimumWidth(300)
        self.out_edit = QLineEdit(CONFIG.get("DEFAULT_OUTPUT_DIR"))
        self.out_edit.setStyleSheet(style)
        self.out_edit.setMinimumWidth(300)

        # 添加行
        l1 = QLabel("ComfyUI 路径:"); l1.setStyleSheet(label_style)
        form_layout.addRow(l1, self.comfy_edit)
        
        l2 = QLabel("VAE 模型路径:"); l2.setStyleSheet(label_style)
        form_layout.addRow(l2, self.vae_edit)
        
        l3 = QLabel("默认输出路径:"); l3.setStyleSheet(label_style)
        form_layout.addRow(l3, self.out_edit)

        layout.addLayout(form_layout)
        layout.addStretch(1)

        # 提示
        tips = CaptionLabel("注: 修改 ComfyUI 路径后建议重启程序。")
        tips.setStyleSheet("color: #888;")
        layout.addWidget(tips)
        
        # 按钮
        btn_layout = QHBoxLayout()
        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        
        save_btn = PrimaryPushButton("保存配置")
        save_btn.clicked.connect(self.save_config)
        
        btn_layout.addWidget(cancel_btn)
        btn_layout.addWidget(save_btn)
        layout.addLayout(btn_layout)

    def save_config(self):
        CONFIG.set("COMFYUI_PATH", self.comfy_edit.text())
        CONFIG.set("VAE_MODELS_DIR", self.vae_edit.text())
        CONFIG.set("DEFAULT_OUTPUT_DIR", self.out_edit.text())
        self.accept()
        self.config_saved.emit()


class VAEDecoderThread(QThread):
    progress = pyqtSignal(int, int)
    finished_one = pyqtSignal(str, bool, str)
    log_message = pyqtSignal(str)
    finished_all = pyqtSignal()
    started_processing = pyqtSignal(str)

    def __init__(self, latent_files: List[str], vae_path: str, output_dir: str, 
                 device_mode: str, dtype_mode: str):
        super().__init__()
        self.latent_files = latent_files
        self.vae_path = vae_path
        self.output_dir = output_dir
        self.is_running = False
        self.vae = None
        
        # --- 硬件与精度配置 ---
        self.device_mode = device_mode # 'MPS', 'CPU', 'CUDA'
        self.dtype_mode = dtype_mode   # 'Float32', 'BFloat16', 'Float16'
        
        # 解析 Device
        if self.device_mode == "MPS" and torch.backends.mps.is_available():
            self.device = torch.device("mps")
        elif self.device_mode == "CUDA" and torch.cuda.is_available():
            self.device = torch.device("cuda")
        else:
            self.device = torch.device("cpu")
            
        # 解析 Dtype
        if self.dtype_mode == "BFloat16":
            self.dtype = torch.bfloat16
        elif self.dtype_mode == "Float16":
            self.dtype = torch.float16
        else:
            self.dtype = torch.float32

        self.offload_device = torch.device("cpu")

    def load_vae(self):
        try:
            self.log_message.emit(f"🔄 读取 VAE: {os.path.basename(self.vae_path)}")
            self.log_message.emit(f"⚙️ 模式: {self.device_mode} | 精度: {self.dtype_mode}")

            vae_data = comfy.utils.load_torch_file(self.vae_path)
            
            # --- 动态权重清洗 ---
            # 根据用户选择的精度，强制转换权重，防止不兼容
            self.log_message.emit(f"🧹 正在转换权重格式至 {self.dtype_mode}...")
            new_vae_data = {}
            for k, v in vae_data.items():
                if isinstance(v, torch.Tensor):
                    # 总是转为目标精度
                    new_vae_data[k] = v.to(dtype=self.dtype)
                else:
                    new_vae_data[k] = v
            
            vae_data = new_vae_data
            del new_vae_data 
            
            self.log_message.emit("🏗️ 构建 VAE 模型...")
            self.vae = comfy.sd.VAE(vae_data)
            
            if hasattr(self.vae, 'first_stage_model'):
                self.vae.first_stage_model.to(self.device)
                self.vae.device = self.device
            
            # --- 智能预热 ---
            try:
                # 尝试预热，使用用户选择的 dtype
                dummy = torch.zeros((1, 4, 8, 8), device=self.device, dtype=self.dtype)
                self.vae.decode(dummy)
                self.log_message.emit(f"✅ VAE 预热成功 (4-Channel)")
            except RuntimeError as re:
                if "channels" in str(re):
                    try:
                        dummy = torch.zeros((1, 16, 8, 8), device=self.device, dtype=self.dtype)
                        self.vae.decode(dummy)
                        self.log_message.emit(f"✅ VAE 预热成功 (16-Channel)")
                    except Exception as e:
                        self.log_message.emit(f"⚠️ 预热失败(忽略): {e}")
                else:
                    self.log_message.emit(f"⚠️ 预热警告: {re}")

            return True
        except Exception as e:
            self.log_message.emit(f"❌ VAE 加载失败: {str(e)}")
            return False

    def load_latent_data(self, file_path):
        if HAS_SAFETENSORS and (file_path.endswith('.safetensors') or file_path.endswith('.latent')):
            try:
                return load_safetensors(file_path)
            except:
                pass
        try:
            return torch.load(file_path, map_location=self.offload_device)
        except:
            return torch.load(file_path, map_location=self.offload_device, weights_only=False)

    def decode_single(self, latent_file: str) -> tuple:
        start_time = time.time()
        try:
            # 1. 读取
            try:
                latent_data = self.load_latent_data(latent_file)
            except Exception as e:
                return False, "", f"读取失败: {str(e)[:20]}"

            # 2. 提取
            latent_tensor = None
            if isinstance(latent_data, dict):
                for key in ['samples', 'latent', 'latents', 'latent_tensor']:
                    if key in latent_data:
                        latent_tensor = latent_data[key]
                        break
                if latent_tensor is None:
                    for v in latent_data.values():
                        if isinstance(v, torch.Tensor):
                            latent_tensor = v
                            break
            elif isinstance(latent_data, torch.Tensor):
                latent_tensor = latent_data

            if latent_tensor is None:
                return False, "", "无有效 Tensor"

            # 3. 预处理
            if latent_tensor.dim() == 3:
                latent_tensor = latent_tensor.unsqueeze(0)
            
            # 输入也要转为目标设备和精度
            latent_input = latent_tensor.to(self.device, dtype=self.dtype)

            # 4. 解码
            with torch.no_grad():
                decoded_result = self.vae.decode(latent_input)

            # 5. 后处理
            if isinstance(decoded_result, tuple):
                decoded_tensor = decoded_result[0]
            else:
                decoded_tensor = decoded_result

            decoded_cpu = decoded_tensor.cpu().float()
            del latent_input, decoded_result, decoded_tensor

            # 6. 保存
            batch_count = decoded_cpu.shape[0]
            base_name = os.path.splitext(os.path.basename(latent_file))[0]
            saved_info = []

            from PIL import Image

            for i in range(batch_count):
                img_tensor = decoded_cpu[i]
                image = np.array(img_tensor)

                if image.min() < 0:
                    image = (image + 1.0) / 2.0
                image = np.clip(image, 0, 1.0)
                image = (image * 255).astype(np.uint8)

                if image.shape[0] in [3, 4]: 
                    image = np.transpose(image, (1, 2, 0))

                img_obj = Image.fromarray(image)
                save_name = f"{base_name}_{i:05d}.png"
                save_path = os.path.join(self.output_dir, save_name)
                img_obj.save(save_path)
                saved_info.append(save_name)

            duration = time.time() - start_time
            msg = f"耗时 {duration:.2f}s" if batch_count == 1 else f"保存 {batch_count} 张 ({duration:.2f}s)"
            return True, saved_info[0], msg

        except Exception as e:
            return False, "", str(e)

    def run(self):
        self.is_running = True
        
        if not os.path.exists(self.output_dir):
            os.makedirs(self.output_dir)

        if not self.load_vae():
            self.finished_all.emit()
            return

        self.log_message.emit(f"🚀 开始处理 {len(self.latent_files)} 个文件...")

        with ThreadPoolExecutor(max_workers=1) as executor:
            for i, file_path in enumerate(self.latent_files):
                if not self.is_running: break
                
                self.started_processing.emit(file_path)
                future = executor.submit(self.decode_single, file_path)
                
                try:
                    success, path, msg = future.result()
                    self.finished_one.emit(file_path, success, msg)
                    
                    if success:
                        self.log_message.emit(f"✅ 完成: {os.path.basename(file_path)} | {msg}")
                    else:
                        self.log_message.emit(f"❌ 失败: {os.path.basename(file_path)} | {msg}")
                    
                    if i % 3 == 0 and torch.backends.mps.is_available():
                        torch.mps.empty_cache()
                        
                except Exception as e:
                    self.log_message.emit(f"❌ 异常: {e}")

                self.progress.emit(i + 1, len(self.latent_files))

        self.vae = None
        if torch.backends.mps.is_available():
            torch.mps.empty_cache()
        self.finished_all.emit()

    def stop(self):
        self.is_running = False


class LatentFileCard(CardWidget):
    remove_clicked = pyqtSignal(str)

    def __init__(self, file_path):
        super().__init__()
        self.file_path = file_path
        self.setFixedHeight(80)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(16, 0, 16, 0)
        
        icon = BodyLabel("📦")
        icon.setFont(QFont("Apple Color Emoji", 24))
        layout.addWidget(icon)
        
        info = QVBoxLayout()
        info.setAlignment(Qt.AlignVCenter)
        self.name = BodyLabel(os.path.basename(file_path))
        self.name.setFont(QFont("PingFang SC", 14, QFont.Bold))
        self.path = CaptionLabel(os.path.dirname(file_path))
        self.path.setStyleSheet("color: #888;")
        info.addWidget(self.name)
        info.addWidget(self.path)
        layout.addLayout(info)
        
        layout.addStretch(1)
        
        self.status = BodyLabel("等待中")
        self.status.setStyleSheet("color: #aaa;")
        layout.addWidget(self.status)
        
        btn = PushButton("✕")
        btn.setFixedSize(30, 30)
        btn.clicked.connect(lambda: self.remove_clicked.emit(self.file_path))
        layout.addWidget(btn)

    def set_processing(self):
        self.status.setText("⏳ 处理中...")
        self.status.setStyleSheet("color: #1890ff; font-weight: bold;")

    def set_status(self, status, msg=""):
        if status == "success":
            self.status.setText(f"✅ {msg}")
            self.status.setStyleSheet("color: #4cc14e;")
        elif status == "error":
            self.status.setText("❌ 失败")
            self.status.setStyleSheet("color: #ff4d4f;")
            self.setToolTip(msg)
        else:
            self.status.setText("⏳ " + msg)


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ComfyUI Latent 解码器 ( BOZOYAN - Pro V1.1)")
        self.resize(1000, 750)
        self.center_window()
        self.latent_files = []
        self.vae_map = {}
        
        # 自动加载上次的 VAE 和 输出路径 (这里简化处理，直接用 ConfigManager)
        self.init_ui()
        self.refresh_settings() # 加载列表

    def center_window(self):
        qr = self.frameGeometry()
        cp = QDesktopWidget().availableGeometry().center()
        qr.moveCenter(cp)
        self.move(qr.topLeft())

    def init_ui(self):
        main = QWidget()
        self.setCentralWidget(main)
        layout = QHBoxLayout(main)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(20)

        # --- 左侧控制栏 ---
        left = CardWidget()
        left.setFixedWidth(320)
        l_layout = QVBoxLayout(left)
        l_layout.setSpacing(15)
        
        # 标题栏 + 设置按钮
        title_layout = QHBoxLayout()
        title = SubtitleLabel("控制面板")
        title.setFont(QFont("PingFang SC", 18, QFont.Bold))
        
        settings_btn = ToolButton(FluentIcon.SETTING)
        settings_btn.setToolTip("配置路径")
        settings_btn.clicked.connect(self.open_settings)
        
        title_layout.addWidget(title)
        title_layout.addStretch(1)
        title_layout.addWidget(settings_btn)
        l_layout.addLayout(title_layout)
        
        # --- 硬件与精度选择 (新增) ---
        l_layout.addWidget(BodyLabel("运行设备:"))
        self.device_combo = ComboBox()
        self.device_combo.addItems(["MPS", "CPU", "CUDA"])
        self.device_combo.setCurrentText("MPS") # 默认 MPS
        l_layout.addWidget(self.device_combo)
        
        l_layout.addWidget(BodyLabel("计算精度:"))
        self.dtype_combo = ComboBox()
        self.dtype_combo.addItems(["Float32", "BFloat16", "Float16"])
        self.dtype_combo.setCurrentText("Float32") # 默认 Float32 (macOS 推荐)
        l_layout.addWidget(self.dtype_combo)

        l_layout.addSpacing(10)

        # VAE 选择
        l_layout.addWidget(BodyLabel("选择 VAE 模型:"))
        self.vae_combo = ComboBox()
        l_layout.addWidget(self.vae_combo)
        
        ref_btn = PushButton("刷新列表")
        ref_btn.clicked.connect(self.load_vae_list)
        l_layout.addWidget(ref_btn)
        
        l_layout.addSpacing(10)
        l_layout.addWidget(BodyLabel("输出位置:"))
        self.out_edit = QLineEdit(CONFIG.get("DEFAULT_OUTPUT_DIR"))
        self.out_edit.setReadOnly(True)
        self.out_edit.setStyleSheet("padding:8px;background:#333;color:#fff;border:1px solid #444;border-radius:5px;")
        l_layout.addWidget(self.out_edit)
        
        ch_btn = PushButton("更改")
        ch_btn.clicked.connect(self.change_dir)
        l_layout.addWidget(ch_btn)
        
        l_layout.addStretch(1)
        
        add_btn = PushButton("添加文件")
        add_btn.clicked.connect(self.add_dialog)
        l_layout.addWidget(add_btn)
        
        clr_btn = PushButton("清空")
        clr_btn.clicked.connect(self.clear_list)
        l_layout.addWidget(clr_btn)
        
        self.start_btn = PrimaryPushButton("开始解码")
        self.start_btn.setFixedHeight(45)
        self.start_btn.clicked.connect(self.start)
        l_layout.addWidget(self.start_btn)
        
        layout.addWidget(left)

        # --- 右侧列表 ---
        right = QWidget()
        r_layout = QVBoxLayout(right)
        r_layout.setContentsMargins(0,0,0,0)
        
        self.header = BodyLabel("拖拽文件到这里")
        self.header.setStyleSheet("color:#888;")
        r_layout.addWidget(self.header)
        
        scroll = SmoothScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet("background:transparent;border:none;")
        self.list_widget = QWidget()
        self.list_layout = QVBoxLayout(self.list_widget)
        self.list_layout.setAlignment(Qt.AlignTop)
        self.list_layout.setSpacing(10)
        scroll.setWidget(self.list_widget)
        r_layout.addWidget(scroll)
        
        self.prog = ProgressBar()
        self.prog.setVisible(False)
        r_layout.addWidget(self.prog)
        
        layout.addWidget(right)
        self.setAcceptDrops(True)

    def open_settings(self):
        dlg = ConfigDialog(self)
        dlg.config_saved.connect(self.refresh_settings)
        dlg.exec_()

    def refresh_settings(self):
        # 刷新全局变量和界面显示
        global COMFYUI_PATH, VAE_MODELS_DIR
        COMFYUI_PATH = CONFIG.get("COMFYUI_PATH")
        VAE_MODELS_DIR = CONFIG.get("VAE_MODELS_DIR")
        self.out_edit.setText(CONFIG.get("DEFAULT_OUTPUT_DIR"))
        self.load_vae_list()

    def load_vae_list(self):
        self.vae_combo.clear()
        self.vae_map = {}
        if not os.path.exists(VAE_MODELS_DIR):
            self.vae_combo.addItem("❌ 路径错误 (请点击设置)")
            return
        
        valid = ('.safetensors', '.pt', '.pth', '.ckpt')
        try:
            for f in os.listdir(VAE_MODELS_DIR):
                if f.lower().endswith(valid):
                    self.vae_map[f] = os.path.join(VAE_MODELS_DIR, f)
                    self.vae_combo.addItem(f)
            
            # --- 自动选中 ae.safetensors ---
            index = self.vae_combo.findText("ae.safetensors")
            if index != -1:
                self.vae_combo.setCurrentIndex(index)
                
        except Exception as e:
            self.vae_combo.addItem(f"错误: {e}")

    def dragEnterEvent(self, e: QDragEnterEvent):
        if e.mimeData().hasUrls(): e.accept()

    def dropEvent(self, e: QDropEvent):
        for url in e.mimeData().urls():
            self.add_path(url.toLocalFile())

    def add_dialog(self):
        files, _ = QFileDialog.getOpenFileNames(self, "选择文件", "", "Latent (*.latent *.safetensors);;All (*.*)")
        for f in files: self.add_path(f)

    def add_path(self, path):
        if os.path.isdir(path):
            for root, _, files in os.walk(path):
                for f in files:
                    if f.endswith('.latent'): self.add_file(os.path.join(root, f))
        elif path.endswith('.latent') or path.endswith('.safetensors'):
            self.add_file(path)

    def add_file(self, path):
        if path in self.latent_files: return
        self.latent_files.append(path)
        card = LatentFileCard(path)
        card.remove_clicked.connect(self.rem_file)
        self.list_layout.addWidget(card)
        self.update_info()

    def rem_file(self, path):
        if path in self.latent_files:
            self.latent_files.remove(path)
            for i in range(self.list_layout.count()):
                w = self.list_layout.itemAt(i).widget()
                if isinstance(w, LatentFileCard) and w.file_path == path:
                    w.deleteLater()
                    break
        self.update_info()

    def clear_list(self):
        self.latent_files = []
        while self.list_layout.count():
            item = self.list_layout.takeAt(0)
            if item.widget(): item.widget().deleteLater()
        self.update_info()

    def update_info(self):
        self.header.setText(f"待处理: {len(self.latent_files)} 个文件")

    def change_dir(self):
        d = QFileDialog.getExistingDirectory(self)
        if d: 
            self.out_edit.setText(d)
            CONFIG.set("DEFAULT_OUTPUT_DIR", d) # 同时也保存到配置

    def start(self):
        if not HAS_COMFY:
            MessageBox("错误", "ComfyUI 模块未加载，请检查设置中的路径是否正确。", self).exec()
            return
            
        if not self.latent_files: return
        vae = self.vae_combo.currentText()
        if not vae or vae.startswith("❌") or vae.startswith("错误"): 
            MessageBox("错误", "请选择有效的模型", self).exec()
            return
        
        self.start_btn.setEnabled(False)
        self.prog.setVisible(True)
        self.prog.setRange(0, len(self.latent_files))
        
        # 获取硬件与精度参数
        device = self.device_combo.currentText()
        dtype = self.dtype_combo.currentText()
        
        self.th = VAEDecoderThread(
            self.latent_files, 
            self.vae_map[vae], 
            self.out_edit.text(),
            device,
            dtype
        )
        
        self.th.started_processing.connect(self.on_one_start)
        self.th.finished_one.connect(self.on_one_done)
        self.th.progress.connect(self.prog.setValue)
        self.th.log_message.connect(print)
        self.th.finished_all.connect(self.on_all_done)
        
        self.th.start()

    def on_one_start(self, path):
        for i in range(self.list_layout.count()):
            w = self.list_layout.itemAt(i).widget()
            if isinstance(w, LatentFileCard) and w.file_path == path:
                w.set_processing()
                break

    def on_one_done(self, path, ok, msg):
        for i in range(self.list_layout.count()):
            w = self.list_layout.itemAt(i).widget()
            if isinstance(w, LatentFileCard) and w.file_path == path:
                w.set_status("success" if ok else "error", msg)

    def on_all_done(self):
        self.start_btn.setEnabled(True)
        self.start_btn.setText("开始解码")
        MessageBox("完成", "所有任务处理完毕！", self).exec()

if __name__ == '__main__':
    QApplication.setHighDpiScaleFactorRoundingPolicy(Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    app = QApplication(sys.argv)
    setTheme(Theme.DARK)
    setThemeColor('#0078d4')
    app.setFont(QFont("PingFang SC", 13))
    w = MainWindow()
    w.show()
    sys.exit(app.exec_())