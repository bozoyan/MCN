#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
图片转视频生成模块 (pic2vod) - 增强版
基于 BizyAir API 的图片转视频功能，支持批量生成和更美观的界面
"""

import os
import sys
import json
import time
import threading
import requests
import base64
from datetime import datetime
from PyQt5.QtCore import QThread, pyqtSignal, QTimer, Qt, QMimeData, QUrl
from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
                            QLineEdit, QTextEdit, QPushButton, QComboBox,
                            QSpinBox, QProgressBar, QMessageBox, QFileDialog,
                            QGroupBox, QTabWidget, QSplitter, QFrame,
                            QGridLayout, QScrollArea, QSlider, QCheckBox, QDialog)
from PyQt5.QtGui import QPixmap, QDragEnterEvent, QDropEvent, QPalette
import qfluentwidgets as qf
from qfluentwidgets import (FluentIcon, CardWidget, ElevatedCardWidget,
                          SmoothScrollArea, SubtitleLabel, BodyLabel,
                          PrimaryPushButton, PushButton, LineEdit, ComboBox,
                          ProgressBar, InfoBar, InfoBarPosition,
                          SwitchButton, InfoBadge, TeachingTip, TeachingTipTailPosition)

# 导入配置管理器
try:
    from storyboard_generator import config_manager, MODEL_API_KEY
except ImportError:
    # 如果无法导入，使用默认配置
    MODEL_API_KEY = os.getenv('SiliconCloud_API_KEY')
    class ConfigManager:
        def get(self, key, default=None):
            return default
        def set(self, key, value):
            pass
    config_manager = ConfigManager()

# 图片拖拽上传小部件
class ImageDropWidget(QFrame):
    """支持拖拽上传的图片区域"""
    image_dropped = pyqtSignal(str, str)  # image_path, base64_data

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAcceptDrops(True)
        self.current_image_path = ""
        self.base64_data = ""
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)

        # 图片显示区域
        self.image_label = QLabel()
        self.image_label.setFixedSize(280, 180)
        self.image_label.setStyleSheet("""
            QLabel {
                border: 2px dashed #505050;
                border-radius: 8px;
                background-color: #2a2a2a;
                color: #888888;
                font-size: 13px;
            }
        """)
        self.image_label.setAlignment(Qt.AlignCenter)
        self.image_label.setText("🖼️\n拖拽图片到这里\n或点击选择文件")
        layout.addWidget(self.image_label, alignment=Qt.AlignCenter)

        # 选择文件按钮
        self.select_btn = PushButton(FluentIcon.FOLDER, "选择图片文件")
        self.select_btn.setFixedHeight(32)
        self.select_btn.setStyleSheet("""
            QPushButton {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 13px;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
                border: 1px solid #4a90e2;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        self.select_btn.clicked.connect(self.select_file)
        layout.addWidget(self.select_btn)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            self.setStyleSheet("background-color: #e3f2fd;")

    def dragLeaveEvent(self, event):
        self.setStyleSheet("")

    def dropEvent(self, event: QDropEvent):
        self.setStyleSheet("")
        files = [u.toLocalFile() for u in event.mimeData().urls()]
        for file_path in files:
            if file_path.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp')):
                self.load_image(file_path)
                break

    def select_file(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择图片文件",
            "",
            "图片文件 (*.png *.jpg *.jpeg *.gif *.bmp *.webp)"
        )
        if file_path:
            self.load_image(file_path)

    def load_image(self, file_path):
        try:
            # 加载图片并缩放
            pixmap = QPixmap(file_path)
            if not pixmap.isNull():
                scaled_pixmap = pixmap.scaled(
                    300, 200,
                    Qt.KeepAspectRatio,
                    Qt.SmoothTransformation
                )
                self.image_label.setPixmap(scaled_pixmap)

                # 转换为base64
                with open(file_path, 'rb') as f:
                    image_data = f.read()
                    self.base64_data = base64.b64encode(image_data).decode('utf-8')

                self.current_image_path = file_path
                self.image_dropped.emit(file_path, self.base64_data)

        except Exception as e:
            QMessageBox.warning(self, "错误", f"加载图片失败: {str(e)}")

    def clear_image(self):
        self.image_label.clear()
        self.image_label.setText("🖼️\n拖拽图片到这里\n或点击选择文件")
        self.current_image_path = ""
        self.base64_data = ""

# API密钥管理器
class APIKeyManager:
    """API密钥管理器"""

    def __init__(self):
        self.api_keys = []
        self.key_file = ""
        self.current_key_index = 0
        self.web_app_id = 39386

    def load_keys_from_file(self, file_path):
        """从文件加载API密钥"""
        try:
            if os.path.exists(file_path):
                with open(file_path, 'r', encoding='utf-8') as f:
                    keys = [line.strip() for line in f.readlines() if line.strip()]
                self.api_keys = [key for key in keys if len(key) > 10]  # 过滤掉无效密钥
                self.key_file = file_path
                return True
        except Exception as e:
            print(f"加载API密钥文件失败: {e}")
        return False

    def get_next_key(self):
        """获取下一个可用的API密钥"""
        if not self.api_keys:
            # 如果没有从文件加载，使用环境变量
            env_key = os.getenv('SiliconCloud_API_KEY')
            if env_key:
                return env_key
            return None

        if self.current_key_index >= len(self.api_keys):
            self.current_key_index = 0

        key = self.api_keys[self.current_key_index]
        self.current_key_index += 1
        return key

    def get_available_keys_count(self):
        """获取可用密钥数量"""
        if self.api_keys:
            return len(self.api_keys)
        env_key = os.getenv('SiliconCloud_API_KEY')
        return 1 if env_key else 0

# 批量视频生成工作线程
class BatchVideoGenerationWorker(QThread):
    """批量视频生成工作线程"""
    progress_updated = pyqtSignal(int, str, str)  # progress, message, task_id
    task_finished = pyqtSignal(bool, str, dict, str)  # success, message, result_data, task_id
    batch_progress = pyqtSignal(int, int)  # current, total
    log_updated = pyqtSignal(str)  # 日志更新信号

    def __init__(self, task_list):
        super().__init__()
        self.task_list = task_list
        self.api_manager = APIKeyManager()
        self.start_time = None
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_elapsed_time)
        self.is_cancelled = False

        # 创建日志目录
        self.log_dir = "logs"
        if not os.path.exists(self.log_dir):
            os.makedirs(self.log_dir)

    def update_elapsed_time(self):
        """更新运行时间"""
        if self.start_time:
            elapsed = time.time() - self.start_time
            hours = int(elapsed // 3600)
            minutes = int((elapsed % 3600) // 60)
            seconds = int(elapsed % 60)
            time_str = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
            self.log_updated.emit(f"⏱️ 运行时间: {time_str}")

    def log_message(self, message):
        """记录日志消息"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {message}"
        self.log_updated.emit(log_entry)

        # 写入日志文件
        log_file = os.path.join(self.log_dir, "batch_video_generation.log")
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(log_entry + "\n")
        except Exception as e:
            print(f"写入日志失败: {e}")

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True
        self.log_message("⏹️ 批量任务已取消")

    def run(self):
        """运行批量视频生成"""
        try:
            self.start_time = time.time()
            self.timer.start(1000)  # 每秒更新一次时间

            self.log_message(f"🚀 开始批量生成视频，共 {len(self.task_list)} 个任务")
            self.batch_progress.emit(0, len(self.task_list))

            # 加载API密钥
            if hasattr(self.task_list[0], 'key_file') and self.task_list[0].key_file:
                self.api_manager.load_keys_from_file(self.task_list[0].key_file)
                self.log_message(f"📋 已加载 {self.api_manager.get_available_keys_count()} 个API密钥")

            for i, task in enumerate(self.task_list):
                if self.is_cancelled:
                    break

                self.log_message(f"📝 处理任务 {i+1}/{len(self.task_list)}: {task.get('name', '未命名')}")
                self.batch_progress.emit(i, len(self.task_list))

                # 处理单个任务
                success = self.process_single_task(task, f"task_{i+1}")

                if not success and self.is_cancelled:
                    break

            if not self.is_cancelled:
                self.batch_progress.emit(len(self.task_list), len(self.task_list))
                self.log_message("✅ 批量生成完成!")

        except Exception as e:
            self.log_message(f"❌ 批量生成失败: {str(e)}")
        finally:
            self.timer.stop()

    def process_single_task(self, task, task_id):
        """处理单个视频生成任务"""
        try:
            api_key = self.api_manager.get_next_key()
            if not api_key:
                self.task_finished.emit(False, "没有可用的API密钥", {}, task_id)
                return False

            self.progress_updated.emit(10, "准备生成视频...", task_id)

            # 准备请求数据
            image_input = task.get('image_input', '')
            prompt = task.get('prompt', '')
            width = task.get('width', 720)
            height = task.get('height', 720)
            num_frames = task.get('num_frames', 81)

            base_url = 'https://api.bizyair.cn/w/v1/webapp/task/openapi/create'
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            }

            input_values = {
                "67:LoadImage.image": image_input,
                "68:ImageResizeKJv2.width": width,
                "68:ImageResizeKJv2.height": height,
                "16:WanVideoTextEncode.positive_prompt": prompt,
                "89:WanVideoImageToVideoEncode.num_frames": num_frames
            }

            request_data = {
                "web_app_id": self.api_manager.web_app_id,
                "suppress_preview_output": True,
                "input_values": input_values
            }

            self.progress_updated.emit(30, "发送API请求...", task_id)

            response = requests.post(
                base_url,
                headers=headers,
                json=request_data,
                timeout=600  # 10分钟超时
            )

            if self.is_cancelled:
                return False

            self.progress_updated.emit(70, "处理响应...", task_id)

            if response.status_code == 200:
                result = response.json()

                if result.get("status") == "Success" and result.get("outputs"):
                    outputs = result["outputs"]
                    if outputs and len(outputs) > 0:
                        video_output = outputs[0]
                        video_url = video_output.get("object_url", "")

                        if video_url:
                            result_data = {
                                "video_url": video_url,
                                "input_image": image_input,
                                "prompt": prompt,
                                "width": width,
                                "height": height,
                                "num_frames": num_frames,
                                "task_name": task.get('name', '未命名'),
                                "timestamp": datetime.now().isoformat()
                            }

                            self.progress_updated.emit(100, "生成完成!", task_id)
                            self.task_finished.emit(True, "视频生成成功!", result_data, task_id)
                            return True

            error_msg = f"生成失败: {result.get('message', '未知错误') if 'result' in locals() else 'API请求失败'}"
            self.progress_updated.emit(0, error_msg, task_id)
            self.task_finished.emit(False, error_msg, {}, task_id)
            return False

        except Exception as e:
            error_msg = f"生成异常: {str(e)}"
            self.progress_updated.emit(0, error_msg, task_id)
            self.task_finished.emit(False, error_msg, {}, task_id)
            return False

# 主要的视频生成界面
class VideoGenerationWidget(QWidget):
    """视频生成主界面 - 增强版"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.current_batch_worker = None
        self.batch_tasks = []
        self.api_manager = APIKeyManager()
        self.init_ui()
        self.load_settings()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(8, 8, 8, 8)

        # 设置深色主题整体样式
        self.setStyleSheet("""
            VideoGenerationWidget {
                background-color: #1e1e1e;
                color: #ffffff;
            }
            QScrollArea {
                background-color: #1e1e1e;
                border: none;
            }
            QSplitter::handle {
                background-color: #3a3a3a;
                width: 2px;
            }
            QSplitter::handle:hover {
                background-color: #4a4a4a;
            }
            QLabel {
                color: #ffffff;
                font-size: 13px;
            }
            QGroupBox {
                color: #ffffff;
            }
            QPushButton {
                color: #ffffff;
            }
            QTextEdit {
                color: #ffffff;
            }
            QLineEdit {
                color: #ffffff;
            }
            QComboBox {
                color: #ffffff;
            }
            QSpinBox {
                color: #ffffff;
            }
        """)

        # 顶部控制栏 - 密钥设置（深色主题）
        top_bar = self.create_top_bar()
        layout.addWidget(top_bar)

        # 创建分割器
        splitter = QSplitter(Qt.Horizontal)
        layout.addWidget(splitter)

        # 左侧控制面板
        left_panel = self.create_control_panel()
        splitter.addWidget(left_panel)

        # 右侧结果面板
        right_panel = self.create_result_panel()
        splitter.addWidget(right_panel)

        # 设置分割比例
        splitter.setSizes([450, 750])

    def create_top_bar(self):
        """创建顶部控制栏（深色主题）"""
        bar = QFrame()
        bar.setFixedHeight(40)
        bar.setStyleSheet("""
            QFrame {
                background-color: #2a2a2a;
                border: 1px solid #404040;
                border-radius: 8px;
                margin: 2px;
            }
        """)
        layout = QHBoxLayout(bar)
        layout.setContentsMargins(12, 6, 12, 6)

        # 标题
        title = QLabel("🎬 图片转视频生成")
        title.setStyleSheet("font-size: 16px; font-weight: bold; color: #ffffff;")
        layout.addWidget(title)

        layout.addStretch()

        # 当前密钥状态显示（深色主题）
        self.key_status_label = QLabel("密钥: 未配置")
        self.key_status_label.setStyleSheet("""
            color: #cccccc;
            padding: 6px 15px;
            background: #333333;
            border-radius: 6px;
            border: 1px solid #404040;
            font-size: 12px;
            min-width: 120px;
        """)
        layout.addWidget(self.key_status_label)

        # 密钥设置按钮
        self.settings_btn = PushButton(FluentIcon.SETTING, "")
        self.settings_btn.setFixedSize(32, 32)
        self.settings_btn.clicked.connect(self.show_settings_dialog)
        self.settings_btn.setStyleSheet("""
            QPushButton {
                border: none;
                background-color: transparent;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
            }
        """)
        layout.addWidget(self.settings_btn)

        return bar

    def create_control_panel(self):
        """创建控制面板（深色主题）"""
        panel = QWidget()
        panel.setStyleSheet("QWidget { background-color: #1e1e1e; }")
        layout = QVBoxLayout(panel)
        layout.setSpacing(12)

        # 创建滚动区域
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setStyleSheet("""
            QScrollArea {
                background-color: #1e1e1e;
                border: none;
            }
            QScrollBar:vertical {
                background-color: #2a2a2a;
                width: 8px;
                border-radius: 4px;
            }
            QScrollBar::handle:vertical {
                background-color: #4a4a4a;
                border-radius: 4px;
                min-height: 20px;
            }
            QScrollBar::handle:vertical:hover {
                background-color: #5a5a5a;
            }
        """)

        scroll_widget = QWidget()
        scroll_widget.setStyleSheet("QWidget { background-color: #1e1e1e; }")
        scroll_layout = QVBoxLayout(scroll_widget)
        scroll_layout.setSpacing(12)

        # 图片输入组
        image_group = self.create_image_input_group()
        scroll_layout.addWidget(image_group)

        # 批量任务组
        batch_group = self.create_batch_group()
        scroll_layout.addWidget(batch_group)

        # 视频参数组
        params_group = self.create_params_group()
        scroll_layout.addWidget(params_group)

        # 操作按钮组
        actions_group = self.create_actions_group()
        scroll_layout.addWidget(actions_group)

        scroll_layout.addStretch()
        scroll.setWidget(scroll_widget)
        layout.addWidget(scroll)

        return panel

    def create_image_input_group(self):
        """创建图片输入组（深色主题）"""
        group = QGroupBox("📸 图片输入")
        group.setStyleSheet("""
            QGroupBox {
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 8px;
                margin-top: 8px;
                padding-top: 8px;
                background-color: #2a2a2a;
                color: #ffffff;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 8px 0 8px;
                color: #ffffff;
                font-size: 14px;
            }
        """)
        layout = QVBoxLayout(group)
        layout.setSpacing(10)

        # 输入方式选择（简化，一行显示）
        self.input_type_combo = ComboBox()
        self.input_type_combo.addItems(["图片URL", "本地文件上传"])
        self.input_type_combo.setFixedHeight(32)
        self.input_type_combo.setStyleSheet("""
            QComboBox {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                padding: 4px 8px;
                color: #ffffff;
                font-size: 13px;
            }
            QComboBox::drop-down {
                border: none;
                width: 20px;
            }
            QComboBox::down-arrow {
                image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAA7AAAAOwBeShxvQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAEFSURBVCiRldKxSgNBEMbxH0QZ0CuEF2CiEwJCgKESFuwBLhAT8AFyEO7wELsAC7AQX4CNxgU0cG6+dCZmZn8ZzYwXJJW8k8/fnOeOA8gw/r9fSEECGNFIAiCRZSROJIKJVmQygJMFQYGIFFsCgnhBaiBiOIEFEZgYhBRRGYGGYBFJp9uQRZZYcS1Lb5EA/ghggCVBJEARRyESOhKhszEMDQDdICB9ALRxZUeCcOPPMi5F+T8SX6FMaVvUIFxAIsgYgsI6IEHEhgUYEagIYRGAqPwiwAEYQmAqBQbY4QhBiBoZfn+/fXfjPMO4KdYvKEnKcTb1ncNcIrr8AyVcOlH9Zc1wAAAAASUVORK5CYII=);
                width: 12px;
                height: 12px;
            }
            QComboBox QAbstractItemView {
                background-color: #333333;
                border: 1px solid #404040;
                selection-background-color: #4a90e2;
                color: #ffffff;
            }
        """)
        self.input_type_combo.currentIndexChanged.connect(self.on_input_type_changed)
        layout.addWidget(self.input_type_combo)

        # URL输入框
        self.url_widget = QWidget()
        url_layout = QVBoxLayout(self.url_widget)
        url_layout.setContentsMargins(0, 0, 0, 0)

        self.image_url_edit = LineEdit()
        self.image_url_edit.setFixedHeight(32)
        self.image_url_edit.setPlaceholderText("输入图片URL地址...")
        self.image_url_edit.setStyleSheet("""
            QLineEdit {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                padding: 6px 12px;
                color: #ffffff;
                font-size: 13px;
            }
            QLineEdit:focus {
                border: 1px solid #4a90e2;
            }
        """)
        url_layout.addWidget(self.image_url_edit)

        layout.addWidget(self.url_widget)

        # 本地文件上传区域
        self.upload_widget = QWidget()
        upload_layout = QVBoxLayout(self.upload_widget)
        upload_layout.setContentsMargins(0, 0, 0, 0)

        # 拖拽上传区域
        self.drop_widget = ImageDropWidget()
        self.drop_widget.image_dropped.connect(self.on_image_dropped)
        upload_layout.addWidget(self.drop_widget)

        layout.addWidget(self.upload_widget)

        # 初始状态
        self.on_input_type_changed(0)

        return group

    def create_batch_group(self):
        """创建批量任务组（深色主题）"""
        group = QGroupBox("📋 批量任务管理")
        group.setStyleSheet("""
            QGroupBox {
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 8px;
                margin-top: 8px;
                padding-top: 8px;
                background-color: #2a2a2a;
                color: #ffffff;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 8px 0 8px;
                color: #ffffff;
                font-size: 14px;
            }
        """)
        layout = QVBoxLayout(group)
        layout.setSpacing(10)

        # 任务列表
        self.task_list_widget = QWidget()
        self.task_list_layout = QVBoxLayout(self.task_list_widget)
        self.task_list_layout.setSpacing(10)

        # 创建滚动区域用于任务列表
        self.task_scroll = QScrollArea()
        self.task_scroll.setWidgetResizable(True)
        self.task_scroll.setFixedHeight(150)
        self.task_scroll.setWidget(self.task_list_widget)

        layout.addWidget(QLabel("待处理任务:"))
        layout.addWidget(self.task_scroll)

        # 添加任务按钮
        add_task_layout = QHBoxLayout()
        self.add_task_btn = PushButton(FluentIcon.ADD, "添加到任务列表")
        self.add_task_btn.setFixedHeight(32)
        self.add_task_btn.setStyleSheet("""
            QPushButton {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 13px;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
                border: 1px solid #4a90e2;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        self.add_task_btn.clicked.connect(self.add_to_batch_tasks)
        add_task_layout.addWidget(self.add_task_btn)

        self.clear_tasks_btn = PushButton(FluentIcon.DELETE, "清空任务")
        self.clear_tasks_btn.setFixedHeight(32)
        self.clear_tasks_btn.setStyleSheet("""
            QPushButton {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 13px;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
                border: 1px solid #dc3545;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        self.clear_tasks_btn.clicked.connect(self.clear_batch_tasks)
        add_task_layout.addWidget(self.clear_tasks_btn)

        layout.addLayout(add_task_layout)

        return group

    def create_params_group(self):
        """创建视频参数组（深色主题）"""
        group = QGroupBox("⚙️ 视频参数")
        group.setStyleSheet("""
            QGroupBox {
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 8px;
                margin-top: 8px;
                padding-top: 8px;
                background-color: #2a2a2a;
                color: #ffffff;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 8px 0 8px;
                color: #ffffff;
                font-size: 14px;
            }
        """)
        layout = QGridLayout(group)
        layout.setSpacing(10)

        # 预设分辨率
        layout.addWidget(QLabel("预设分辨率:"), 0, 0)
        self.resolution_combo = ComboBox()
        self.resolution_combo.addItems([
            "自定义",
            "480p - 16:9 (854×480)",
            "480p - 9:16 (480×854)",
            "720p - 16:9 (1280×720)",
            "720p - 9:16 (720×1280)"
        ])
        self.resolution_combo.setFixedHeight(32)
        self.resolution_combo.setStyleSheet("""
            QComboBox {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                padding: 4px 8px;
                color: #ffffff;
                font-size: 13px;
            }
            QComboBox::drop-down {
                border: none;
                width: 20px;
            }
            QComboBox::down-arrow {
                image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAA7AAAAOwBeShxvQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAEFSURBVCiRldKxSgNBEMbxH0QZ0CuEF2CiEwJCgKESFuwBLhAT8AFyEO7wELsAC7AQX4CNxgU0cG6+dCZmZn8ZzYwXJJW8k8/fnOeOA8gw/r9fSEECGNFIAiCRZSROJIKJVmQygJMFQYGIFFsCgnhBaiBiOIEFEZgYhBRRGYGGYBFJp9uQRZZYcS1Lb5EA/ghggCVBJEARRyESOhKhszEMDQDdICB9ALRxZUeCcOPPMi5F+T8SX6FMaVvUIFxAIsgYgsI6IEHEhgUYEagIYRGAqPwiwAEYQmAqBQbY4QhBiBoZfn+/fXfjPMO4KdYvKEnKcTb1ncNcIrr8AyVcOlH9Zc1wAAAAASUVORK5CYII=);
                width: 12px;
                height: 12px;
            }
            QComboBox QAbstractItemView {
                background-color: #333333;
                border: 1px solid #404040;
                selection-background-color: #4a90e2;
                color: #ffffff;
            }
        """)
        self.resolution_combo.currentIndexChanged.connect(self.on_resolution_changed)
        layout.addWidget(self.resolution_combo, 0, 1, 1, 2)

        # 自定义尺寸
        layout.addWidget(QLabel("宽度:"), 1, 0)
        self.width_spin = QSpinBox()
        self.width_spin.setRange(256, 2048)
        self.width_spin.setValue(720)
        self.width_spin.setSingleStep(64)
        self.width_spin.setFixedHeight(32)
        self.width_spin.setStyleSheet("""
            QSpinBox {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                padding: 4px 8px;
                color: #ffffff;
                font-size: 13px;
            }
            QSpinBox:focus {
                border: 1px solid #4a90e2;
            }
        """)
        layout.addWidget(self.width_spin, 1, 1)

        layout.addWidget(QLabel("高度:"), 1, 2)
        self.height_spin = QSpinBox()
        self.height_spin.setRange(256, 2048)
        self.height_spin.setValue(720)
        self.height_spin.setSingleStep(64)
        self.height_spin.setFixedHeight(32)
        self.height_spin.setStyleSheet("""
            QSpinBox {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                padding: 4px 8px;
                color: #ffffff;
                font-size: 13px;
            }
            QSpinBox:focus {
                border: 1px solid #4a90e2;
            }
        """)
        layout.addWidget(self.height_spin, 1, 3)

        # 视频时长
        layout.addWidget(QLabel("视频时长(秒):"), 2, 0)
        self.duration_spin = QSpinBox()
        self.duration_spin.setRange(1, 30)
        self.duration_spin.setValue(5)
        self.duration_spin.setSingleStep(1)
        self.duration_spin.setFixedHeight(32)
        self.duration_spin.setStyleSheet("""
            QSpinBox {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                padding: 4px 8px;
                color: #ffffff;
                font-size: 13px;
            }
            QSpinBox:focus {
                border: 1px solid #4a90e2;
            }
        """)
        self.duration_spin.valueChanged.connect(self.update_frames)
        layout.addWidget(self.duration_spin, 2, 1)

        # 帧数显示
        layout.addWidget(QLabel("总帧数:"), 2, 2)
        self.frames_label = QLabel("81")
        self.frames_label.setStyleSheet("""
            QLabel {
                font-weight: bold;
                color: #4a90e2;
                background: #2a3a4a;
                padding: 8px;
                border-radius: 4px;
                font-size: 14px;
                border: 1px solid #3a5a7a;
            }
        """)
        layout.addWidget(self.frames_label, 2, 3)

        # 帧数说明
        frames_note = QLabel("注：16帧 = 1秒，含封面帧")
        frames_note.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(frames_note, 3, 0, 1, 4)

        return group

    def create_actions_group(self):
        """创建操作按钮组（深色主题）"""
        group = QGroupBox("🚀 操作")
        group.setStyleSheet("""
            QGroupBox {
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 8px;
                margin-top: 8px;
                padding-top: 8px;
                background-color: #2a2a2a;
                color: #ffffff;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 8px 0 8px;
                color: #ffffff;
                font-size: 14px;
            }
        """)
        layout = QVBoxLayout(group)
        layout.setSpacing(10)

        # 提示词输入（深色主题，增大字体）
        self.prompt_edit = QTextEdit()
        self.prompt_edit.setPlaceholderText("输入视频生成的提示词，例如：美女跳舞、风景变化等...")
        self.prompt_edit.setFixedHeight(100)
        self.prompt_edit.setStyleSheet("""
            QTextEdit {
                font-size: 14px;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                border: 1px solid #404040;
                border-radius: 6px;
                padding: 10px;
                background-color: #333333;
                color: #ffffff;
                selection-background-color: #4a90e2;
            }
            QTextEdit:focus {
                border: 1px solid #4a90e2;
            }
        """)
        layout.addWidget(self.prompt_edit)

        # 生成按钮（深色主题）
        button_layout = QHBoxLayout()

        self.single_generate_btn = PrimaryPushButton(FluentIcon.PLAY, "单个生成")
        self.single_generate_btn.setFixedHeight(40)
        self.single_generate_btn.setStyleSheet("""
            QPushButton {
                background-color: #4a90e2;
                border: none;
                border-radius: 6px;
                color: #ffffff;
                font-size: 14px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #5ba0f2;
            }
            QPushButton:pressed {
                background-color: #3a80d2;
            }
        """)
        self.single_generate_btn.clicked.connect(self.generate_single_video)
        button_layout.addWidget(self.single_generate_btn)

        self.batch_generate_btn = PrimaryPushButton(FluentIcon.PLAY_SOLID, "批量生成")
        self.batch_generate_btn.setFixedHeight(40)
        self.batch_generate_btn.setStyleSheet("""
            QPushButton {
                background-color: #28a745;
                border: none;
                border-radius: 6px;
                color: #ffffff;
                font-size: 14px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #38b755;
            }
            QPushButton:pressed {
                background-color: #1a9735;
            }
        """)
        self.batch_generate_btn.clicked.connect(self.generate_batch_videos)
        button_layout.addWidget(self.batch_generate_btn)

        layout.addLayout(button_layout)

        return group

    def create_result_panel(self):
        """创建结果展示面板（深色主题）"""
        panel = QWidget()
        panel.setStyleSheet("QWidget { background-color: #1e1e1e; }")
        layout = QVBoxLayout(panel)
        layout.setSpacing(10)
        layout.setContentsMargins(5, 0, 0, 0)

        # 创建Tab Widget
        self.result_tabs = QTabWidget()
        self.result_tabs.setStyleSheet("""
            QTabWidget::pane {
                border: 1px solid #404040;
                background: #2a2a2a;
                border-radius: 8px;
            }
            QTabBar::tab {
                background: #333333;
                color: #cccccc;
                padding: 10px 20px;
                margin-right: 2px;
                border-top-left-radius: 8px;
                border-top-right-radius: 8px;
                border: 1px solid #404040;
                border-bottom: none;
                font-weight: 500;
                font-size: 13px;
            }
            QTabBar::tab:selected {
                background: #4a90e2;
                color: #ffffff;
                border-bottom: 1px solid #4a90e2;
            }
            QTabBar::tab:hover:!selected {
                background: #3a3a3a;
                color: #ffffff;
            }
        """)

        # 视频列表Tab
        self.video_list_widget = QWidget()
        video_list_layout = QVBoxLayout(self.video_list_widget)
        video_list_layout.setContentsMargins(10, 10, 10, 10)

        # 批量进度
        self.batch_progress_bar = ProgressBar()
        self.batch_progress_bar.setFixedHeight(15)
        self.batch_progress_label = QLabel("准备就绪")
        video_list_layout.addWidget(self.batch_progress_label)
        video_list_layout.addWidget(self.batch_progress_bar)

        # 视频列表滚动区域
        self.video_scroll = SmoothScrollArea()
        self.video_scroll_widget = QWidget()
        self.video_scroll_layout = QVBoxLayout(self.video_scroll_widget)
        self.video_scroll_layout.setSpacing(10)
        self.video_scroll.setWidget(self.video_scroll_widget)
        self.video_scroll.setWidgetResizable(True)

        video_list_layout.addWidget(QLabel("生成结果:"))
        video_list_layout.addWidget(self.video_scroll)

        self.result_tabs.addTab(self.video_list_widget, "视频列表")

        # 日志Tab
        self.log_widget = QWidget()
        log_layout = QVBoxLayout(self.log_widget)
        log_layout.setContentsMargins(10, 10, 10, 10)

        # 日志文本框
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setStyleSheet("""
            QTextEdit {
                font-family: 'Consolas', 'Monaco', monospace;
                font-size: 12px;
                background-color: #1a1a1a;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                selection-background-color: #4a90e2;
            }
        """)
        log_layout.addWidget(QLabel("操作日志:"))
        log_layout.addWidget(self.log_text)

        # 日志控制按钮
        log_controls = QHBoxLayout()
        clear_log_btn = PushButton(FluentIcon.DELETE, "清空日志")
        clear_log_btn.setStyleSheet("""
            QPushButton {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 13px;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
                border: 1px solid #dc3545;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        clear_log_btn.clicked.connect(self.clear_log)
        log_controls.addWidget(clear_log_btn)

        save_log_btn = PushButton(FluentIcon.SAVE, "保存日志")
        save_log_btn.setStyleSheet("""
            QPushButton {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 13px;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
                border: 1px solid #28a745;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        save_log_btn.clicked.connect(self.save_log)
        log_controls.addWidget(save_log_btn)

        log_controls.addStretch()
        log_layout.addLayout(log_controls)

        self.result_tabs.addTab(self.log_widget, "操作日志")

        layout.addWidget(self.result_tabs)

        return panel

    def on_input_type_changed(self, index):
        """输入方式改变"""
        is_url = index == 0
        self.url_widget.setVisible(is_url)
        self.upload_widget.setVisible(not is_url)

    def on_resolution_changed(self, index):
        """预设分辨率改变"""
        resolutions = {
            1: (854, 480),   # 480p - 16:9
            2: (480, 854),   # 480p - 9:16
            3: (1280, 720),  # 720p - 16:9
            4: (720, 1280)   # 720p - 9:16
        }

        if index in resolutions:
            width, height = resolutions[index]
            self.width_spin.setValue(width)
            self.height_spin.setValue(height)

    def update_frames(self, seconds):
        """根据秒数更新帧数"""
        total_frames = seconds * 16 + 1
        self.frames_label.setText(str(total_frames))

    def on_image_dropped(self, file_path, base64_data):
        """处理图片拖拽事件"""
        self.add_log(f"📁 已加载图片: {os.path.basename(file_path)}")

    def add_to_batch_tasks(self):
        """添加到批量任务列表"""
        # 获取当前设置
        image_input = self.get_current_image_input()
        prompt = self.prompt_edit.toPlainText().strip()

        if not image_input:
            QMessageBox.warning(self, "警告", "请先选择图片")
            return

        if not prompt:
            QMessageBox.warning(self, "警告", "请输入视频提示词")
            return

        # 创建任务数据
        task = {
            'name': f"任务_{len(self.batch_tasks)+1}",
            'image_input': image_input,
            'prompt': prompt,
            'width': self.width_spin.value(),
            'height': self.height_spin.value(),
            'num_frames': self.duration_spin.value() * 16 + 1,
            'timestamp': datetime.now().isoformat()
        }

        self.batch_tasks.append(task)
        self.update_task_list_display()
        self.add_log(f"📝 已添加任务: {task['name']}")

    def update_task_list_display(self):
        """更新任务列表显示"""
        # 清空现有显示
        while self.task_list_layout.count():
            item = self.task_list_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        # 添加任务卡片
        for i, task in enumerate(self.batch_tasks):
            task_card = self.create_task_card(task, i)
            self.task_list_layout.addWidget(task_card)

    def create_task_card(self, task, index):
        """创建任务卡片"""
        card = CardWidget()
        card.setFixedHeight(60)
        layout = QHBoxLayout(card)
        layout.setContentsMargins(10, 5, 10, 5)

        # 任务信息
        info_layout = QVBoxLayout()
        name_label = QLabel(task['name'])
        name_label.setStyleSheet("font-weight: bold;")
        info_layout.addWidget(name_label)

        prompt_label = QLabel(f"提示词: {task['prompt'][:30]}...")
        prompt_label.setStyleSheet("color: #666; font-size: 12px;")
        info_layout.addWidget(prompt_label)

        layout.addLayout(info_layout)

        layout.addStretch()

        # 删除按钮
        delete_btn = PushButton(FluentIcon.DELETE, "")
        delete_btn.setFixedSize(30, 30)
        delete_btn.clicked.connect(lambda: self.remove_task(index))
        layout.addWidget(delete_btn)

        return card

    def remove_task(self, index):
        """删除任务"""
        if 0 <= index < len(self.batch_tasks):
            task_name = self.batch_tasks[index]['name']
            del self.batch_tasks[index]
            self.update_task_list_display()
            self.add_log(f"🗑️ 已删除任务: {task_name}")

    def clear_batch_tasks(self):
        """清空批量任务"""
        self.batch_tasks.clear()
        self.update_task_list_display()
        self.add_log("🗑️ 已清空所有任务")

    def get_current_image_input(self):
        """获取当前图片输入"""
        if self.input_type_combo.currentIndex() == 0:  # URL
            return self.image_url_edit.text().strip()
        else:  # 本地文件
            return self.drop_widget.base64_data

    def generate_single_video(self):
        """生成单个视频"""
        image_input = self.get_current_image_input()
        prompt = self.prompt_edit.toPlainText().strip()

        if not image_input:
            QMessageBox.warning(self, "警告", "请先选择图片")
            return

        if not prompt:
            QMessageBox.warning(self, "警告", "请输入视频提示词")
            return

        # 创建单个任务
        task = {
            'name': "单个任务",
            'image_input': image_input,
            'prompt': prompt,
            'width': self.width_spin.value(),
            'height': self.height_spin.value(),
            'num_frames': self.duration_spin.value() * 16 + 1
        }

        # 执行单个任务
        self.execute_batch_tasks([task])

    def generate_batch_videos(self):
        """生成批量视频"""
        if not self.batch_tasks:
            QMessageBox.warning(self, "警告", "请先添加任务到列表")
            return

        self.execute_batch_tasks(self.batch_tasks)

    def execute_batch_tasks(self, tasks):
        """执行批量任务"""
        if self.current_batch_worker and self.current_batch_worker.isRunning():
            QMessageBox.warning(self, "警告", "当前有任务正在执行")
            return

        self.current_batch_worker = BatchVideoGenerationWorker(tasks)
        self.current_batch_worker.progress_updated.connect(self.update_task_progress)
        self.current_batch_worker.task_finished.connect(self.on_task_finished)
        self.current_batch_worker.batch_progress.connect(self.update_batch_progress)
        self.current_batch_worker.log_updated.connect(self.add_log)

        # 如果有密钥文件，加载密钥
        if hasattr(self, 'key_file_path') and self.key_file_path:
            self.current_batch_worker.api_manager.load_keys_from_file(self.key_file_path)

        self.current_batch_worker.start()

    def update_task_progress(self, progress, message, task_id):
        """更新单个任务进度"""
        self.add_log(f"[{task_id}] {progress}% - {message}")

    def on_task_finished(self, success, message, result_data, task_id):
        """任务完成回调"""
        if success:
            self.add_log(f"✅ [{task_id}] {message}")
            self.add_video_result(result_data)
        else:
            self.add_log(f"❌ [{task_id}] {message}")

    def update_batch_progress(self, current, total):
        """更新批量进度"""
        progress = int((current / total) * 100) if total > 0 else 0
        self.batch_progress_bar.setValue(progress)
        self.batch_progress_label.setText(f"批量进度: {current}/{total}")

    def add_video_result(self, video_data):
        """添加视频结果"""
        # 创建视频结果卡片
        video_card = VideoResultCard(video_data)
        self.video_scroll_layout.addWidget(video_card)

        # 切换到视频列表Tab
        self.result_tabs.setCurrentIndex(0)

    def show_settings_dialog(self):
        """显示设置对话框"""
        dialog = APISettingsDialog(self.api_manager, self)
        if dialog.exec_() == QDialog.Accepted:
            self.update_key_status()
            self.save_settings()

    def update_key_status(self):
        """更新密钥状态显示（深色主题）"""
        count = self.api_manager.get_available_keys_count()
        if count > 0:
            self.key_status_label.setText(f"密钥: {count}个可用")
            self.key_status_label.setStyleSheet("""
                color: #4CAF50;
                padding: 6px 15px;
                background: #1e3a1e;
                border-radius: 6px;
                border: 1px solid #2e5a2e;
                font-size: 12px;
                min-width: 120px;
            """)
        else:
            self.key_status_label.setText("密钥: 未配置")
            self.key_status_label.setStyleSheet("""
                color: #ff6b6b;
                padding: 6px 15px;
                background: #3a1e1e;
                border-radius: 6px;
                border: 1px solid #5a2e2e;
                font-size: 12px;
                min-width: 120px;
            """)

    def add_log(self, message):
        """添加日志"""
        self.log_text.append(message)
        # 自动滚动到底部
        cursor = self.log_text.textCursor()
        cursor.movePosition(cursor.End)
        self.log_text.setTextCursor(cursor)

    def clear_log(self):
        """清空日志"""
        self.log_text.clear()
        self.add_log("📝 日志已清空")

    def save_log(self):
        """保存日志"""
        file_path, _ = QFileDialog.getSaveFileName(
            self, "保存日志", f"video_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt", "文本文件 (*.txt)"
        )
        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(self.log_text.toPlainText())
                QMessageBox.information(self, "成功", f"日志已保存到: {file_path}")
            except Exception as e:
                QMessageBox.critical(self, "错误", f"保存失败: {str(e)}")

    def load_settings(self):
        """加载设置"""
        try:
            settings_file = "video_settings.json"
            if os.path.exists(settings_file):
                with open(settings_file, 'r', encoding='utf-8') as f:
                    settings = json.load(f)

                # 加载密钥文件路径
                if 'key_file' in settings:
                    self.api_manager.load_keys_from_file(settings['key_file'])
                    self.key_file_path = settings['key_file']

                self.update_key_status()
        except Exception as e:
            self.add_log(f"加载设置失败: {e}")

    def save_settings(self):
        """保存设置"""
        try:
            settings = {}
            if hasattr(self, 'key_file_path') and self.key_file_path:
                settings['key_file'] = self.key_file_path

            settings_file = "video_settings.json"
            with open(settings_file, 'w', encoding='utf-8') as f:
                json.dump(settings, f, ensure_ascii=False, indent=2)
        except Exception as e:
            self.add_log(f"保存设置失败: {e}")

# API设置对话框
class APISettingsDialog(QDialog):
    """API设置对话框"""

    def __init__(self, api_manager, parent=None):
        super().__init__(parent)
        self.api_manager = api_manager
        self.setWindowTitle("API密钥设置")
        self.setMinimumSize(500, 400)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)

        # Web App ID设置
        webapp_group = QGroupBox("Web App ID")
        webapp_layout = QVBoxLayout(webapp_group)

        self.webapp_id_spin = QSpinBox()
        self.webapp_id_spin.setRange(1, 99999)
        self.webapp_id_spin.setValue(self.api_manager.web_app_id)
        webapp_layout.addWidget(QLabel("Web App ID:"))
        webapp_layout.addWidget(self.webapp_id_spin)

        layout.addWidget(webapp_group)

        # API密钥文件设置
        key_group = QGroupBox("API密钥文件")
        key_layout = QVBoxLayout(key_group)

        file_layout = QHBoxLayout()
        self.key_file_edit = LineEdit()
        self.key_file_edit.setPlaceholderText("输入密钥文件路径...")
        self.key_file_edit.setText(getattr(self.parent(), 'key_file_path', ''))
        file_layout.addWidget(self.key_file_edit)

        self.browse_btn = PushButton(FluentIcon.FOLDER, "浏览")
        self.browse_btn.clicked.connect(self.browse_key_file)
        file_layout.addWidget(self.browse_btn)

        key_layout.addLayout(file_layout)

        # 密钥说明
        info_label = QLabel("密钥文件格式：每行一个API密钥，建议至少18个密钥用于批量处理")
        info_label.setStyleSheet("color: #666; font-size: 12px; padding: 5px;")
        key_layout.addWidget(info_label)

        # 测试按钮
        self.test_btn = PushButton(FluentIcon.PLAY, "测试密钥")
        self.test_btn.clicked.connect(self.test_keys)
        key_layout.addWidget(self.test_btn)

        layout.addWidget(key_group)

        # 状态显示
        self.status_label = QLabel("准备就绪")
        self.status_label.setStyleSheet("padding: 10px; background: #333333; border-radius: 4px;")
        layout.addWidget(self.status_label)

        # 按钮
        button_layout = QHBoxLayout()
        save_btn = PrimaryPushButton("保存")
        save_btn.clicked.connect(self.save_settings)
        button_layout.addWidget(save_btn)

        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)

        layout.addLayout(button_layout)

    def browse_key_file(self):
        """浏览密钥文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "选择API密钥文件", "", "文本文件 (*.txt);;所有文件 (*)"
        )
        if file_path:
            self.key_file_edit.setText(file_path)

    def test_keys(self):
        """测试密钥"""
        file_path = self.key_file_edit.text().strip()
        if not file_path or not os.path.exists(file_path):
            QMessageBox.warning(self, "警告", "请选择有效的密钥文件")
            return

        if self.api_manager.load_keys_from_file(file_path):
            count = len(self.api_manager.api_keys)
            self.status_label.setText(f"✅ 成功加载 {count} 个API密钥")
            self.status_label.setStyleSheet("padding: 10px; background: #e8f5e8; border-radius: 4px; color: #4CAF50;")
        else:
            self.status_label.setText("❌ 密钥文件加载失败")
            self.status_label.setStyleSheet("padding: 10px; background: #ffebee; border-radius: 4px; color: #f44336;")

    def save_settings(self):
        """保存设置"""
        self.api_manager.web_app_id = self.webapp_id_spin.value()

        file_path = self.key_file_edit.text().strip()
        if file_path and os.path.exists(file_path):
            if self.api_manager.load_keys_from_file(file_path):
                self.parent().key_file_path = file_path
                self.accept()
            else:
                QMessageBox.warning(self, "警告", "密钥文件保存失败")
        else:
            self.accept()

# 视频结果卡片
class VideoResultCard(CardWidget):
    """视频结果展示卡片"""

    def __init__(self, video_data, parent=None):
        super().__init__(parent)
        self.video_data = video_data
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(10)
        layout.setContentsMargins(15, 15, 15, 15)

        # 标题
        title = self.video_data.get('task_name', '未命名视频')
        if 'timestamp' in self.video_data:
            try:
                dt = datetime.fromisoformat(self.video_data['timestamp'])
                title += f" ({dt.strftime('%H:%M:%S')})"
            except:
                pass

        self.title_label = QLabel(title)
        self.title_label.setStyleSheet("font-weight: bold; color: #333; font-size: 14px;")
        layout.addWidget(self.title_label)

        # 视频信息
        info_text = f"尺寸: {self.video_data.get('width', 'N/A')}×{self.video_data.get('height', 'N/A')}"
        info_text += f"\n帧数: {self.video_data.get('num_frames', 'N/A')}"
        self.info_label = QLabel(info_text)
        self.info_label.setStyleSheet("color: #666; font-size: 12px;")
        layout.addWidget(self.info_label)

        # 提示词预览
        prompt = self.video_data.get('prompt', '')
        if prompt:
            prompt_preview = prompt[:50] + "..." if len(prompt) > 50 else prompt
            self.prompt_label = QLabel(f"提示词: {prompt_preview}")
            self.prompt_label.setStyleSheet("color: #888; font-size: 11px;")
            self.prompt_label.setWordWrap(True)
            layout.addWidget(self.prompt_label)

        # 视频URL显示
        video_url = self.video_data.get('video_url', '')
        if video_url:
            url_label = QLabel("视频URL:")
            url_label.setStyleSheet("color: #333; font-size: 12px; font-weight: bold;")
            layout.addWidget(url_label)

            self.url_edit = LineEdit()
            self.url_edit.setText(video_url)
            self.url_edit.setReadOnly(True)
            self.url_edit.setStyleSheet("font-size: 11px; padding: 5px;")
            layout.addWidget(self.url_edit)

        # 按钮
        button_layout = QHBoxLayout()

        self.view_btn = PushButton(FluentIcon.VIEW, "播放")
        self.view_btn.clicked.connect(self.view_video)
        button_layout.addWidget(self.view_btn)

        self.download_btn = PushButton(FluentIcon.DOWNLOAD, "下载")
        self.download_btn.clicked.connect(self.download_video)
        button_layout.addWidget(self.download_btn)

        self.copy_url_btn = PushButton(FluentIcon.COPY, "复制URL")
        self.copy_url_btn.clicked.connect(self.copy_url)
        button_layout.addWidget(self.copy_url_btn)

        layout.addLayout(button_layout)

    def view_video(self):
        """查看视频"""
        video_url = self.video_data.get('video_url', '')
        if video_url:
            from PyQt5.QtCore import QUrl
            from PyQt5.QtGui import QDesktopServices
            QDesktopServices.openUrl(QUrl(video_url))
        else:
            QMessageBox.warning(self, "警告", "视频URL不可用")

    def download_video(self):
        """下载视频"""
        video_url = self.video_data.get('video_url', '')
        if not video_url:
            QMessageBox.warning(self, "警告", "视频URL不可用")
            return

        file_path, _ = QFileDialog.getSaveFileName(
            self,
            f"保存视频 {self.video_data.get('task_name', 'video')}",
            f"{self.video_data.get('task_name', 'video')}.mp4",
            "MP4 Files (*.mp4)"
        )

        if file_path:
            try:
                self.download_btn.setEnabled(False)
                self.download_btn.setText("下载中...")

                response = requests.get(video_url, stream=True, timeout=300)
                response.raise_for_status()

                with open(file_path, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)

                QMessageBox.information(self, "成功", f"视频已保存到: {file_path}")
            except Exception as e:
                QMessageBox.critical(self, "错误", f"下载失败: {str(e)}")
            finally:
                self.download_btn.setEnabled(True)
                self.download_btn.setText("下载")

    def copy_url(self):
        """复制视频URL"""
        video_url = self.video_data.get('video_url', '')
        if video_url:
            from PyQt5.QtWidgets import QApplication
            clipboard = QApplication.clipboard()
            clipboard.setText(video_url)

            # 显示提示
            from qfluentwidgets import InfoBar
            InfoBar.success(
                title="成功",
                content="视频URL已复制到剪贴板",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=2000,
                parent=self
            )