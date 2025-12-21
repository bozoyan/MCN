#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
ComfyUI Latent VAE 解码工具 (macOS MPS Ultimate Fix)
修复: 在加载 VAE 之前暴力清洗权重字典，强制将 BFloat16 转为 Float32，彻底解决 MPS 报错。
"""

import os
import sys
import torch
import numpy as np
import traceback
from typing import List
from concurrent.futures import ThreadPoolExecutor, as_completed

# ================= 配置区域 =================
# 1. ComfyUI 安装路径
COMFYUI_PATH = "/Users/hao/comflowy/ComfyUI"

# 2. VAE 模型文件夹路径
VAE_MODELS_DIR = "/Volumes/BO/AI/models/VAE"

# 3. 默认输出路径
DEFAULT_OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")
# ===========================================

# --- 环境注入 ---
if not os.path.exists(COMFYUI_PATH):
    print(f"❌ 严重错误: 找不到 ComfyUI 路径: {COMFYUI_PATH}")
    sys.exit(1)

if COMFYUI_PATH not in sys.path:
    sys.path.append(COMFYUI_PATH)

# --- 核心模块导入 ---
try:
    try:
        from safetensors.torch import load_file as load_safetensors
        HAS_SAFETENSORS = True
    except ImportError:
        HAS_SAFETENSORS = False

    import comfy.sd
    import comfy.utils
    print("✅ 成功导入 ComfyUI 核心模块")
except ImportError as e:
    print(f"❌ 导入失败: {e}")
    sys.exit(1)

# --- 界面库导入 ---
try:
    from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                                QHBoxLayout, QFileDialog, QLineEdit, QDesktopWidget)
    from PyQt5.QtCore import Qt, QThread, pyqtSignal
    from PyQt5.QtGui import QDragEnterEvent, QDropEvent, QFont
    
    # 使用基础组件以保证最大兼容性
    from qfluentwidgets import (
        PushButton, PrimaryPushButton, CardWidget, SubtitleLabel, CaptionLabel, 
        BodyLabel, ProgressBar, ComboBox, Theme, setTheme, setThemeColor,
        SmoothScrollArea, MessageBox
    )
except ImportError:
    print("❌ 缺少界面库")
    sys.exit(1)


class VAEDecoderThread(QThread):
    progress = pyqtSignal(int, int)
    finished_one = pyqtSignal(str, bool, str)
    log_message = pyqtSignal(str)
    finished_all = pyqtSignal()

    def __init__(self, latent_files: List[str], vae_path: str, output_dir: str):
        super().__init__()
        self.latent_files = latent_files
        self.vae_path = vae_path
        self.output_dir = output_dir
        self.is_running = False
        self.vae = None
        
        # --- 强制使用 MPS + Float32 ---
        if torch.backends.mps.is_available():
            self.device = torch.device("mps")
            self.device_name = "MPS (GPU)"
        else:
            self.device = torch.device("cpu")
            self.device_name = "CPU"
            
        self.offload_device = torch.device("cpu")
        self.dtype = torch.float32 

    def load_vae(self):
        try:
            self.log_message.emit(f"🔄 正在读取文件: {os.path.basename(self.vae_path)} ...")
            
            # 1. 加载原始权重数据 (Dict)
            vae_data = comfy.utils.load_torch_file(self.vae_path)
            
            # ----------------------------------------------------------
            # 🔥 核心修复：暴力清洗权重 (Force Cast Weights)
            # 遍历所有权重，只要发现是 BFloat16 或 Float16，立刻转为 Float32
            # ----------------------------------------------------------
            self.log_message.emit("🧹 正在清洗权重格式 (Force Float32)...")
            new_vae_data = {}
            for k, v in vae_data.items():
                if isinstance(v, torch.Tensor):
                    # 检查是否为半精度/BF16
                    if v.dtype in [torch.bfloat16, torch.float16]:
                        # 强制转为 float32
                        new_vae_data[k] = v.to(dtype=torch.float32)
                    else:
                        new_vae_data[k] = v
                else:
                    new_vae_data[k] = v
            
            # 替换原始数据
            vae_data = new_vae_data
            del new_vae_data # 释放内存
            
            # 2. 初始化 VAE (此时传入的已经是纯净的 FP32 数据)
            self.log_message.emit("🏗️ 构建 VAE 模型...")
            self.vae = comfy.sd.VAE(vae_data)
            
            # 3. 移动到 MPS
            if hasattr(self.vae, 'first_stage_model'):
                self.vae.first_stage_model.to(self.device)
                self.vae.device = self.device
            
            # 4. 预热 (Warmup)
            try:
                dummy = torch.zeros((1, 4, 8, 8), device=self.device, dtype=torch.float32)
                self.vae.decode(dummy)
                self.log_message.emit(f"✅ VAE 就绪 ({self.device_name} FP32)")
            except Exception as e:
                self.log_message.emit(f"⚠️ VAE 预热警告: {e}")

            return True
        except Exception as e:
            self.log_message.emit(f"❌ VAE 加载失败: {str(e)}")
            # traceback.print_exc()
            return False

    def load_latent_data(self, file_path):
        """兼容性文件加载器"""
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
        try:
            # 1. 读取
            try:
                latent_data = self.load_latent_data(latent_file)
            except Exception as e:
                return False, "", f"读取失败: {str(e)[:40]}"

            # 2. 提取 Tensor
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

            # 3. 预处理 (输入也必须是 Float32)
            if latent_tensor.dim() == 3:
                latent_tensor = latent_tensor.unsqueeze(0)
            
            latent_input = latent_tensor.to(self.device, dtype=torch.float32)

            # 4. 解码
            with torch.no_grad():
                decoded_result = self.vae.decode(latent_input)

            # 5. 后处理
            if isinstance(decoded_result, tuple):
                decoded_tensor = decoded_result[0]
            else:
                decoded_tensor = decoded_result

            # 移回 CPU
            image = decoded_tensor[0].cpu().float().numpy()
            del latent_input, decoded_result, decoded_tensor

            # 反归一化
            if image.min() < 0:
                image = (image + 1.0) / 2.0
            image = np.clip(image, 0, 1.0)
            image = (image * 255).astype(np.uint8)

            if image.shape[0] in [3, 4]: 
                image = np.transpose(image, (1, 2, 0))

            from PIL import Image
            img_obj = Image.fromarray(image)
            
            file_name = os.path.splitext(os.path.basename(latent_file))[0]
            save_path = os.path.join(self.output_dir, f"{file_name}.png")
            img_obj.save(save_path)

            return True, save_path, "成功"

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
            future_map = {executor.submit(self.decode_single, f): f for f in self.latent_files}
            
            for i, future in enumerate(as_completed(future_map)):
                if not self.is_running: break
                
                original = future_map[future]
                try:
                    success, path, msg = future.result()
                    self.finished_one.emit(original, success, msg if not success else path)
                    
                    if success:
                        self.log_message.emit(f"✅ 保存: {os.path.basename(path)}")
                    else:
                        self.log_message.emit(f"❌ 失败 {os.path.basename(original)}: {msg}")
                    
                    # 显存清理
                    if i % 5 == 0 and torch.backends.mps.is_available():
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

    def set_status(self, status, msg=""):
        if status == "success":
            self.status.setText("✅ 完成")
            self.status.setStyleSheet("color: #4cc14e;")
        elif status == "error":
            self.status.setText("❌ 失败")
            self.status.setStyleSheet("color: #ff4d4f;")
            self.setToolTip(msg)
        else:
            self.status.setText("⏳ 处理中")
            self.status.setStyleSheet("color: #1890ff;")


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ComfyUI Latent 解码器 (MPS Fix)")
        self.resize(1000, 700)
        self.center_window()
        self.latent_files = []
        self.vae_map = {}
        self.init_ui()
        self.load_vae_list()

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

        # 左侧
        left = CardWidget()
        left.setFixedWidth(320)
        l_layout = QVBoxLayout(left)
        l_layout.setSpacing(15)
        
        l_layout.addWidget(SubtitleLabel("控制面板"))
        l_layout.addWidget(BodyLabel("选择 VAE:"))
        self.vae_combo = ComboBox()
        l_layout.addWidget(self.vae_combo)
        
        ref_btn = PushButton("刷新列表")
        ref_btn.clicked.connect(self.load_vae_list)
        l_layout.addWidget(ref_btn)
        
        l_layout.addSpacing(10)
        l_layout.addWidget(BodyLabel("输出位置:"))
        self.out_edit = QLineEdit(DEFAULT_OUTPUT_DIR)
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

        # 右侧
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

    def load_vae_list(self):
        self.vae_combo.clear()
        self.vae_map = {}
        if not os.path.exists(VAE_MODELS_DIR):
            self.vae_combo.addItem("❌ 路径错误")
            return
        
        valid = ('.safetensors', '.pt', '.pth', '.ckpt')
        for f in os.listdir(VAE_MODELS_DIR):
            if f.lower().endswith(valid):
                self.vae_map[f] = os.path.join(VAE_MODELS_DIR, f)
                self.vae_combo.addItem(f)

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
        if d: self.out_edit.setText(d)

    def start(self):
        if not self.latent_files: return
        vae = self.vae_combo.currentText()
        if not vae or vae.startswith("❌"): 
            MessageBox("错误", "请选择有效的模型", self).exec()
            return
        
        self.start_btn.setEnabled(False)
        self.prog.setVisible(True)
        self.prog.setRange(0, len(self.latent_files))
        
        self.th = VAEDecoderThread(self.latent_files, self.vae_map[vae], self.out_edit.text())
        self.th.progress.connect(self.prog.setValue)
        self.th.finished_one.connect(self.on_one_done)
        self.th.log_message.connect(print)
        self.th.finished_all.connect(self.on_all_done)
        self.th.start()

    def on_one_done(self, path, ok, msg):
        for i in range(self.list_layout.count()):
            w = self.list_layout.itemAt(i).widget()
            if isinstance(w, LatentFileCard) and w.file_path == path:
                w.set_status("success" if ok else "error", msg)

    def on_all_done(self):
        self.start_btn.setEnabled(True)
        self.start_btn.setText("开始解码")
        MessageBox("完成", "处理完毕", self).exec()

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