#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
ComfyUI Latent VAE 解码工具 (BOZOYAN-Pro v2.2 - Final Stats Fix)
修复内容:
1. 【关键修复】修正 memory_stats 返回空字典导致的 KeyError。现在返回完整的 0 值字典，包含 'reserved_bytes.all.current' 等所有必需键。
2. 【环境保持】保留 V2.1 的 Lazy Init 禁用补丁，防止 "Torch not compiled" 报错。
3. 【动态加载】保留路径修改后的自动重试逻辑。
"""

import os
import sys
import json
import time
import types
import importlib

# ==========================================
# 1. 环境与硬件防御 (必须在 import torch 前)
# ==========================================
# 强制注入 --cpu 参数
if "--cpu" not in sys.argv:
    sys.argv.append("--cpu")

# 屏蔽 CUDA 和 MPS 物理设备
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"

import torch

# ==========================================
# 2. 深度 Monkey Patch (拆除报错引信)
# ==========================================
try:
    # --- 屏蔽状态查询 ---
    torch.cuda.is_available = lambda: False
    torch.cuda.device_count = lambda: 0
    torch.cuda.current_device = lambda: 0
    
    # --- 解决解包错误 ---
    torch.cuda.get_device_capability = lambda device=None: (0, 0)
    
    # --- ★★★ 核心修复：构造完整的显存统计字典 ★★★ ---
    # 防止 KeyError: 'reserved_bytes.all.current'
    def _mock_memory_stats(device=None):
        return {
            "reserved_bytes.all.current": 0,
            "allocated_bytes.all.current": 0,
            "active_bytes.all.current": 0,
            "inactive_split_bytes.all.current": 0,
            "reserved_bytes.all.peak": 0,
            "allocated_bytes.all.peak": 0,
            "active_bytes.all.peak": 0,
            "inactive_split_bytes.all.peak": 0,
            "num_alloc_retries": 0,
            "num_ooms": 0
        }
    torch.cuda.memory_stats = _mock_memory_stats

    # --- 其他显存函数 ---
    torch.cuda.memory_allocated = lambda device=None: 0
    torch.cuda.max_memory_allocated = lambda device=None: 0
    torch.cuda.memory_reserved = lambda device=None: 0
    torch.cuda.max_memory_reserved = lambda device=None: 0
    torch.cuda.empty_cache = lambda: None
    
    # --- 属性伪造 ---
    class MockProperties:
        name = "Intel CPU"
        total_memory = 16 * 1024**3 
    torch.cuda.get_device_properties = lambda device=None: MockProperties()

    # --- 禁止 PyTorch 检查 CUDA ---
    if hasattr(torch.cuda, '_lazy_init'):
        torch.cuda._lazy_init = lambda: None
    
    if hasattr(torch.cuda, 'init'):
        torch.cuda.init = lambda: None

    if hasattr(torch.cuda, 'check_error'):
        torch.cuda.check_error = lambda x: None

    # --- 上下文管理器 ---
    class MockDeviceContext:
        def __init__(self, *args, **kwargs): pass
        def __enter__(self): return self
        def __exit__(self, *args): pass
    torch.cuda.device = MockDeviceContext

    print("✅ 已应用深度 CPU 补丁 (Memory Stats Fixed)")

except Exception as e:
    print(f"⚠️ 补丁应用警告: {e}")

# ==========================================

import numpy as np
from typing import List
from concurrent.futures import ThreadPoolExecutor

# --- PyQt5 & Fluent Widgets ---
try:
    from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                                QHBoxLayout, QFileDialog, QLineEdit, QDesktopWidget,
                                QDialog, QFormLayout, QLabel, QFrame)
    from PyQt5.QtCore import Qt, QThread, pyqtSignal
    from PyQt5.QtGui import QFont, QDragEnterEvent, QDropEvent
    
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
        self.config_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vae.json")
        self.defaults = {
            "COMFYUI_PATH": "/Users/hao/comflowy/ComfyUI",
            "VAE_MODELS_DIR": "/Volumes/BO/AI/models/VAE",
            "DEFAULT_OUTPUT_DIR": os.path.join(os.path.dirname(os.path.abspath(__file__)), "output"),
            "THEME_MODE": "dark",
            "DTYPE_MODE": "Float32"
        }
        self.config = self.load_config()

    def load_config(self):
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    saved = json.load(f)
                    config = self.defaults.copy()
                    config.update(saved)
                    return config
            except:
                return self.defaults.copy()
        return self.defaults.copy()

    def save_config(self):
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4, ensure_ascii=False)
        except Exception as e:
            print(f"❌ 保存配置失败: {e}")

    def get(self, key):
        return self.config.get(key, self.defaults.get(key))

    def set(self, key, value):
        self.config[key] = value
        self.save_config()

CONFIG = ConfigManager()

# --- ComfyUI 环境注入 ---
COMFYUI_PATH = CONFIG.get("COMFYUI_PATH")
VAE_MODELS_DIR = CONFIG.get("VAE_MODELS_DIR")

if os.path.exists(COMFYUI_PATH):
    if COMFYUI_PATH not in sys.path:
        sys.path.insert(0, COMFYUI_PATH)
        print(f"🔗 已注入 ComfyUI 路径: {COMFYUI_PATH}")

# --- ComfyUI 模块导入 ---
HAS_COMFY = False
HAS_SAFETENSORS = False
try:
    try:
        from safetensors.torch import load_file as load_safetensors
        HAS_SAFETENSORS = True
    except ImportError:
        HAS_SAFETENSORS = False

    import comfy.sd
    import comfy.utils
    HAS_COMFY = True
    print("✅ 成功导入 ComfyUI 核心模块 (Intel CPU 模式)")

except ImportError as e:
    print(f"❌ 启动时导入失败: {e}")
except KeyError as e:
    print(f"❌ 显存统计键值缺失: {e}")
except Exception as e:
    print(f"❌ 启动时发生错误: {e}")


# --- 拖拽容器 ---
class DragDropArea(QFrame):
    files_dropped = pyqtSignal(list)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAcceptDrops(True)
        self.setFrameShape(QFrame.NoFrame)
        self.setStyleSheet("background: transparent;")

    def dragEnterEvent(self, e: QDragEnterEvent):
        if e.mimeData().hasUrls():
            e.accept()
        else:
            e.ignore()

    def dropEvent(self, e: QDropEvent):
        urls = [u.toLocalFile() for u in e.mimeData().urls()]
        if urls:
            self.files_dropped.emit(urls)


class ConfigDialog(QDialog):
    config_saved = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("环境配置")
        self.resize(500, 300)
        
        is_dark = CONFIG.get("THEME_MODE") == "dark"
        bg = "#2b2b2b" if is_dark else "#f9f9f9"
        text = "white" if is_dark else "black"
        self.setStyleSheet(f"background-color: {bg}; color: {text};")
        
        layout = QVBoxLayout(self)
        form_layout = QFormLayout()
        form_layout.setSpacing(15)

        input_bg = "#333" if is_dark else "#fff"
        input_border = "#555" if is_dark else "#ccc"
        style = f"QLineEdit {{ padding: 8px; border-radius: 5px; background: {input_bg}; border: 1px solid {input_border}; color: {text}; }}"
        
        self.comfy_edit = QLineEdit(CONFIG.get("COMFYUI_PATH"))
        self.comfy_edit.setStyleSheet(style)
        self.comfy_edit.setMinimumWidth(300)
        self.vae_edit = QLineEdit(CONFIG.get("VAE_MODELS_DIR"))
        self.vae_edit.setStyleSheet(style)
        self.vae_edit.setMinimumWidth(300)
        self.out_edit = QLineEdit(CONFIG.get("DEFAULT_OUTPUT_DIR"))
        self.out_edit.setStyleSheet(style)
        self.out_edit.setMinimumWidth(300)

        form_layout.addRow(QLabel("ComfyUI 路径:"), self.comfy_edit)
        form_layout.addRow(QLabel("VAE 模型路径:"), self.vae_edit)
        form_layout.addRow(QLabel("默认输出路径:"), self.out_edit)

        layout.addLayout(form_layout)
        
        tips = CaptionLabel("注: 修改路径后会自动尝试加载。")
        tips.setStyleSheet("color: #888;")
        layout.addWidget(tips)

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

    def __init__(self, latent_files: List[str], vae_path: str, output_dir: str, dtype_mode: str):
        super().__init__()
        self.latent_files = latent_files
        self.vae_path = vae_path
        self.output_dir = output_dir
        self.is_running = False
        
        # 1. 强制使用 CPU
        self.device = torch.device("cpu")
        
        # 2. 精度设置
        if dtype_mode == "BFloat16":
            self.dtype = torch.bfloat16
        elif dtype_mode == "Float16":
            self.dtype = torch.float16
        else:
            self.dtype = torch.float32

    def load_vae(self):
        try:
            self.log_message.emit(f"🔄 读取 VAE: {os.path.basename(self.vae_path)}")
            # 显式 map_location='cpu'
            vae_data = comfy.utils.load_torch_file(self.vae_path)
            
            self.log_message.emit(f"🧹 转换权重至 CPU ({self.dtype})...")
            new_vae_data = {}
            for k, v in vae_data.items():
                if isinstance(v, torch.Tensor):
                    new_vae_data[k] = v.to(device=self.device, dtype=self.dtype)
                else:
                    new_vae_data[k] = v
            del vae_data
            
            self.log_message.emit("🏗️ 构建 VAE 模型...")
            self.vae = comfy.sd.VAE(new_vae_data)
            
            if hasattr(self.vae, 'first_stage_model'):
                self.vae.first_stage_model.to(self.device)
                self.vae.device = self.device
            
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
        return torch.load(file_path, map_location="cpu")

    def decode_single(self, latent_file: str) -> tuple:
        start_time = time.time()
        try:
            latent_data = self.load_latent_data(latent_file)
            
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

            if latent_tensor.dim() == 3:
                latent_tensor = latent_tensor.unsqueeze(0)
            
            latent_input = latent_tensor.to(device=self.device, dtype=self.dtype)

            with torch.no_grad():
                decoded_result = self.vae.decode(latent_input)

            if isinstance(decoded_result, tuple):
                decoded_tensor = decoded_result[0]
            else:
                decoded_tensor = decoded_result

            decoded_cpu = decoded_tensor.cpu().float()
            del latent_input, decoded_result, decoded_tensor

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
            return True, saved_info[0], f"耗时 {duration:.2f}s"

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
                except Exception as e:
                    self.log_message.emit(f"❌ 异常: {e}")
                self.progress.emit(i + 1, len(self.latent_files))

        self.vae = None
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
        self.setWindowTitle("ComfyUI Latent 解码器 (BOZOYAN-Pro V2.2 - Intel Mac)")
        self.resize(1000, 750)
        
        if CONFIG.get("THEME_MODE") == "light":
            setTheme(Theme.LIGHT)
        else:
            setTheme(Theme.DARK)

        self.center_window()
        self.latent_files = []
        self.vae_map = {}
        
        self.init_ui()
        self.refresh_settings()

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
        
        title_layout = QHBoxLayout()
        title = SubtitleLabel("控制面板")
        title.setFont(QFont("PingFang SC", 18, QFont.Bold))
        
        self.theme_btn = ToolButton(FluentIcon.BRIGHTNESS)
        self.theme_btn.setToolTip("切换主题 (深/浅)")
        self.theme_btn.clicked.connect(self.toggle_theme)

        settings_btn = ToolButton(FluentIcon.SETTING)
        settings_btn.setToolTip("配置路径")
        settings_btn.clicked.connect(self.open_settings)
        
        title_layout.addWidget(title)
        title_layout.addStretch(1)
        title_layout.addWidget(self.theme_btn)
        title_layout.addWidget(settings_btn)
        l_layout.addLayout(title_layout)
        
        # CPU 模式强制显示
        l_layout.addWidget(BodyLabel("运行设备:"))
        self.device_combo = ComboBox()
        self.device_combo.addItem("Intel CPU (强制)")
        self.device_combo.setCurrentIndex(0)
        self.device_combo.setEnabled(False) 
        l_layout.addWidget(self.device_combo)
        
        l_layout.addWidget(BodyLabel("计算精度:"))
        self.dtype_combo = ComboBox()
        self.dtype_combo.addItems(["Float32", "BFloat16", "Float16"])
        self.dtype_combo.setCurrentText(CONFIG.get("DTYPE_MODE"))
        self.dtype_combo.currentTextChanged.connect(lambda t: CONFIG.set("DTYPE_MODE", t))
        l_layout.addWidget(self.dtype_combo)

        l_layout.addSpacing(10)

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
        self.update_output_style() 
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

        # --- 右侧列表 (DragDropArea) ---
        right = DragDropArea()
        right.files_dropped.connect(self.on_files_dropped)
        
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

    def on_files_dropped(self, files):
        for f in files:
            self.add_path(f)

    def update_output_style(self):
        if CONFIG.get("THEME_MODE") == "dark":
            self.out_edit.setStyleSheet("padding:8px; border:1px solid #444; border-radius:5px; background: #333; color: white;")
        else:
            self.out_edit.setStyleSheet("padding:8px; border:1px solid #ccc; border-radius:5px; background: #fff; color: black;")

    def toggle_theme(self):
        current = CONFIG.get("THEME_MODE")
        if current == "dark":
            setTheme(Theme.LIGHT)
            CONFIG.set("THEME_MODE", "light")
        else:
            setTheme(Theme.DARK)
            CONFIG.set("THEME_MODE", "dark")
        self.update_output_style()

    def open_settings(self):
        dlg = ConfigDialog(self)
        dlg.config_saved.connect(self.refresh_settings)
        dlg.exec_()

    def refresh_settings(self):
        global COMFYUI_PATH, VAE_MODELS_DIR, HAS_COMFY
        COMFYUI_PATH = CONFIG.get("COMFYUI_PATH")
        VAE_MODELS_DIR = CONFIG.get("VAE_MODELS_DIR")
        
        if COMFYUI_PATH and COMFYUI_PATH not in sys.path:
            sys.path.insert(0, COMFYUI_PATH)

        # 核心修复：如果之前加载失败，现在重试
        if not HAS_COMFY and COMFYUI_PATH:
            try:
                import comfy.sd
                import comfy.utils
                HAS_COMFY = True
                print("✅ 动态修复: ComfyUI 模块加载成功")
            except Exception as e:
                print(f"⚠️ 动态修复失败: {e}")
            
        self.out_edit.setText(CONFIG.get("DEFAULT_OUTPUT_DIR"))
        self.dtype_combo.setCurrentText(CONFIG.get("DTYPE_MODE"))
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
            
            index = self.vae_combo.findText("ae.safetensors")
            if index != -1:
                self.vae_combo.setCurrentIndex(index)
                
        except Exception as e:
            self.vae_combo.addItem(f"错误: {e}")

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
            CONFIG.set("DEFAULT_OUTPUT_DIR", d)

    def start(self):
        if not HAS_COMFY:
            MessageBox("错误", "ComfyUI 模块未加载，请检查设置中的 ComfyUI 路径。", self).exec()
            return
            
        if not self.latent_files: return
        vae = self.vae_combo.currentText()
        if not vae or vae.startswith("❌") or vae.startswith("错误"): 
            MessageBox("错误", "请选择有效的模型", self).exec()
            return
        
        self.start_btn.setEnabled(False)
        self.prog.setVisible(True)
        self.prog.setRange(0, len(self.latent_files))
        
        dtype = self.dtype_combo.currentText()
        
        self.th = VAEDecoderThread(
            self.latent_files, 
            self.vae_map[vae], 
            self.out_edit.text(),
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
    
    if CONFIG.get("THEME_MODE") == "light":
        setTheme(Theme.LIGHT)
    else:
        setTheme(Theme.DARK)
        
    setThemeColor('#0078d4')
    app.setFont(QFont("PingFang SC", 13))
    w = MainWindow()
    w.show()
    sys.exit(app.exec_())