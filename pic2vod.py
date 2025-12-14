#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
图片转视频生成模块 (pic2vod)
基于 BizyAir API 的图片转视频功能
"""

import os
import json
import time
import threading
import requests
from datetime import datetime
from PyQt5.QtCore import QThread, pyqtSignal, QTimer, Qt
from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
                            QLineEdit, QTextEdit, QPushButton, QComboBox,
                            QSpinBox, QProgressBar, QMessageBox, QFileDialog,
                            QGroupBox, QTabWidget, QSplitter, QFrame,
                            QGridLayout)
from PyQt5.QtGui import QPixmap
import qfluentwidgets as qf
from qfluentwidgets import (FluentIcon, CardWidget, ElevatedCardWidget,
                          SmoothScrollArea, SubtitleLabel, BodyLabel,
                          PrimaryPushButton, PushButton, LineEdit, ComboBox,
                          ProgressBar, InfoBar, InfoBarPosition)

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

# 视频生成工作线程
class VideoGenerationWorker(QThread):
    """视频生成工作线程"""
    progress_updated = pyqtSignal(int, str)
    time_updated = pyqtSignal(str)
    finished = pyqtSignal(bool, str, dict)  # success, message, result_data
    log_updated = pyqtSignal(str)  # 日志更新信号

    def __init__(self, image_input, prompt, width, height, num_frames):
        super().__init__()
        self.image_input = image_input
        self.prompt = prompt
        self.width = width
        self.height = height
        self.num_frames = num_frames
        self.web_app_id = 39386
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
            self.time_updated.emit(f"运行时间: {elapsed:.1f}秒")

    def log_message(self, message):
        """记录日志消息"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {message}"
        self.log_updated.emit(log_entry)

        # 写入日志文件
        log_file = os.path.join(self.log_dir, "video_generation.log")
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(log_entry + "\n")
        except Exception as e:
            print(f"写入日志失败: {e}")

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True
        self.log_message("任务已取消")

    def run(self):
        """运行视频生成"""
        try:
            self.start_time = time.time()
            self.timer.start(100)  # 每100毫秒更新一次时间显示

            api_key = config_manager.get('api.api_key', MODEL_API_KEY)
            if not api_key:
                self.timer.stop()
                self.finished.emit(False, "API密钥未配置", {})
                return

            self.log_message(f"开始生成视频 - 图片: {self.image_input[:50]}...")
            self.log_message(f"参数: 宽度={self.width}, 高度={self.height}, 帧数={self.num_frames}")

            base_url = 'https://api.bizyair.cn/w/v1/webapp/task/openapi/create'
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            }

            # 构建请求数据
            input_values = {
                "67:LoadImage.image": self.image_input,
                "68:ImageResizeKJv2.width": self.width,
                "68:ImageResizeKJv2.height": self.height,
                "16:WanVideoTextEncode.positive_prompt": self.prompt,
                "89:WanVideoImageToVideoEncode.num_frames": self.num_frames
            }

            request_data = {
                "web_app_id": self.web_app_id,
                "suppress_preview_output": True,
                "input_values": input_values
            }

            self.log_message(f"发送请求到: {base_url}")
            self.progress_updated.emit(10, "正在发送请求...")

            response = requests.post(
                base_url,
                headers=headers,
                json=request_data,
                timeout=600  # 10分钟超时
            )

            if self.is_cancelled:
                self.timer.stop()
                self.finished.emit(False, "任务已取消", {})
                return

            self.progress_updated.emit(50, "正在处理响应...")

            if response.status_code == 200:
                result = response.json()
                self.log_message(f"响应状态: {result.get('status', 'Unknown')}")

                if result.get("status") == "Success" and result.get("outputs"):
                    outputs = result["outputs"]
                    if outputs and len(outputs) > 0:
                        video_output = outputs[0]
                        video_url = video_output.get("object_url", "")

                        if video_url:
                            self.log_message(f"视频生成成功: {video_url}")
                            self.progress_updated.emit(100, "视频生成完成!")

                            result_data = {
                                "video_url": video_url,
                                "input_image": self.image_input,
                                "prompt": self.prompt,
                                "width": self.width,
                                "height": self.height,
                                "num_frames": self.num_frames,
                                "timestamp": datetime.now().isoformat()
                            }

                            self.timer.stop()
                            self.finished.emit(True, "视频生成成功!", result_data)
                        else:
                            error_msg = "响应中未找到视频URL"
                            self.log_message(f"错误: {error_msg}")
                            self.timer.stop()
                            self.finished.emit(False, error_msg, {})
                    else:
                        error_msg = "响应中没有输出数据"
                        self.log_message(f"错误: {error_msg}")
                        self.timer.stop()
                        self.finished.emit(False, error_msg, {})
                else:
                    error_msg = f"生成失败: {result.get('message', '未知错误')}"
                    self.log_message(f"错误: {error_msg}")
                    self.timer.stop()
                    self.finished.emit(False, error_msg, {})
            else:
                error_msg = f"HTTP请求失败: {response.status_code}"
                self.log_message(f"错误: {error_msg}")
                self.timer.stop()
                self.finished.emit(False, error_msg, {})

        except requests.exceptions.Timeout:
            error_msg = "请求超时，可能需要等待更长时间"
            self.log_message(f"错误: {error_msg}")
            self.timer.stop()
            self.finished.emit(False, error_msg, {})
        except Exception as e:
            error_msg = f"生成失败: {str(e)}"
            self.log_message(f"错误: {error_msg}")
            self.timer.stop()
            self.finished.emit(False, error_msg, {})

# 视频预览小部件
class VideoPreviewWidget(CardWidget):
    """视频预览小部件"""

    def __init__(self, video_data, index, parent=None):
        super().__init__(parent)
        self.video_data = video_data
        self.index = index
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(10)
        layout.setContentsMargins(15, 15, 15, 15)

        # 标题
        title = f"视频 {self.index + 1}"
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
        info_text = f"尺寸: {self.video_data.get('width', 'N/A')}x{self.video_data.get('height', 'N/A')}"
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

        # 按钮
        button_layout = QHBoxLayout()

        self.view_btn = PushButton(FluentIcon.VIEW, "查看")
        self.view_btn.clicked.connect(self.view_video)
        button_layout.addWidget(self.view_btn)

        self.download_btn = PushButton(FluentIcon.DOWNLOAD, "下载")
        self.download_btn.clicked.connect(self.download_video)
        button_layout.addWidget(self.download_btn)

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
            f"保存视频 {self.index + 1}",
            f"video_{self.index + 1}.mp4",
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

# 主要的视频生成界面
class VideoGenerationWidget(QWidget):
    """视频生成主界面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.current_worker = None
        self.generated_videos = []
        self.init_ui()
        self.load_history()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)

        # 标题
        title = SubtitleLabel("🎬 图片转视频生成")
        title.setStyleSheet("font-size: 18px; font-weight: bold;")
        layout.addWidget(title)

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
        splitter.setSizes([400, 600])

    def create_control_panel(self):
        """创建控制面板"""
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setSpacing(15)

        # 图片输入组
        image_group = QGroupBox("图片输入")
        image_layout = QVBoxLayout()

        # 输入方式选择
        self.input_type_combo = ComboBox()
        self.input_type_combo.addItems(["图片URL", "上传本地图片"])
        self.input_type_combo.currentIndexChanged.connect(self.on_input_type_changed)
        image_layout.addWidget(QLabel("输入方式:"))
        image_layout.addWidget(self.input_type_combo)

        # URL输入
        self.image_url_edit = LineEdit()
        self.image_url_edit.setPlaceholderText("输入图片URL地址...")
        image_layout.addWidget(QLabel("图片URL:"))
        image_layout.addWidget(self.image_url_edit)

        # 文件选择
        self.file_path_edit = LineEdit()
        self.file_path_edit.setPlaceholderText("选择本地图片文件...")
        self.file_path_edit.setEnabled(False)
        image_layout.addWidget(QLabel("本地文件:"))
        image_layout.addWidget(self.file_path_edit)

        self.browse_btn = PushButton(FluentIcon.FOLDER, "浏览")
        self.browse_btn.setEnabled(False)
        self.browse_btn.clicked.connect(self.browse_image_file)
        image_layout.addWidget(self.browse_btn)

        image_group.setLayout(image_layout)
        layout.addWidget(image_group)

        # 提示词输入组
        prompt_group = QGroupBox("视频提示词")
        prompt_layout = QVBoxLayout()

        self.prompt_edit = QTextEdit()
        self.prompt_edit.setPlaceholderText("输入视频生成的提示词，例如：美女跳舞、风景变化等...")
        self.prompt_edit.setMaximumHeight(100)
        prompt_layout.addWidget(QLabel("提示词:"))
        prompt_layout.addWidget(self.prompt_edit)

        prompt_group.setLayout(prompt_layout)
        layout.addWidget(prompt_group)

        # 视频参数组
        params_group = QGroupBox("视频参数")
        params_layout = QGridLayout()

        # 预设分辨率
        params_layout.addWidget(QLabel("预设分辨率:"), 0, 0)
        self.resolution_combo = ComboBox()
        self.resolution_combo.addItems([
            "自定义",
            "480p - 16:9 (854×480)",
            "480p - 9:16 (480×854)",
            "720p - 16:9 (1280×720)",
            "720p - 9:16 (720×1280)"
        ])
        self.resolution_combo.currentIndexChanged.connect(self.on_resolution_changed)
        params_layout.addWidget(self.resolution_combo, 0, 1, 1, 2)

        # 自定义尺寸
        params_layout.addWidget(QLabel("宽度:"), 1, 0)
        self.width_spin = QSpinBox()
        self.width_spin.setRange(256, 2048)
        self.width_spin.setValue(720)
        self.width_spin.setSingleStep(64)
        params_layout.addWidget(self.width_spin, 1, 1)

        params_layout.addWidget(QLabel("高度:"), 2, 0)
        self.height_spin = QSpinBox()
        self.height_spin.setRange(256, 2048)
        self.height_spin.setValue(720)
        self.height_spin.setSingleStep(64)
        params_layout.addWidget(self.height_spin, 2, 1)

        # 视频时长
        params_layout.addWidget(QLabel("视频时长(秒):"), 3, 0)
        self.duration_spin = QSpinBox()
        self.duration_spin.setRange(1, 30)
        self.duration_spin.setValue(5)
        self.duration_spin.setSingleStep(1)
        self.duration_spin.valueChanged.connect(self.update_frames)
        params_layout.addWidget(self.duration_spin, 3, 1)

        # 帧数显示
        params_layout.addWidget(QLabel("总帧数:"), 4, 0)
        self.frames_label = QLabel("81")
        self.frames_label.setStyleSheet("font-weight: bold; color: #0078d4;")
        params_layout.addWidget(self.frames_label, 4, 1)

        # 帧数说明
        frames_note = QLabel("注：16帧 = 1秒，含封面帧")
        frames_note.setStyleSheet("color: #666; font-size: 11px;")
        params_layout.addWidget(frames_note, 5, 0, 1, 2)

        params_group.setLayout(params_layout)
        layout.addWidget(params_group)

        # 生成按钮
        self.generate_btn = PrimaryPushButton(FluentIcon.PLAY, "生成视频")
        self.generate_btn.setFixedHeight(40)
        self.generate_btn.clicked.connect(self.generate_video)
        layout.addWidget(self.generate_btn)

        # 进度显示
        progress_group = QGroupBox("生成进度")
        progress_layout = QVBoxLayout()

        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(10)
        progress_layout.addWidget(self.progress_bar)

        self.status_label = QLabel("准备就绪")
        progress_layout.addWidget(self.status_label)

        self.time_label = QLabel("运行时间: 0.0秒")
        self.time_label.setStyleSheet("color: #666; font-size: 12px;")
        progress_layout.addWidget(self.time_label)

        progress_group.setLayout(progress_layout)
        layout.addWidget(progress_group)

        layout.addStretch()
        return panel

    def create_result_panel(self):
        """创建结果展示面板"""
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setSpacing(15)

        # 结果标题
        result_title = SubtitleLabel("📹 生成结果")
        result_title.setStyleSheet("font-size: 16px; font-weight: bold;")
        layout.addWidget(result_title)

        # 创建Tab Widget
        self.result_tabs = QTabWidget()

        # 视频列表Tab
        self.video_list_widget = QWidget()
        video_list_layout = QVBoxLayout(self.video_list_widget)

        # 滚动区域
        self.video_scroll = SmoothScrollArea()
        self.video_scroll_widget = QWidget()
        self.video_scroll_layout = QVBoxLayout(self.video_scroll_widget)
        self.video_scroll_layout.setSpacing(10)
        self.video_scroll.setWidget(self.video_scroll_widget)
        self.video_scroll.setWidgetResizable(True)

        video_list_layout.addWidget(self.video_scroll)

        self.result_tabs.addTab(self.video_list_widget, "视频列表")

        # 日志Tab
        self.log_widget = QWidget()
        log_layout = QVBoxLayout(self.log_widget)

        # 日志文本框
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setMaximumHeight(200)
        log_layout.addWidget(QLabel("操作日志:"))
        log_layout.addWidget(self.log_text)

        # 清空日志按钮
        clear_log_btn = PushButton(FluentIcon.DELETE, "清空日志")
        clear_log_btn.clicked.connect(self.clear_log)
        log_layout.addWidget(clear_log_btn)

        self.result_tabs.addTab(self.log_widget, "操作日志")

        layout.addWidget(self.result_tabs)

        return panel

    def on_input_type_changed(self, index):
        """输入方式改变"""
        is_url = index == 0
        self.image_url_edit.setEnabled(is_url)
        self.file_path_edit.setEnabled(not is_url)
        self.browse_btn.setEnabled(not is_url)

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
        # 16帧 = 1秒，加上封面帧
        total_frames = seconds * 16 + 1
        self.frames_label.setText(str(total_frames))

    def browse_image_file(self):
        """浏览图片文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择图片文件",
            "",
            "图片文件 (*.png *.jpg *.jpeg *.gif *.bmp *.webp)"
        )

        if file_path:
            self.file_path_edit.setText(file_path)

    def get_image_input(self):
        """获取图片输入"""
        if self.input_type_combo.currentIndex() == 0:  # URL
            return self.image_url_edit.text().strip()
        else:  # 本地文件
            return self.file_path_edit.text().strip()

    def generate_video(self):
        """生成视频"""
        # 验证输入
        image_input = self.get_image_input()
        if not image_input:
            QMessageBox.warning(self, "警告", "请输入图片URL或选择本地图片文件")
            return

        prompt = self.prompt_edit.toPlainText().strip()
        if not prompt:
            QMessageBox.warning(self, "警告", "请输入视频提示词")
            return

        # 检查本地文件是否存在
        if self.input_type_combo.currentIndex() == 1:  # 本地文件
            if not os.path.exists(image_input):
                QMessageBox.warning(self, "警告", "选择的图片文件不存在")
                return

        # 获取参数
        width = self.width_spin.value()
        height = self.height_spin.value()
        duration = self.duration_spin.value()
        num_frames = duration * 16 + 1

        # 禁用生成按钮
        self.generate_btn.setEnabled(False)
        self.generate_btn.setText("生成中...")

        # 重置进度
        self.progress_bar.setValue(0)
        self.status_label.setText("正在初始化...")
        self.time_label.setText("运行时间: 0.0秒")

        # 创建并启动工作线程
        self.current_worker = VideoGenerationWorker(image_input, prompt, width, height, num_frames)
        self.current_worker.progress_updated.connect(self.update_progress)
        self.current_worker.time_updated.connect(self.update_time)
        self.current_worker.finished.connect(self.on_generation_finished)
        self.current_worker.log_updated.connect(self.add_log)
        self.current_worker.start()

    def update_progress(self, value, message):
        """更新进度"""
        self.progress_bar.setValue(value)
        self.status_label.setText(message)

    def update_time(self, message):
        """更新时间显示"""
        self.time_label.setText(message)

    def add_log(self, message):
        """添加日志"""
        self.log_text.append(message)
        # 自动滚动到底部
        cursor = self.log_text.textCursor()
        cursor.movePosition(cursor.End)
        self.log_text.setTextCursor(cursor)

    def on_generation_finished(self, success, message, result_data):
        """生成完成"""
        self.generate_btn.setEnabled(True)
        self.generate_btn.setText("生成视频")

        if success:
            self.add_log(f"✅ {message}")
            self.add_result_video(result_data)
        else:
            self.add_log(f"❌ {message}")
            QMessageBox.critical(self, "生成失败", message)

        self.current_worker = None

    def add_result_video(self, video_data):
        """添加生成的视频到结果列表"""
        self.generated_videos.append(video_data)

        # 创建视频预览小部件
        video_widget = VideoPreviewWidget(video_data, len(self.generated_videos) - 1)
        self.video_scroll_layout.addWidget(video_widget)

        # 切换到视频列表Tab
        self.result_tabs.setCurrentIndex(0)

        # 保存历史记录
        self.save_history()

    def save_history(self):
        """保存历史记录"""
        try:
            history_file = "video_history.json"
            with open(history_file, "w", encoding="utf-8") as f:
                json.dump(self.generated_videos, f, ensure_ascii=False, indent=2)
        except Exception as e:
            self.add_log(f"保存历史记录失败: {e}")

    def load_history(self):
        """加载历史记录"""
        try:
            history_file = "video_history.json"
            if os.path.exists(history_file):
                with open(history_file, "r", encoding="utf-8") as f:
                    self.generated_videos = json.load(f)

                # 重新创建历史视频小部件
                for i, video_data in enumerate(self.generated_videos):
                    video_widget = VideoPreviewWidget(video_data, i)
                    self.video_scroll_layout.addWidget(video_widget)

                if self.generated_videos:
                    self.add_log(f"📚 加载了 {len(self.generated_videos)} 个历史视频记录")
        except Exception as e:
            self.add_log(f"加载历史记录失败: {e}")
            self.generated_videos = []

    def clear_log(self):
        """清空日志"""
        self.log_text.clear()
        self.add_log("📝 日志已清空")

    def cancel_current_task(self):
        """取消当前任务"""
        if self.current_worker:
            self.current_worker.cancel()
            self.add_log("⏹️ 正在取消当前任务...")